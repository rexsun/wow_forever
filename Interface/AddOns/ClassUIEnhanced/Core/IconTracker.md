# IconTracker.lua

Shared factory for the plain-frame icon trackers. `private.IconTracker.CreateTracker(config)`
returns a complete component plus a `ctx` handle for hooks. Used by **CooldownTracker**
(override-bar hooks), **UtilitiesTracker** (hook-free), and every **`spells`-type Additional
Frame** (`AdditionalFrameManager.getIconTracker`).

## Hosted mode (Additional Frames)

Six optional config fields turn the factory from a primary component into an AF renderer. All
are absent for the two primary trackers, whose behaviour is therefore unchanged.

| Field | Absent means |
|---|---|
| `parent` | Factory creates its own top-level container. When present it creates a **wrapper** inside the host and `SetAllPoints`es it — one call, the only geometry it ever writes to anything the host owns. The host keeps sole ownership of positioning. |
| `getSettings` | Reads `private.profile.components[name]` — nil for an AF, which then errors in `getEnabled`. |
| `buildSpellMap` | Derives the map from `CDMDataSource.BuildComponentSpellMaps(categoryId, routeKey, name)`; `categoryId`/`routeKey` are required only in that case. |
| `getOrderRank` | Falls back to `Util.BuildSpellOrderRank`, which returns **nil for any non-CDM component** — an AF would silently sort by ascending spellID. |
| `getAppendRank` | Foreign icons are appended after the sort and always land last (the 12.0 order CooldownTracker's routed trinkets/potions rely on). When present they are merged into the array **before** the sort under synthetic negative ids (`-1`, `-2`, … = negated 1-based append index) and ranked through the same table. |
| `hooks.getAppendFrames` | No foreign icons. |

The tracker shares the host's component name, so its `Anchor` visibility / alpha / strata
queries resolve to the host's own settings; there is never a second registered name. The
factory performs **no** `ComponentManager` or `Anchor` registration of its own.

`container:Show()`/`Hide()` in hosted mode act on the **wrapper**, never the host frame — see
`Core/AdditionalFrameManager.md` for why that does not collide with AF visibility.

**Foreign-icon alpha.** `placeIconButton`'s foreign branch and `SyncAlpha` both multiply
`Util.GetIconAlphaOverride(icon)` into the effective alpha and skip an icon with an in-flight
fade. An Additional Frame runs its foreign icons through `Util.MakeIconVisibilityFilter`,
which parks a faded icon on exactly that override; a flat write would clobber it every layout
pass (`.context/patterns.md`, "every writer of a routed icon's alpha multiplies the
override"). Inert for CooldownTracker — nothing sets an override on the icons it routes,
because the AF filter is the sole writer and CT skips AF-routed slots.

**Foreign-icon re-evaluation is not reachable through `extraWatcherEvents`.** That config
field feeds the swipe watcher's per-event pass, which walks only `activeButtons` and escalates
to a full `Refresh` solely when a *pooled* button's visibility flips. `hooks.getAppendFrames`
runs inside `layoutButtons`, i.e. only inside a full `tracker.Refresh()`, so a host whose
foreign icons need extra events must drive a full `Refresh` from its own watcher — which is
what `AdditionalFrameManager`'s `updateIvmWatcherEvents` does.

## Core

Pooled display-only icon Frames (acquire/release free-list, `Tooltip.Apply` binding at
creation). Merged CDM+custom spell map via
`CDMDataSource.BuildComponentSpellMaps(categoryId, routeKey, name)` — **unioned**; the
`selfAura` half is deliberately not kept as a separate eligibility set. Secret-safe
per-button content refresh, `private.fontsDirty`-gated font pass. The request is latched
per tracker (`fontsOwed`) ahead of the `preRefresh` takeover and disabled returns and
consumed by the next full `Refresh`: CooldownTracker's skyriding bar ends on a dismount
pass, which carries no font pass (`Core/Anchoring.md`).

**Watchers.** A coalesced `SPELL_UPDATE_COOLDOWN` + `SPELL_UPDATE_USABLE` +
`SPELL_RANGE_CHECK_UPDATE` + `SPELL_UPDATE_USES` (the cast-count text, below)
(+ `config.extraWatcherEvents`) swipe watcher escalates to a
full Refresh only on a
visible-set membership change (in combat
too). It also carries `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW`/`_HIDE` (gated by a `procDirty`
flag so the per-frame cooldown pass never re-queries) and a unit-filtered `UNIT_AURA`
("player") **purely as a tick** — the payload is never read — because an aura dropping
implies no `SPELL_UPDATE_COOLDOWN`. Everything coalesces into one pass per frame in a
single `OnUpdate`. A second watcher carries `PLAYER_TARGET_CHANGED` and `UNIT_FACTION` (target and player) for the
target-unit aura containers. Keybind text has no watcher of its own: `OnKeybindsChanged`, which
`Core/Util/Util.lua`'s shared watcher fires once per burst after invalidating the keybind cache
(and only when an action-bar slot's action really changed), redraws **only the keybind text**
of the pooled buttons, through the same `applyKeybindText` helper `refreshButtonContent` uses.
Nothing else the tracker draws reads the action bars (range comes from the
`SPELL_RANGE_CHECK_UPDATE` payload). Two cases keep the full `Refresh`: routed icons are shown
(`lastAppendCount > 0` — their text is re-asserted from the host's settings in the collect,
after their own tracker wrote it from its own), or a hook owns the container (CooldownTracker's
override bar builds its keybinds and slots in its layout).

**Teardown must be exact, because a hosted tracker is disposable.** `Callback.Register` keys on
function identity (`framework.table.addunique`), so an anonymous closure built inside
`Initialize` can never be taken back out — harmless for a component initialized once per
session, fatal for an AF tracker that is created, initialized and discarded on every profile
switch. `Initialize` therefore registers **stable per-tracker closures** (`onCallbackRefresh` for
`OnCDMSpellsChanged`, `onKeybindsChanged` for `OnKeybindsChanged`) behind a `callbacksRegistered` flag; `OnDisable`
unregisters it and both watcher frames, `OnEnable` re-registers every one of them — the
callbacks, `targetWatcher`'s `PLAYER_TARGET_CHANGED` and `UNIT_FACTION`, and `spellWatcher`'s event set (including
`extraWatcherEvents`). Keybind changes arriving through a callback rather than a watcher of the
tracker's own also closes the old asymmetry for good: a disable/enable cycle used to leave
keybind text frozen because nothing re-armed that watcher. Both directions are idempotent, so
a second `Initialize` cannot double-register and an `Initialize` after `OnDisable` does not
leave the tracker deaf.

**No combat-transition refreshes.** At `PLAYER_REGEN_DISABLED` the lockdown has not started, so
a pull-time `Refresh` redrew the pre-combat state already on screen — in the pull frame, where
a `/cueperf` capture measured every tracker's refresh together at 9.5–18.6 ms. On exit,
`Core/Anchoring.lua`'s `OnLeaveCombat` layout pass runs `ContentLayout`, which **is** `Refresh`,
for every visible tracker. See `.context/performance.md` "Combat transitions".

`OnEnable` is not only reached through `ComponentManager.EnableComponent`:
`ProfileManager.FullLayoutRefresh` reconciles every registered component's lifecycle
(`comp.GetEnabled() and comp.OnEnable() or comp.OnDisable()`) and is the tail of
`pm.OnProfileChanged`, and `pm.MakeComponentRefresh` does the same for a single component on a
segmented import. So a tracker disabled through its checkbox and then re-enabled by a profile
switch or an import **is** re-armed; the unregistration in `OnDisable` does not strand it.

This matters beyond memory: a dead spells
tracker's `Refresh` still resolves **live** state through `activeFrames`, so a ghost pass would
release and re-adopt the live frame's foreign icons and `SetPoint` real trinket frames into the
abandoned container.

`OnDisable` also does what `Refresh`'s disabled branch used to do on the next combat
transition, since no such transition reaches the tracker any more: `releaseAppendFrames()`
unconditionally, and the container hide deferred through a **one-shot** `OnLeaveCombat` when
the disable lands inside a lockdown.

Four more things outlive the tracker unless `OnDisable` takes them down, and none is
reachable from a `Refresh` a discarded tracker never receives:

| left live | why it matters | teardown |
|---|---|---|
| the swipe coalescer's `OnUpdate` script | `UnregisterAllEvents` does not clear a script; a pass armed in the teardown frame still ticks | `spellWatcher:SetScript("OnUpdate", nil)` **plus** `swipeDirty = false` |
| the keybind `C_Timer.After(0)` | cannot be cancelled | `bindPending = false`; the timer body drops when it finds the flag cleared |
| all twelve `AuraContainer`s (6 shared + 6 per icon) | `Create` enables them, and only `clearSlotTopology` — reachable only from `syncAuraSlots` — ever switched them off; each keeps parsing every `UNIT_AURA`, engine-side, so Lua memory sampling never shows it | `AuraContainer.Suspend` on each |
| every pooled button's `Tooltip` binding | the module's `tracked` array has no other release path, and a hosted tracker builds a **new** pool per profile switch, so it grows by `#icons` every time and is walked on every combat transition | `Tooltip.Release(allButtons[i])`, re-applied by `OnEnable` |

Both flags live at **tracker scope**, not as `Initialize` locals, precisely so `OnDisable`
can clear them. Clearing the OnUpdate script without clearing `swipeDirty` would be a worse
bug than the one it fixes: the coalescer only installs its script when the flag is low, so a
latched `true` would make it permanently un-installable after a disable/enable cycle.

`Suspend` re-arms on its own — it forgets the container's demand record rather than writing
`false` into it, so the next sync that wants an aura re-enables the container (see
`AuraContainer.md`). The tooltip bindings do **not**: `Release` drops the frame from the
module's array and a pooled button is never re-created, so `OnEnable` re-applies them
explicitly. That asymmetry only bites the primaries — `OnEnable` is never called for a
hosted tracker.

`getEnabled()` is row-safe (`local settings = getSettings(); return settings and
settings.enabled`) for the same reason the deferred hide is: it is what the two pending-work
paths above land on, and a hosted tracker's row is gone by then.

That deferred handler re-checks the settings **row**, not `getEnabled()`. A hosted tracker's
row is `private.profile.additional_frames[id]`, and both AF teardown paths delete it while the
handler is still pending — `manager.DeleteFrame` registers the deferral inside
`deactivateFrame(id)` and nils the row immediately after, and `manager.OnProfileChanged` runs
its deactivate loop over the **old** ids after AceDB has already swapped `private.profile`, so
an id absent from the new profile reads nil too. `getEnabled()` is `getSettings().enabled`, so
either path would raise `attempt to index a nil value` inside
`Callback.Trigger("OnLeaveCombat")` — which has no `pcall`, so the `ipairs` dispatch aborts and
every handler after it is skipped for that trigger. An absent row means the frame is gone, i.e.
not enabled: hide. A primary tracker is unaffected either way, its `components[name]` row
always exists.

The name-keyed registries
(`AuraContainer.RegisterTracker`, `AssistedHighlight.RegisterButtons`) are deliberately left
in place — they hold one entry per component *name*, so a rebuilt tracker overwrites its
predecessor rather than accumulating, and clearing them on disable would break
`AdditionalFrameManager`'s deactivate-all-then-activate-all ordering.

## CDM alert playback

Buttons carry no alert mixin: `Core/CDMAlerts.lua` draws a cooldown Visual alert on its own
overlay parented to the button, never through Blizzard's shared `VisualAlertsManager` pool
(`Core/CDMAlerts.md` "Cooldown Visual alerts never touch Blizzard's pool").

`refreshButtonContent` publishes `button.cue_onCooldown = isRealCD == true` — no separate
duration/GCD gate: `isRealCD` is already "on a real cooldown", and Blizzard's own
`duration > MIN_GLOBAL_RECOVERY_TIME` clause (`CooldownViewer.lua:1002`) can't be reproduced
here since `cdInfo.duration`/`.startTime` are secret in 12.1 (`.context/patterns-secrets.md`).
The `== true` coercion is load-bearing, not cosmetic: for an unused item-category entry,
`cdInfo` (and so `isRealCD`) is nil, and a bare nil published as `cue_onCooldown` would collide
with `CDMAlerts`'s own nil sentinel for "no prior observation yet"
(`Core/CDMAlerts.lua`'s `prevOnCooldown`) — coercing to a real boolean keeps "no cooldown" and
"never observed" distinct.
The swipe watcher's per-button pass (`onSwipeUpdate`) feeds that value straight to
`CDMAlerts.OnCooldownStateChanged(spellID, button.cue_onCooldown, button)` right after the
content refresh, so `Core/CDMAlerts.lua` — not this file — owns the edge detection and the
alert-firing decision. `releaseButton` calls `CDMAlerts.ReleaseButton(button)` before handing a
button back to the free list, so a button re-bound to a different spell doesn't inherit a stale
edge or a running visual alert.

## Layout

Mode-aware grid through the dimension-gated `RelayoutSubtree` resize chokepoint. Full
viewer-layout feature set via `computeGridGeometry` + `Util.ComputeViewerIconLayout(Vertical)`:
horizontal/vertical `layout_direction`, per-line `layout_alignment`, `frame_size_mode`
including the `fixed_width*` single-line modes, `overflow_icon_size` / `overflow_direction`
lines, `min_width`, anchor-inherited width/height caps. Placement mirrors
`AdditionalFrameManager.layoutIcons`.

**Exported shared placement.** `PlaceGrid(settings, componentName, frames, placeFn)` and
`ComputeGridGeometry` own the complete placement contract (direction, per-line alignment so
a partial last row centers on its own count, the `fixed_width*` modes, overflow lines at
their own icon size, `overflow_direction`) and leave only per-frame anchor/styling to
`placeFn` — which is what lets BuffTracker's always-show slot cells reuse it untouched.
`computeGridGeometry` is the single grid-geometry source — the layout pass, this file's
size estimate, and `AuraIconTracker`'s (which is what BuffTracker's `GetComponentSize`
resolves to) all go through it. A simpler `ComputeIconGrid` sat beside it for a while with
no callers left and has been removed.

**Icon order.** `layoutButtons` sorts the visible buttons with `compareByOrderRank`, whose
ranks come from `Util.BuildSpellOrderRank(name, spellMap)` — the component's own
`priority_order` first, then Blizzard's CDM order (the layout blob's `orderedCooldownIDs`
where the player has arranged the CooldownViewer, the DB2 category-set index otherwise)
behind it. spellID is the tie-break, and unranked entries (custom spells, which the CDM has
never heard of) sort last in spellID order so they stay grouped at the end. Sorting by
spellID alone, which this used to do, matched Blizzard only by accident: neither order
source is in spellID order.

The CDM half is scoped to **this tracker's category** — `BuildSpellOrderRank` resolves it
from `CDM_COMPONENT_VIEWER_KEYS[name]`, since each of the four CDM trackers backs exactly
one. A global rank map let a spell with entries in two categories carry its cooldown-bar
position into the buff bar; see `Core/CDMDataSource.md` "Display order".

**Foreign icons** (`getAppendFrames` — CooldownTracker's routed trinkets/potions) are
appended after the spell-sorted buttons and counted into `lastVisibleCount`, the size
estimate and `IsCollapsed`. `placeIconButton` detects them by the absence of `cue_Icon` and
owns only their rect and alpha, since they stay parented to their source container (which
keeps their texture, border, desaturation and text current). The last pass's list is
retained so `SyncAlpha` can re-alpha them without re-running the collector, whose side
effects (`SetIgnoreParentAlpha`, font re-apply) belong on the layout path only.

`placeIconButton` also draws each own button's icon border, passing the spell's
`spell_borders` colour (`Util.GetSpellBorderColor(settings, cue_spellID)`, #8, written by
the Tracking tab's row menu) as `ApplyIconBorder`'s colour: it replaces the global
`icon_border` colour and draws even while that is off. It runs on every layout pass, so an
edit needs no restyle flag here; the lookup returns before the base/override walk while the
map is empty.

`GetComponentSize` under the hide visibility modes (2/4) uses the last laid-out visible
count so it matches the actual container size. When that count is zero it returns `1, 1` —
a deliberate collapse for the primary trackers. A host that needs the opposite (an
Additional Frame holds its configured size so anchored children keep their slot) overrides
that answer on its own side; see `AdditionalFrameManager.md` "Spells frames". Nothing in
the factory branches on the host.

> Note for such a host: `1, 1` is **not** the only empty answer. `spellCount == 0`
> (`lastSpellCount + lastAppendCount`) short-circuits to `0, 0` *above* the hide-mode branch,
> so a tracker whose entire content is foreign icons reports `0, 0` — not the sentinel — once
> the host's filter empties the append list. An override keyed on `1, 1` alone misses exactly
> that case.

**Edit Mode reserves a one-icon box when there is nothing to lay out.** `GetComponentSize`
already estimates `count = 1` under `private.isEditMode`, but `layoutButtons` sized the
container itself to `1, 1` in every mode — so an empty tracker had no rect to grab and Edit
Mode could not select or move it. The `count == 0` branch now runs the same
`computeGridGeometry(settings, 1, name)` the estimate uses, keeping frame and anchor system
on one answer; outside Edit Mode it still collapses to `1, 1`.

An empty tracker is an ordinary steady state, not a startup transient — a CooldownViewer
that reports no known spells leaves every tracker empty for as long as that holds (the case
on a client where the CDM backend is not live yet; see
`.context/memory/project_forever_support.md`). Nothing here asks which client it is: the
tracker fills from whatever the CDM returns, so it lights up on its own if that changes.

## Per-icon visual options

`hide_gcd_swipe` (GCD-only suppression), `gcd_edge_charges` (edge-ring recharge),
`hide_icon` via `Util.ApplyIconVisibility`, fade-mode transitions through
`Util.ApplyIconVisibilityAlpha` (modes 3/5 animate over 0.3 s, everything else instant —
the same helper AF-routed children use, so both surfaces match),
`icon_visibility_treat_charging_as_on_cd` in the GCD-excluding `isSpellOnCooldown` (that
predicate drives the **visibility** modes only — desaturation keys off `isRealCD`, so a
charge spell greys out when its last charge is spent, never while it is merely recharging),
the **usability tint** (below),
`timer_font` via a per-tracker named Font + `SetCountdownFont`, `rotation_highlight` via
`AssistedHighlight.RegisterButtons`, and `GetIconFrame(spellID)` exposing the pooled button
so `Core/Util/ButtonPress.lua` can flash it.

**Usability tint.** `refreshButtonContent` writes `cue_Icon:SetVertexColor`, reproducing
Blizzard's `CooldownViewerCooldownItemMixin:RefreshIconColor` (`CooldownViewer.lua:1209`)
and its `CooldownViewerConstants` colours: out of range `0.64,0.15,0.15`, then usable
`1,1,1`, insufficient power `0.5,0.5,1`, otherwise `0.4,0.4,0.4` — out-of-range outranking
the rest, as it does for Blizzard (`:1227`). Usability is read off the **active** spell for
the same reason the texture and swipe are; range is keyed by the **base** spellID, because
that is what Blizzard registers and what the event carries. An item-backed entry takes the
usable colour unconditionally, exactly as Blizzard does for a spell-less entry carrying a
category (`:1213`), and never range-checks.

Only the *cooldown* trackers do this. `CooldownViewerBuffItemMixin` derives from
`CooldownViewerItemMixin`, not the cooldown one (`:1288`), so Blizzard's buff icons carry no
`RefreshIconColor` either — the aura trackers matching that is parity, not a gap.

This is the addon's only writer of that texture's vertex colour, so no multiply-by-override
dance is needed — but that is the standing invariant, not a coincidence: a second writer
would have to compose with this one (`patterns.md`, "reveal to a default").

It exists because the own-renderer migration dropped it: desaturation covers only the
cooldown, so a spell with **no** cooldown had nothing that could ever dim it. Reported
2026-09-14 as "Execute stays lit up like it's castable permanently". `SPELL_UPDATE_USABLE`
is registered by the factory rather than per component — every instance draws spell icons,
and `SPELL_UPDATE_COOLDOWN` never fires for a spell whose only change is that it became
castable. Blizzard registers the pair together (`:2154`).

**Range is a registration, not a read**, and `ensureRangeCheck` owns it.
`C_Spell.EnableSpellRangeCheck(baseSpellID, true)` must be called before
`SPELL_RANGE_CHECK_UPDATE` fires for a spell at all; the handler then stores the payload's
`checksRange == true and inRange == false` (Blizzard's own reading, `:829` — `checksRange`
false means *no check was made*, e.g. no target, which is not out of range).
`C_Spell.SpellHasRange` gates the registration, as it does for Blizzard (`:740`).

> ⚠️ **The registration is deliberately NEVER released, and that is not an oversight.**
> The enable is a flat per-spell bool, not a refcount (*"False if the spell no longer needs
> the event"*), and Blizzard's own CooldownViewer item frames enable the same spells for
> their own tint (`:743`) — they stay bound while CUE holds the viewers invisible, so they
> never release either. Calling `false` on button release would switch off a check the
> default UI, or another addon, is still relying on. It is session state and is gone on the
> next reload. The cost of holding it is that the event keeps firing for a spell no longer
> tracked: one table store in the handler. That is the cheaper side of the trade.

Both tables (`rangeCheckEnabled`, `spellOutOfRange`) are **module-level, shared by every
tracker instance**, because the registration is global client state rather than per tracker.
Each instance's watcher writes the same value on each event — idempotent, and cheaper than
routing one watcher's events to the others.

`ensureRangeCheck` is also the one place that must never see a secret id:
`EnableSpellRangeCheck` is `SecretArguments = "AllowedWhenUntainted"`, unlike the three read
APIs around it. It never does — the item-backed path, whose spellID can come from
`GetLastCategoryCooldownSource` (`SecretWhenCooldownsRestricted`), returns before reaching
it, and a potion has no range regardless.

The red tint is paired with `cue_OutOfRange`, Blizzard's own `UI-CooldownManager-OORshadow`
atlas at alpha 0.5 (`CooldownViewer.xml:42`, shown at `:1237`). It sits on the button's
`OVERLAY` layer, so the cooldown swipe (a child Frame at +3) draws over it — the same
stacking their item frame has — and is suppressed with `hide_icon`, which leaves nothing for
a shadow to sit on.

`no_range_tint` ("No Out of Range Tint", default `false`) turns the red tint and the shadow
off together; the usability tint still applies. The range registration is unaffected, so
turning it back on takes effect at once.

The CDM ready flash fires via `GlowEffect.PlayReadyFlash` on the `cdInfo.isActive` falling
edge, tinted by `cdm_glow_color`, gated by `hide_ready_blink` and by
`icon_visibility_mode == 2` alone. Mode 2 hides the icon the instant it is ready, so there is
nothing to flash on; mode **3** only fades it, and `hide_ready_blink` is documented as
"Independent of Icon Visibility", so it was suppressing a blink the user had asked to keep.
The `CooldownFrameTemplate` bling is unconditionally off because CDM's own `<Cooldown>` has no
`BlingTexture`.

**Only the HIDE modes (2/4) drop a button out of the grid.** `layoutButtons` used to gate grid
membership on `cue_visAlpha > 0` alone, which caught a *fade* mode configured with
`icon_visibility_faded_alpha == 0` — whose own setting promises the icon "still occupies its
layout slot" — and reflowed the row like a hide mode.

`no_cd_overlay` / `no_cd_overlay_edge_only` (children of `hide_active_swipe` ON) mean "do
not *dim* while on cooldown" — on these plain buttons a swipe recolor (gold tint, or fully
transparent so only the leading edge reads), **not** a suppression of the cooldown. They never
reach the GCD, which has its own overlay (below); when it shared `cue_Cooldown` they tinted it
and put a gold sweep on every icon on every cast.

**The GCD is its own overlay, `cue_GCD`** — 2.13.4's universal one (`Util.GetOrCreateGCDCooldown`,
deleted with the CDM renderer): a dark swipe with no numbers, edge or bling, drawn whenever the
spell is on its GCD regardless of the charge/cooldown routing on `cue_Cooldown`, so it also
sweeps over a recharge. Gated by `hide_gcd_swipe` alone; `hide_cd_swipe` never reached it. It
sits at button+8 (container+9), above the aura takeover (+7/+8) — a GCD sweeps over a buffed
icon, as it did in 2.13.4 — and below the text overlay (+14). `cue_Cooldown` carries only a real
cooldown, a recharge or an item cooldown.

**Blizzard parity for the swipe, the edge and the count** (`CooldownViewer.lua`
`CacheCooldownValues` / `CacheChargeValues`, which drove these visuals before 3.0; pinned by
`tests/cdmparity_check.lua`):

| state | Blizzard | here |
|---|---|---|
| spell cooldown | dark swipe, **no edge** (`:1000`) | same |
| GCD | dark swipe, no edge; hidden under an aura (the aura wins, `:1072`) | dark swipe, no edge, on `cue_GCD` — and over an aura too, as 2.13.4 drew it |
| recharge with charges left | edge, no swipe (`:915`) | 2.13.4's override: full swipe, no edge; `gcd_edge_charges` gives Blizzard's edge-only look |
| every charge spent | falls to the spell cooldown: swipe, no edge | same |
| spell without charges | `GetSpellCastCount`, hidden at 0 (`:1119`), on `SPELL_UPDATE_USES` | same, via `TruncateWhenZero` (the count is secret while cooldowns are restricted) |

The edge was drawn unconditionally until 2026-09-28 — a yellow line round every icon on every
GCD. It now follows 2.13.4 (`Util.ApplySwipeToChild`), not Blizzard: only the two edge-only
modes, `gcd_edge_charges` and `no_cd_overlay_edge_only`, draw it. The takeover's slot Cooldown
also takes `SetUseAuraDisplayTime(true)`, as the CDM's aura display did. The cast count is what shows
Scourge Strike's Lesser Ghoul stacks; the 3.0 renderer drew charges only, so it was lost with
the CDM.

## Override resolution — query the ACTIVE spell

Texture, cooldown, charge and tooltip queries all run against
`C_Spell.GetOverrideSpell(spellID) or spellID`, mirroring Blizzard's
`GetSpellCooldownInfo` / `GetSpellChargeInfo`. `C_Spell` resolves no override on its own,
so a spec replacement — Augmentation's Deep Breath `357210` → Breath of Eons `403631` —
drew the base spell's art and never showed a cooldown (`icon_visibility_mode` reads the same
`cdInfo`, so hide-when-ready was wrong with it).

**The base id stays the key** for everything identifying CDM data or config:
`resolveIconOverride`, the aura-slot set, the button pool, and
`GetKeybindTextForSpell` (action slots hold the base id).

**A spell-rank family on "Highest" is drawn as another spell** (WoW Forever). Every pass
first resolves `display = displaySpell(name, key)`:
- `CustomSpells.GetRankedSpell(name, key)` for a custom entry with `ranks = "highest"`;
- `CDMDataSource.GetRankedSpell(key)` for a whole cooldown family's representative;
- else the key.

The override resolution above then runs on `display`, and so do proc glow, the range check
(`ensureRangeCheck` / `spellOutOfRange`), the keybind text (`refreshButtonContent` and
`onKeybindsChanged`) and the tooltip (`button.cue_displaySpell`). For keybinds this
deliberately breaks the "base id" rule: each rank is its own spell, so an action slot holds
whichever rank the player put there, most often the highest. The key stays the button's
identity: the pool, config, order and alerts.

The base icon reproduces only the conditional-icon half of Blizzard's
`CooldownViewerItemDataMixin:GetSpellTexture` dynamic-appearance path — `conditionalIconID`
outranks `iconID` with `suppress_buff_icon_swap` OFF, `originalIconID` with it ON.

Above both sits the manual `icon_overrides` texture, resolved by `resolveIconOverride`. The
CDM wrapper got this from `Util.ApplyIconOverride` (since deleted) off a viewer child's
`cooldownInfo`, so
the plain-frame pool lost it in the migration and resolves it from the map key instead — and
it walks `GetAuraIdentitySet`, because the Tracking tab keys entries by
`overrideSpellID or spellID` while a tracker's key is `spellID`. An override is the user
pinning a texture, so it also suppresses that spell's swap slot.

### `reverse_swipe` is applied before the cooldown, not after

`SetReverse` is called on `cue_Cooldown` on **every** `refreshButtonContent` pass, above the
`SetCooldown` / `SetCooldownFromDurationObject` branch and outside the "is there a cooldown"
guard. A swipe reads its direction when it starts, so a `SetReverse` that follows the call
that starts it can only ever reach the *next* cooldown — which, on a button whose cooldown is
re-bound from the same duration object each pass, is never. That is how the setting came to
read as dead after the 12.1 rework: the pre-migration renderer set it at the top of its
per-child pass (`Util.ApplySwipeToChild`), so the ordering was right by accident of structure.
Blizzard orders it the same way (`Blizzard_UIWidgetTemplateBase.lua:1314`). The same ordering
applies in `Components/CooldownTracker.lua`'s override frames and `Components/RacialTracker.lua`.

## Item-backed entries (potions and trinkets)

The 12.1 CDM entries that carry no spellID at all — potions by `spellCategoryID`, trinkets by
`equipSlot` — arrive under a synthetic negative key (`Core/CDMDataSource.md`).
`CDMDataSource.GetIconSource(key)` returns non-nil for exactly those, and every C_Spell query
in `refreshButtonContent` branches on it:

| | icon | cooldown | tooltip |
|---|---|---|---|
| potion category | static category art (`SPELL_CATEGORY_ICONS`) | `GetLastCategoryCooldownSource` → the ordinary spell path | none |
| trinket equip slot | `ItemUtil.GetEquipSlotTexture` | `GetInventoryItemID` → `C_Item.GetItemCooldown` → `SetCooldown` | `"inventory"`, the slot |

Each mirrors Blizzard: the category icon outranks all dynamic art
(`CooldownViewerItemData.lua:548`), the equip-slot texture comes next (`:566`), and the two
cooldown sources are its own (`:46` and `CooldownViewer.lua:1024`).

Three secrecy constraints shape this, none optional:

- `C_Spell.GetOverrideSpell` is `SecretArguments = AllowedWhenUntainted`, so the category's
  spellID — secret while cooldowns are restricted — must never reach it. A category is not
  spec-overridable anyway, so it is used raw.
- `C_Item.GetItemCooldown` is **not** `SecretWhenCooldownsRestricted`, so its numbers are
  plain and may be passed to `SetCooldown`, which rejects secrets from addon code.
  `C_Spell.GetSpellCooldown`'s cannot be, which is why the spell path uses
  `SetCooldownFromDurationObject`.
- The potion tooltip is dropped rather than resolved: the last-used item id is secret on the
  same terms, so it could never reach `SetItemByID`.

Charges, keybind text, proc glow, aura slots and swap slots are all skipped — an item-backed
key is not a spellID, so there is nothing for them to ask about, and an aura slot for one
would cost a pooled button and a filter entry that can never match. `icon_visibility_mode`
works normally: a reusable stand-in cooldown table (`itemCooldownInfo`) feeds
`isSpellOnCooldown` the same shape the spell path does, allocating nothing per frame.

## Icon swap (`suppress_buff_icon_swap` OFF)

A separate **engine-driven layer**, because Blizzard's live `linkedSpellID` is secret while
auras are. Three more containers — `<container>_SwapPlayer` (unit player) and
`<container>_SwapTarget` / `<container>_SwapTargetH` (unit target, one per target filter
string, gated like the takeover's: "Target filters and the identity gate" below), since
`SetUnit` is per container and a linked aura may land on either — hold one slot per pool
index whose candidate filter is
`CDMDataSource.GetLinkedIdSet` (**linked ids only**, so the slot shows exactly when Blizzard
would have found a linked spell). Each slot button carries one Texture bound with
`SetIcon`, so the engine draws the art of the linked aura the slot actually matched. The
engine's own show/hide of that button **is** the swap; Lua reads no secret on either side,
so it works in combat, which the old route did not.

**The bind is what makes a multi-link entry right.** Roll the Bones `1214909` carries four
outcome buffs in one entry. The static `GetSwapIconSpell` (`linkedSpellIDs[1]`) texture it
replaced drew One of a Kind whichever buff was rolled. One difference from Blizzard remains:
with two links up at once, the engine picks by its own candidate order, where the CDM takes
the first match in `linkedSpellIDs`.

**The base art is masked out, not covered**, so a faded icon does not show it through the swap.
See "Covered-icon masks" under the takeover below.

With the feature off they are fed the **EMPTY** list, not an all-zero one — a zero list
reads as slot demand, so both containers stayed enabled and registered for `UNIT_AURA`
holding a never-matching slot per pool index (27 on a 9-icon tracker) for a switched-off
feature.

Both containers get the **merged** spell map, never the `selfAura` split: `selfAura` is dead
data Blizzard's own CDM never reads, and the spell that exposed the secret read — Fire
Breath, whose linked aura is a target DoT — reports `selfAura = true`.

**Levels.** Wrappers sit at `container+1` so buttons land at `+2`: above the pooled button
whose base icon they replace, below that button's own cooldown swipe (`+4`, raised from `+2`
for exactly this) so a swapped icon is still darkened while on cooldown, and below the gold
aura spirals. The crop is re-applied every sync (the engine's per-aura write keeps it), so a
size or `icon_zoom` change reaches the swap. It reaches every swap button through the flat
`swapSlotIndex`. The per-index registry that preceded it kept one button per pool index, but a
cell has one per filter per topology, and `SyncSlots` walks filters inside indices. So the
target container's `HELPFUL` button overwrote its `HARMFUL` one, and the dropped button's
texture was never shown: a swap to a debuff on the target never drew. Desaturation is **not** mirrored onto them: the
icon's own branch is a per-refresh read of `isRealCD` and this is a layout-pass sync, so a
swapped icon stays saturated.

Under modes 2-5 a per-button alpha cannot reach a restricted slot button, so the swap slots
take the **same per-icon topology as the aura slots**: `ensurePerIconSlots` builds
`_SwapPlayer<i>` / `_SwapTarget<i>` / `_SwapTargetH<i>` alongside the aura slots in one handle, and
`syncCueAlpha` writes all six wrappers, so a mode 4/5 hide or fade takes the swapped icon
with its icon. Mode 1 keeps the three shared containers. The extra three ride the cue handle
rather than being built on demand — an EMPTY container holds no slot and never registers for
`UNIT_AURA`, which makes one handle, one topology switch and one alpha mirror cheaper than
two of each.

## Aura takeover (`hide_active_swipe` OFF — the 2.13.4 look, re-sourced)

While a tracked aura is up it **owns the icon**, exactly as Blizzard's CDM drew it
(`CheckCacheCooldownValuesFromAura`, `CooldownViewer.lua:885-887`) and as 2.13.4 showed it
by leaving that CDM on screen: the art stays fully coloured, a gold `ITEM_AURA_COLOR` swipe
sweeps the aura's duration with **no edge**, and the **buff's** remaining time is the timer.
Only when it ends does the icon fall back to its cooldown swipe and countdown. Default OFF,
as in 2.13.4 — and the default matters more than it looks: AceDB strips values equal to the
default, so a 2.13.4 profile that never touched the setting has nothing saved and inherits
whatever the default says now.

`hide_active_swipe` alone arms it, as in 2.13.4: `syncAuraSlots` fills `slotTakeover` (pool
index → true) and `restyleSlotButton` / `syncAuraIcons` / `syncIconMasks` read it per index.

**Per spell:** `active_swipe_excludes` (spell ids, written by the Tracking tab's **Options**
menu, `Core/UI/TrackingTab.md`) leaves a spell out of the takeover while the rest keep it
(the user's case: Avenging Wrath's buff is worth seeing, Blood Boil's is not). It resolves base/override pairs
(`Util.BaseOrOverrideInList`), the pandemic excludes' test. An excluded spell's slot is still
armed when `pandemic_glow` or `active_glow` wants it, and then carries only their regions (see
"Off switch"). It has no effect while `hide_active_swipe` is on.

3.0's `show_active_duration` on these trackers
(below) is gone — a key a 3.0 profile saved is ignored, and the Options / Edit Mode widget for
it is Trinket-only again.

> **What 3.0.0 shipped instead, and why it was reverted (2026-09-28).** The pre-3.0
> takeover needed `CDMDataSource.GetAuraState` — a CooldownViewer child walk, per button, per
> refresh — to tell the icon to *yield* its spiral. When that read went, OFF was re-sourced as
> a rotating gold **edge** on top of the icon's own cooldown, the takeover moved behind
> `show_active_duration` (default off), and `hide_active_swipe`'s default flipped to `true`
> (`c1d0bb0`, when OFF still held the CDM keep-alive open). Net effect for an upgraded
> profile: no buff display at all. Reported as "can't bring back the buff icon/timer over the
> abilities". Nothing in the takeover below reads a viewer child — the engine's show/hide of
> the slot button *is* the yield — so neither the border nor the flipped default had a
> reason left.

The takeover is the engine-driven slot button, given three things. The slot Cooldown draws its
**swipe** in `ITEM_AURA_COLOR` — the one case where the slot swipe contends with nothing, since
the copy below covers the icon's own cooldown — unless `hide_cd_swipe`, which in 2.13.4 was a
`SetDrawSwipe` on the CDM's own Cooldown and so hid the buff sweep as well. `cue_AuraIcon` is an opaque
copy of the pooled button's art, `SetAllPoints` to the slot, in full colour unless
`force_desaturation` (below); and the slot
Cooldown's countdown numbers are un-hidden (`SetHideCountdownNumbers(false)`, still gated by
`hide_cd_text`, which now applies to this timer because it *is* the icon's timer while the aura
lasts) and given the tracker's `timer_font` through the same `applyButtonTimerFont` the pooled
button's own countdown uses, so the two are indistinguishable across the handover.

**The copy is what makes "stay coloured" reachable at all.** Whether an aura is up is not
readable in Lua under the 12.1 lockdown, so `refreshButtonContent`'s `SetDesaturated(isRealCD)`
can never be told to hold off — the spell genuinely *is* on cooldown. The engine, however, shows
this button exactly while the aura is up, so a coloured copy on it is the answer to a question
Lua cannot ask. It does the same job for the double-timer: at `container+7` it covers the pooled
button's own cooldown (`container+4`), swipe and countdown included, while staying below the
text overlay (`container+14`), so charges and keybind survive.

`syncAuraIcons` textures the copies, and takes the art from the pooled button's own `cue_Icon`
rather than re-resolving it — `refreshButtonContent` has already settled `icon_overrides`, the
override spell and the conditional-icon precedence, and reading back what it wrote cannot drift
from it. The exception is an armed icon **swap**, which draws at `container+2` and would vanish
under the takeover. For that index the copy is bound with `SetIcon` instead, so the engine
draws the aura the slot matched (for Roll the Bones, the outcome buff that was rolled), and
`ClearIcon` hands it back to the static copy when the swap goes. Each call ends in a full
`UpdateAuraDisplay`, so `auraIconBound` keeps them to transitions. The pass runs *after*
`syncSwapSlots`, which is what makes `swapList` this pass's answer rather than the last one's.

Both of `syncSwapSlots`' gates apply for its reasons: `InCombatLockdown()` **and**
`Util.IsAuraAccessBlocked()`, because the slot buttons carry
`DenyTaintedAccessWhenAurasAreSecret`, the restriction cascades to a texture created on them,
and secrecy outlives combat.

The pooled icon's art is **masked out** while the copy covers it, not left under it to show
through a fade — see "Covered-icon masks" below.

**`force_desaturation` ("Always Desaturate On Cooldown") is the one approximation.** In 2.13.4 it
overrode the CDM's "stay coloured while the buff runs" and greyed the icon *while the spell was on
cooldown* (`isRealCD and not hasRemainingCharges`). The copy is written only by `syncAuraIcons`,
behind those same two gates, so it cannot follow the cooldown state in combat, and the engine has
no desaturation binding (`CustomAuraButtonSharedMixin` has none). It greys the copy for the buff's
**whole** duration instead: identical while the spell is still on cooldown (the usual case),
different when the cooldown ends mid-buff, on a charge spell with charges left, or on a spell with
no cooldown of its own — 2.13.4 showed colour there. `no_desaturation` wins, as before. Chosen by
the user 2026-09-28 over leaving the option removed (`e0dcc56` removed it because the border had
made it meaningless).

A `slotTakeover` change (`slotTakeoverMoved`), `hide_cd_text` and `hide_cd_swipe` are in the
`slotStyle*` diff that marks the restyle pass dirty, so toggling any of them, or one spell's
exclude, applies without a `/reload`; the copy's texture (or
bind) and desaturation are re-applied by `syncAuraIcons`, and the masks by `syncIconMasks`, on
every out-of-combat `Refresh`.

### Covered-icon masks

A cover hides what is under it only at full opacity: alpha applies per region, so under any
fade the pooled icon's art shows through the takeover copy or the swap icon, and this tracker
offers plenty of fades. So every slot button, aura and swap alike, carries a transparent
`cue_IconMask` that the engine shows exactly while the button is up (`bindCoveredIconMask`).
Added to the pooled `cue_Icon`, it erases the art rather than covering it. How the switch
works: `.context/patterns-auracontainer.md` "Where a decoration goes". The binder is exported
as `private.IconTracker.BindCoveredMask` for AuraIconTracker's missing-buff glow
(`Core/AuraTrackers.md`).

**A texture takes at most three masks**, and the client errors past that ("Texture already has
the maximum number of mask textures (3)", live report). A cell has up to twelve slot buttons:
two families (aura, swap), each with the player's filter plus the target's two, in each of two
topologies. So `syncIconMasks` keeps on the icon only the three that can cover it now:

- **the active topology's** buttons, since the other topology is neutralized and never shows
  (`slotPerIcon`, recorded at allocation, says which a button belongs to);
- **the takeover's** where it draws (`slotTakeover`, per index). Its filters are a superset of the
  swap's (same units and strings, identity set over linked ids), so it covers every swap too.
- **the swap's** otherwise. A pandemic / active-glow carrier covers nothing, and its mask would
  erase the icon with nothing on top.

Every removal runs before any add, so a switch never passes through four. `iconMaskOn` keeps it
to transitions (a `hide_active_swipe`, `active_swipe_excludes` or topology change), and the pass runs after both slot
syncs under the same two gates as `syncAuraIcons`. `initButton` no longer adds a square
`WHITE8x8` mask of its own: carried over from the CDM viewer-squaring code, it did nothing on a
plain texture and held one of the three places.

Still covered only, so under a fade they show through faintly: the pooled cooldown's swipe and
countdown numbers, which no mask can reach (it applies to Textures alone), and the out-of-range
shadow. For the cooldown this is the limit, not a gap. The one other engine switch, a clip frame
moved by a collapsing chain of aura buttons, was probed and fails: anything positioned off an
aura button is forbidden to addon code in combat, and this cooldown is written on every cast
(`.context/patterns-auracontainer.md` "Where a decoration goes"). Accepted by the user
2026-09-28: a player who wants the buff shown on the icon is unlikely to fade it. The shadow is a Texture with its own three places, and one mask can mask several
textures, so it could take the same masks; not done.

The factory owns three containers per topology: `<container>_AuraSlots` (player) and
`<container>_AuraSlotsT` / `<container>_AuraSlotsTH` (target, HARMFUL / HELPFUL), wrapper
level `container+5` so the takeover sits above each icon's own cooldown and below the
count/keybind overlay. One `AddAuraSlot` per **pool index** — or, under
`icon_visibility_mode` 2-5, one whole **set per pool index** (`_AuraSlots<i>` /
`_AuraSlotsT<i>` / `_AuraSlotsTH<i>`, same levels).

The **target twins** exist because `SetUnit` is per container: without them a tracked cooldown
whose aura lands on the target — every DoT — got no slot, no button, and therefore no
takeover, no pandemic region and no active border. They matter most for `pandemic_glow`, since
refreshable auras are overwhelmingly target DoTs while the player container mostly sees
long-cooldown burst buffs with no refresh window at all. They carry Blizzard's own two
filter strings (`HARMFUL|PLAYER`, `HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY`), because
`GetTargetAurasFilterString` picks by friendliness while the container's unit is fixed and
the target's friendliness is not.

### Target filters and the identity gate

**One container per string, because only one of them may run.** On 12.1.0 Blizzard's identity
gate fails for a HARMFUL aura on a unit the player can assist, and a failed gate *skips*
`includeSpellIDs` rather than failing it (`.context/patterns-auracontainer.md` "The
identity-filter gate"). The two strings used to share one container per family, which can only
be switched as a whole, so nothing gated them: on a friendly target — self-target included —
`HARMFUL|PLAYER` matched every debuff the player had cast on it, in every cell. Live report
(3.0.1): a self-cast 22-minute quest debuff drawn as the takeover, timer and all, on every
cooldown and utility icon. The HELPFUL string fails the same way on a hostile NPC.

Each target container, aura and swap alike, is armed at creation with
`AuraContainer.GateOnIdentity` for its one string, which keeps it **disabled** while the gate
fails. That is the choice Blizzard's `GetTargetAurasFilterString` makes by reaction.
Disabled, not hidden: a hidden container stops processing and keeps the previous target's
matches, and their covered-icon masks ignore the parent's visibility, so they would go on
erasing the icon. A disabled container clears every candidate.

`retargetSlots` re-gates and then `UpdateAllAuras()`es every target-unit container on
`PLAYER_TARGET_CHANGED` (`SetUnit` early-outs on an unchanged token) and on `UNIT_FACTION`
for the target **or the player** (a reaction flip with no target change moves the gate and
fires no `UNIT_AURA`). The player half is mind control: the player's side flips, the target's
friendliness with it, and `UNIT_FACTION` fires for `"player"` only. Without it the gate stays
stale across the control: during it every icon would light up with the player's bleeds on the
controlling mob, and after it a container disabled by a mid-control target change would stay off
until the next target change. Pinned by `tests/targetgate_check.lua`.

**Why the per-icon topology split exists: alpha.** A slot button is *anchored* to its cell,
not parented to it, so per-icon `cue_visAlpha` cannot reach the cues in its subtree, and the
nearest frame we own is the container's wrapper. `syncCueAlpha` writes each wrapper the same
`effectiveAlpha * cue_visAlpha` its icon gets, so the takeover, pandemic border and
active border fade and hide exactly with the icon.

**Mode 1 keeps the single shared container** because each container costs a `UNIT_AURA`
registration and per-delta bookkeeping for as long as it holds a slot
(`ShouldRegisterForUnitAuraEvents` keys on `HasAnyAuraSlots` and never consults `IsEnabled`,
and there is no `RemoveAuraSlot`). An EMPTY container is free — which is why the shared one
stays eagerly created and per-icon ones are built only for icons that actually arm a slot.
Switching topology **neutralizes** the abandoned one rather than destroying it, so a profile
that visits both keeps paying both until `/reload`.

Neutralizing means feeding `SyncSlots` the **EMPTY** list, not an all-zero one: both give
every allocated slot the never-matching filter, but only the empty list drops the
container's slot demand, so `setContainerDemand` can `SetEnabled(false)` and the container
stops re-parsing auras. That is what makes a toggle actually disarm.

**Cell identity.** A slot's cell is captured once at allocation and pooled buttons are never
destroyed, so "the i-th button ever created" is the only stable cell identity the pool has.
The slot button is `SetAllPoints`'d to it inside `initializeFrame` and rides every layout
move for free. Each pass repoints slot *i* at the spell currently on `allButtons[i]`, or `0`
(matches nothing) when that button is free; the filter is widened by
`CDMDataSource.GetAuraIdentitySet`.

**Every tracked spell is eligible on both units, and the filters decide.** The slots used to
be gated to the `selfAura` subset — the mistake `.context/api.md` records twice over: any
spell CDM mislabels got no slot, and therefore no takeover, no pandemic region and no
active border, silently. A spell whose aura lands elsewhere simply never matches, which
costs nothing. The player filter is `PLAYER|HELPFUL|INCLUDE_NAME_PLATE_ONLY`, matching
Blizzard's own friendly-unit string; without that include flag, nameplate-flagged auras are
dropped from the match entirely.

**Off switch.** The whole engine switches off — every slot to the never-matching filter —
when `hide_active_swipe` is on, **unless `pandemic_glow` or
`active_glow` wants it**: those run the same slots purely as carriers for their regions
(`AuraContainer.AttachPandemic` / `SyncPandemic`, `ApplyActiveGlow`), with every drawn part of
the bound Cooldown suppressed for an index not in `slotTakeover`. The same holds per spell for
an `active_swipe_excludes` entry: unarmed, or a carrier when a glow wants it. Neither mode reads
a viewer child, so neither carries a CDM gate.

Container calls are combat-restricted, so the sync bails under lockdown until the
combat-exit layout pass (`Core/Anchoring.lua`'s `OnLeaveCombat`, which runs `ContentLayout` =
`Refresh`).

Slot buttons are styled through the `AuraContainer` dirty registry
(`RegisterTracker`/`MarkDirty`/`RestyleIfDirty`, re-marked when `reverse_swipe`,
`slotTakeover`, `hide_cd_text`, `hide_cd_swipe` or `fontsDirty` moves). Outside the
takeover the slot Cooldown draws nothing — no swipe, no edge, no countdown numbers; the
takeover gives it the swipe, the numbers and the timer Font (above). Component-level opacity
is pushed to the wrapper.

## CDM keep-alive consumers

**None.** `CDMDataSource.GetAuraState` and the whole keep-alive bridge are deleted; this
file no longer reads a CooldownViewer child by any route, direct or indirect.

The last two consumers went together. `hide_active_swipe`'s spiral yield is now the
engine's own show/hide of the takeover slot (above). `icon_visibility_mode` 2/3 OR'd `auraActive` into `notReady` — "buffing ≠
ready" — and that term was **dropped**, deliberately, to close the dependency: all four
hide/fade modes now key off the real cooldown alone. It only ever differed from `onCD` for
an entry buffed while NOT on cooldown — a GCD-only tracked spell, a charge spender sitting
at full charges, or a buff outlasting its own cooldown. Reintroducing it brings back
`rebuildAuraState`, `Util.GetViewerChildren`, the `needsViewerChildren` predicate and the
viewer-suppression path with it; read `Core/CDMDataSource.md` "CVar ownership" first.

The `UNIT_AURA` tick on `spellWatcher` went with them. It existed only so a buff dropping
out of combat refreshed those two consumers before the next cast; every state these buttons
draw now moves on `SPELL_UPDATE_COOLDOWN`.

`active_glow` is **not** one of them — it is a border on the aura slot button
(`GlowEffect.CreateActiveBorder`, built lazily by `AuraContainer.ApplyActiveGlow` from
`restyleSlotButton`), so the engine shows it and a custom spell with no CDM entry glows like
any other. Static, like the pandemic border, and for the same reason — see
`Core/Util/README.md`.

`proc_glow_*` state is read with `C_SpellActivationOverlay.IsSpellOverlayed` rather than from
the event's payload, which carries the *overlayed* id and diverges from the CDM map key under
an override. It is asked about **both** the CDM key and `C_Spell.GetOverrideSpell` of it: a
replacement spell is overlayed under whichever id the engine treats as active, and the button
draws the override's art while the action slot still holds the base. Base-id-only missed every
replacement — Glacial Spike (replaces Frostbolt / Frostfire Bolt) and Prismatic Bolt (replaces
the next Arcane Blast) never glowed. Blizzard's `RefreshOverlayGlow` asks about the resolved id
alone (`CooldownViewerItemData.lua:216`).

## Hooks (`config.hooks`)

`preRefresh`, `postSwipeUpdate`, `ownsContainer`, `isCollapsed`, `getComponentSizeOverride`,
`getAppendFrames`, `getForceVisible`, `afterInitialize`, `onEnable`, `onDisable`.

> ⚠️ A `preRefresh` takeover parks the pooled buttons at alpha 0, and **every**
> unconditional button-alpha writer must respect that park or the base icons come back.
> `postSwipeUpdate` is therefore consulted at the **head** of the swipe pass rather than
> after its re-alpha loop, and `SyncAlpha` skips its button loop while `ownsContainer` is
> true. See `.context/patterns.md`.

Remaining parity gaps: `.context/migration-parity-gaps.md`.

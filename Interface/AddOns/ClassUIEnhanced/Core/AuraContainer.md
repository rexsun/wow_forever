# AuraContainer.lua

Facade over Blizzard's 12.1 `CustomAuraContainerTemplate`. Full behavioural notes in
`.context/patterns-auracontainer.md`.

There is no load-time template probe. One existed — a throwaway `CreateFrame` wrapped in `pcall`
purely to reword the error — and it was deleted 2026-09-20 with the rest of the addon's `pcall`
use. Clients without the template (every classic client) get LibAuraContainer's emulation, so
creation never reaches a missing template.

Every container in the addon is created through `LibAuraContainer-1.0` (embedded copy in
`libs/LibAuraContainer-1.0/`, a copy of the library's runtime files; re-copy it when the library
changes. Release packaging pulls `cont1nuity/LibAuraContainer-1.0` through `.pkgmeta` instead, so
that repo must carry the same version): `LAC:CreateContainer(name, parent)`, and the enum/defaults reads go through `LAC.*`
(`LAC.FlowDirection`, `LAC.FlowLayoutAxis`, `LAC.SortMethod`, `LAC.SortDirection`,
`LAC.DispelTypeTextureStyle`). On retail and Forever the library is a pass-through:
`CreateContainer` is `CreateFrame("AuraContainer", name, parent, "CustomAuraContainerTemplate")`
returned untouched, and each `LAC.*` field is Blizzard's own table (`AnchorUtil.FlowDirection`,
`AuraContainerSortMethod`, ...). Its emulated container only loads on clients without the
template: MoP, TBC, Wrath and Era.

## Two engines

Components pick per refresh from `always_show_tracked` (`tracker.IsUsingSlots()`); Blizzard's viewer "Hide when inactive" is copied into it once by `pm.MigrateHideWhenInactive`.

**Groups** (compacting) — `SyncGroup(container, key, filter, spellIDMap, initFn, layoutOpts, idSetFor)`
adds or updates an aura group idempotently, skipping the engine calls when a per-group
signature (sorted spell IDs + layout opts) is unchanged. The map is widened first
(`widenToIdentitySets`) through the optional `idSetFor`, which defaults to
`CDMDataSource.GetAuraIdentitySet`. `AuraBarTracker` passes its own `identitySetFor`, so a
by-name custom aura (`CustomSpells.GetAuraIdSet`) widens too. The signature hashes the widened
ids, so a newly resolved name re-syncs on its own.

**Slots** (always-show) — `SyncSlots(container, filters, spellIDs, cellFor, initButton, idSetFor, sigSalt)`
points a container's aura slots at an ordered spell list: one slot per (spell, filter),
keys allocated once (`cue_slot_<filter>_<index>`) and *repointed* via
`SetAuraSlotCandidateFilters` rather than rebuilt — guarded by a spell-order signature
because every such call ends in `UpdateAllAuras()`. Optional `idSetFor(spellID)` widens a
slot to a full identity set (`CDMDataSource.GetAuraIdentitySet`) where the displayed aura
is a linked/override id; the signature stays over the base ids, the widening being a pure
function of them. The one input that breaks that is a by-name custom aura, whose set changes
when its name resolves. The aura trackers therefore add `CustomSpells.GetNameStamp()` to
`sigSalt`.

**Per-spell groups** — `SyncSpellGroups(container, keyPrefix, filter, spellIDMap, idSetFor,
initFor, layoutOpts, rank)` is the third engine: one group per spell, so it compacts *and*
keeps a spellID to key per-spell state by. It is also the only compacting engine whose flow
order is ours — each group's `layoutIndex` is its position in the sorted list, and `rank`
(from `Util.BuildSpellOrderRank`, nil = plain spellID order) decides that sort. The plain
`SyncGroup` engine cannot be ordered at all: Blizzard flows it with
`AuraContainerSortMethod.Default`.

Slot frames are excluded from the container flow layout, so **the caller owns the grid**:
its plain `cell` frame carries the persistent chrome, the slot button carries only the
bound adornments and is anchored to the cell inside `initializeFrame` — which runs
*before* the provider applies access restrictions, so afterwards only the unrestricted
cell is ever moved. Allocation is tracked addon-side because `HasAuraSlot`/`GetAuraSlot`
exist only on Blizzard's private mixin, unlike `HasAuraGroup`.

## Construction

`Create(name, parent, unit)` returns a pre-configured container, player-unit unless a
`unit` is given. **`SetUnit` is per container**, so covering a second unit means a second
container.

`makeInit(componentName, getSettingsFn)` builds the once-per-button `initializeFrame`
closure (icon, stack count, cooldown spiral, timer text — all `cue_`-prefixed addon
regions). The spiral's swipe is set from `hide_cd_swipe` **before** `SetDurationCooldown`, with
the edge turned off as well when the swipe is hidden; see `.context/patterns-auracontainer.md`
"Set a bound Cooldown's draw flags before the bind".

`CreateTextLayer(button)` returns a child frame at `button:GetFrameLevel() + 10`, and every
aura button's stack count is created on it rather than on the button. The icon border
(`Util.ApplyIconBorder`), the active-aura border and the duration Cooldown are all child
**frames** of the button, so a FontString on the button itself draws *underneath* them however
high its draw layer — `SetDrawLayer("OVERLAY", 7)` is a within-frame ordering and cannot reach
across frames, which is why two trackers carried that call and still showed the count behind the
border. Same shape as `IconTracker`'s `textOverlay`. It is safe on a forbidden button on two
counts: nothing in `Blizzard_AuraContainer/` ever adds `Enum.SecretAspect.FrameLevel`, so
`GetFrameLevel` returns a plain number, and `initializeFrame` runs before access restrictions
are applied in any case. A FontString created there is still an indirect **descendant** of the
button, which is all `AuraContainerUtil.ValidateInboundScriptObject` asks for — the bound
`cue_Timer` has always lived one level down, on `cue_Cooldown`.

Call sites: `makeInit` (groups), `AuraIconTracker.initSlotButton`, `AuraBarTracker`'s group and
slot inits, and `OutboundBuffTracker`'s.

Restyle registry for pooled buttons: `RegisterTracker(name, restyleFn)` / `TrackButton` /
`MarkDirty` / `RestyleIfDirty`. All trackers are marked dirty on `OnProfileChanged`;
components bridge `private.fontsDirty` into `MarkDirty`.

## Per-button settings (both engines)

`ApplyTooltip(button, settings)` maps `tooltip_mode` / `tooltip_anchor` onto the button's
**own** tooltip (`SetMouseMotionEnabled` / `SetHideTooltipInCombat` /
`SetTooltipAnchorPoint`) rather than routing through `Core/UI/Tooltip.lua` — the button
already owns a tooltip and knows the secret aura behind it, and `SetHideTooltipInCombat`
is re-evaluated per show, so `out_of_combat` needs no combat callbacks. Called from each
component's `restyleFn`, the only place a button is reliably writable.

`ApplyCdmAlertGlow(button, visualAlertType)` shows or hides the CDM `OnAuraApplied` **Visual**
alert on one button. One frame per *shape* (flipbook vs alpha bounce), created lazily and kept,
because switching type by rebuilding one frame's AnimationGroup is strictly more code than
holding both — and only a spell that actually has a visual alert configured ever builds either.
Engine-agnostic: it lives in the button's own subtree like the active border, so unlike
`SyncProcGlow` it does not need an unrestricted cell. The caller supplies the type, which means
supplying the spell, which slots and per-spell groups can both do and plain groups cannot. See
`Core/CDMAlerts.md`.

`ForEachTrackedButton(componentName, fn)` walks every acquired button of either engine — the
restyle registry is the only place slot buttons and group buttons are held together. It does
**not** gate on aura secrecy the way `RestyleIfDirty` does; the caller decides, because not
every per-button pass writes into the button's subtree.

`AttachPandemic(button, settings, componentName, cell, barFrame)` +
`SyncPandemic(componentName, cells, list, enabled, settings, isBar)` — see below.

> **`syncSlots` ignores the `AddAuraSlot` return, and correctly so — it is the same object as
> the `button` passed to `initButton`.** The provider runs `initializeFrame` at creation and
> `AcquireFrame` returns that frame (`Blizzard_AuraContainerFrameProviders.lua:75-113`). A slot
> button is positionable by addon code whenever auras are not secret, which is what makes an
> engine-collapsing chain (`SetCollapsesLayout`) possible — the prototype anchors the buttons
> `initButton` hands it and captures nothing. See `.context/patterns-auracontainer.md`,
> "Collapsing a slot chain".

## Slots-only

`SyncProcGlow(cells, list, enabled, settings)` drives `proc_glow_*` on the chrome cell.
Every pooled cell is walked so surplus cells and the idle engine clear. Needs no CDM bridge.

State is read as `IsSpellOverlayed`, not from the event payload — which carries the
*overlayed* id and diverges under an override — and it is asked of **both** the CDM key and
`C_Spell.GetOverrideSpell` of it. A spec that replaces a tracked spell carries the overlay
under the replacement's id, so the base-only query this used to do never lit an overridden
tracked buff at all. `Core/IconTracker.lua`'s twin had asked about both since it was written;
this one had not.

**Slots-only is a property of the cue, not just of the implementation.** The overlay means
"this spell is free to cast now", which for a tracked *buff* is typically the moment its aura
is **not** running — so under a compacting engine there is no icon on screen when the cue
fires. On a cooldown tracker the entry *is* the castable spell and the two line up, which is
why that path lives on the button instead.

`ApplyActiveGlow(button, settings)` carries `active_glow` onto the button's own bound
border (`GlowEffect.CreateActiveBorder`, built lazily on the first pass that wants it, so
every init path gets one). **There is no pass and no aura read**: the engine shows the
button exactly while its aura is up, so the border in its subtree *is* the aura state.
That is what makes it work under both engines, while auras are secret, and for a custom
spell with no CDM entry — its predecessor asked `CDMDataSource.GetAuraState`, which reads
a viewer child and answered `false` for every spell without one. Being a feature switch
rather than a state pass, it rides the restyle path like `ApplyTooltip`. Under groups the
button↔aura binding is secret, so there is no spellID to key it by.

## Pandemic regions (both engines)

Rides Blizzard's native `AddPandemicRegion` (12.1.0.69111): the addon supplies a plain
host frame and the engine `SetShown`s it inside the aura's refresh-carryover window. So —
unlike every other per-aura feature here — it needs no CDM viewer child, no
`DurationObject`, and no button↔aura binding, which is why it works under groups as well
as slots and does not go dark while auras are secret.

The border is drawn **on the registered host itself** (`GlowEffect.ApplyEdgeBorder`), so
the engine's `SetShown` drives the pixels directly. It used to hang two frames deeper
(host → overlay → border), putting two addon-owned shown states between the engine's
decision and the art — and nothing in that subtree can be read back, since the bind stamps
`SecretAspect.Shown` on it. For the same reason **"off" is a transparent edge, never a
`Hide`**: once registered, the host's visibility stops being ours to set.

Registration is lazy (on 12.1.0 a registered region costs a per-frame engine OnUpdate for
the life of every refreshable aura) and is removed again when the setting goes off. The
removal key is build-dependent — an index on 12.1.0, the region itself on 12.1.5 / Forever —
so `pandemic_entry.regionKey` stores `AddPandemicRegion(host) or host`.

The **entire** sync — registration *and* styling — is skipped while
`C_Secrets.ShouldAurasBeSecret()`. This is the one per-aura feature whose visuals must
live inside the button subtree, and `DenyTaintedAccessWhenAurasAreSecret` cascades there
even to regions created before the restriction was applied — unlike `SyncProcGlow`, which
rides the chrome cell and needs no gate. That window is **not combat** (it spans whole M+
runs and encounters) and has no event, so a skipped pass is queued and retried on a 1 s
timer armed only while something is outstanding, keyed by section so a later Refresh
supersedes it. The acquire-time registration path is always legal (`initializeFrame` runs
before restrictions apply).

Because the window is Blizzard's and the remaining-% is unreadable, the cue is a **static
border** — shown or hidden, nothing in between. Colour and thickness apply;
`pandemic_glow_style` picks only which side of the edge it draws on
(`border` / `border_inside`); animated styles, urgency colours and thresholds do not apply
at all, and nothing animated can run inside the button's subtree anyway. The per-spell
`pandemic_glow_excludes` need the button's spell: under slots from the cell's index, under
per-spell groups from the `cue_spellID` makeInit stamps. A plain-group button
(`AuraBarTracker`, which has no per-spell engine yet, #47) has neither and follows the
tracker-wide setting.

## The identity-filter gate

Blizzard applies `includeSpellIDs` only when `AuraContainerUtil.CanApplyIdentityCandidateFilters`
allows it. **When it does not, the spell-ID filter is skipped entirely** — every aura
passing the group's filter string is admitted, and a tracked-spell container fills with
untracked auras.

`IdentityFilterHolds(filter, unit)` answers whether the gate holds:
`CanApplyIdentityCandidateFilters` reduced by what the filter string already guarantees,
with the same `canAssist*` arguments, so it reads exactly what Blizzard reads. Owners hide
the failing container themselves — `SetShown` being the one primitive that still works in
combat — on the edges that move reaction: `PLAYER_TARGET_CHANGED`, and `UNIT_FACTION` for the
unit **and for the player**. Being mind controlled flips the player's side, so the target's
friendliness changes with `UNIT_FACTION` firing for `"player"` only; Blizzard's `TargetFrame`
listens to both units for that reason (`TargetFrame.lua:200`).

`GateOnIdentity(container, filter)` is the other repair: it records the filter and ANDs its
gate into the container's demand, so the container is **disabled** while the gate fails; the
owner re-calls it on the same edges. For an owner whose engine-shown decorations outlive a
hidden button — IconTracker's covered-icon masks ignore their parent's visibility. A hidden
container stops processing and keeps its last matches (its dirty pass is `RunWhenVisibleOnce`);
a disabled one clears them (`ParseAllAuras` drops every candidate before its enabled check).
Either repair needs one filter string per container: a container is switched as a whole.

**12.1.0.69465 hotfixed the player-side half**: HELPFUL on the player, a group member or
their pets is now unconditional, and both `UnitCanAssist` calls pass the
immune/uninteractable overrides — so cutscenes, vehicles, charms and teleports no longer
open the gate, and the recovery pass that watched `UNIT_FLAGS`/`PLAYER_CONTROL_*`/vehicle
edges is gone. What remains fails on **every** evaluation and no re-parse repairs it: the
cross filters of a two-filter target block — `HARMFUL|PLAYER` on a friendly target,
`HELPFUL|PLAYER` on a hostile NPC.

The same gate makes an **all-empty container the worst case, not the safe one**: nothing
tracked means nothing but the empty map standing between the filter string and every aura
on the unit, and with no tracked spell there is no chrome either, so the leak shows as
adornments floating with no icon. `SyncGroup` / `SyncSpellGroups` / `SyncSlots` therefore
report whether their section wants anything into a per-container demand table, and the
container is `SetEnabled(false)` when none does — `ParseAuras` early-returns on a disabled
container, so the gate has nothing to widen. Demand is tracked rather than recomputed
because the toggle runs a full rebuild.

`Suspend(container)` is the teardown form of the same switch: it **forgets** the container's
demand record and disables it. Clearing the record is load-bearing — the demand writer
early-returns on an unchanged value, so the stale `true` a bare `SetEnabled(false)` leaves
behind would swallow the next sync's re-enable and leave the container dark for the session.
With the record empty, the first sync that wants an aura re-enables it, which is the only
resume path there is. (Writing `false` into each section would clear that hazard too, since
`false ~= true` proceeds; `wipe` is preferred because it also drops sections that will never
be re-synced.)
`IconTracker.OnDisable` calls it on all four shared containers and all four per icon;
without it a hosted tracker (rebuilt on every profile switch) leaves one more live set
parsing every `UNIT_AURA` behind each time.

Surplus slots (and the idle engine during a mode switch) take `includeSpellIDs = {}`,
which matches nothing — the per-slot off switch, since neither engine has a public removal
API. **It only holds while the gate does.**

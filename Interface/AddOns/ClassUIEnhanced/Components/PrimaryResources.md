# PrimaryResources

DF power bar. Auto-hides mana for mana-using DPS/tank specs that don't benefit from it; per-class opt-ins (`arcane_mana_bar`, `paladin_mana_bar`, `evoker_mana_bar`, `druid_mana_bar` for Guardian, `shaman_mana_bar` for Elemental/Enhancement, `balance_mana_bar` for Balance, `priest_mana_bar` for Shadow) force it back on. Value text positioned via `ApplyFontProfile` using `value_font` anchor_point/offsets.

Below PlayerHealthBar. Defaults: 200×20.

## Spec and form changes

Auto-hide is re-evaluated by `specEventFrame` (`PLAYER_SPECIALIZATION_CHANGED`,
`UPDATE_SHAPESHIFT_FORM`, `PLAYER_ENTERING_WORLD`), which **registers in `Initialize` and is
never unregistered** — the same shape as SecondaryResources' `talentEventFrame`. Two reasons,
both of which made a mana ↔ non-mana spec switch need a `/reload`:

- the login path calls `Initialize` → `Refresh`, never `OnEnable`, so a registration there
  only happened after a component toggle or profile switch;
- auto-hide is a `GetEnabled()` false, so `FullLayoutRefresh` calls `OnDisable` for it — and
  an `OnDisable` that unregistered the listener switched off the one event able to bring the
  bar back.

The handler relayouts on every spec change and loading screen, but on a form shift only when
`Refresh` recorded an enabled flip (`lastEnabled`): shifts are frequent and each relayout is a
full `Anchor.Refresh`. Pinned by `tests/primaryspec_check.lua`.

## Every spec-keyed decision goes through `getRealSpecIndex()`

`C_SpecializationInfo.GetSpecialization()` answers with an index on **every** client,
including one that has no specialization system at all — it returns `1`, which the auto-hide
gates read as the class's first retail spec. For a Druid that is Balance, so `auto_hide`
resolved "Astral Power lives on the secondary bar, mana is redundant" and disabled the whole
component for a character whose only resource *is* mana.

> ⚠️ **Neither obvious test for "is this a real spec" works.** A non-nil index does not mean
> a spec system exists, and neither does a non-nil specID: on WoW Forever a level-1 Druid
> reports index `1` resolving to specID `1484`, named *"Druid"*, role `DAMAGER` — a genuine
> row, simply not one of retail's (DB2 `ChrSpecialization` ends at `1480`). A probe written
> against `GetSpecializationInfo` returning nil is inert there.

`getRealSpecIndex()` gates on **`GetNumSpecializations()`**, which is Blizzard's own
authority for the class's spec list — `IsInitialSpec` is
`specializationIndex > GetNumSpecializations()` (`Blizzard_SharedXML/UnitUtil.lua:9`). Retail
classes report 3 or 4; a client with no spec system reports 1. Both spec-keyed reads in this
file (`primaryManaOverrideSpecs` in `getPlayerPrimaryPowerType`, and the DAMAGER/TANK role
gates in `getEnabled`) go through it, and where the count is 1 both fall through to the
permissive branch: the native `UnitPowerType` is reported, and the bar stays enabled.

The `DAMAGER` branch is why the gate has to sit *outside* the per-spec tests rather than
replacing them. It ends in a catch-all `return false`, which is correct on retail — every
mana-using DPS spec there really does keep its combat resource elsewhere — so a specless
client would fall past every opt-in and into it.

This is a data test, not a client test: no build or flavour check anywhere in the path. A
client that gains a spec system raises the count and the existing per-spec behaviour applies
unchanged, with nothing to unwind. The ceiling is written at the call site — the indexes
compared inside are retail's, so a multi-spec client on a different numbering would need
specID comparisons instead. `isAugmentationEvoker()` still reads the raw index; it is already
guarded by a class check no specless client can satisfy.

## Mana override for caster builder/spenders

Elemental Shaman, Balance Druid, and Shadow Priest natively report their combat resource (Maelstrom / Astral Power / Insanity) as the primary power. Those resources are shown on the SecondaryResources bar instead, and the primary bar tracks **mana** for these specs.

The override lives in `getPlayerPrimaryPowerType()` — returns `Enum.PowerType.Mana, "MANA"` for the three specs (keyed by `primaryManaOverrideSpecs`), else the native `UnitPowerType`. It is routed through the auto-hide token check, the `override_colors` token lookup, and the spend-prediction gate, and applied to the DF bar by wrapping `UpdatePowerInfo`: DF re-derives `powerType` from `UnitPowerType` on every `UpdatePowerBar` (UNIT_DISPLAYPOWER / SetUnit / PLAYER_ENTERING_WORLD), so the wrap re-applies the override after the DF body runs; the alternate-power raid bar (`ALTERNATE_POWER_INDEX`) is left untouched. The mana bar is hidden by default (auto-hide); the per-class opt-in shows it.

## Breakpoint pips

Rendered by the shared `private.BreakpointPips` module (`Core/Util/BreakpointPips.lua` — see `Core/Util/README.md`); this component only owns a host table (`pipHost`, created once and mutated in place: `bar`/`key` set in `Refresh()` before `Apply`, `baseColor` referencing the `cachedBarColor` mirror). `UpdatePower` runs the allocation-free `UpdateDynamic` per power tick; the disabled branch of `Refresh()` calls `Clear`. Storage key: plain `"CLASS-spec"`, except the three mana-override specs which use `"CLASS-spec-MANA"` (their combat-resource pips live on the SecondaryResources continuous bar under `"CLASS-spec-<TOKEN>"` — see `MigrateBreakpointPipKeys` in ProfileManager for the legacy-key migration).

## Spend prediction

`spend_prediction`: reverse-fill StatusBar overlay on the mana bar showing the cost of the current cast; secret-safe via `SetValue` (AllowedWhenTainted) with `SetMinMaxValues(0, currentPower)`.

## Five-second rule (WoW Forever)

`five_second_rule` (default on): WoW Forever keeps vanilla's rule that Spirit-based mana regen pauses for 5 s after mana is spent. A spark crosses the bar over those 5 s, left to right (a vertical bar: bottom to top). `five_second_rule_size` (default `"full"`) picks the band it covers across the bar: all of it, or its top or bottom third (`FSR_BANDS`; on a vertical bar the band is measured from the left, the top under its +90° text rotation). Gated on `HAS_FIVE_SECOND_RULE` (`ClientScope.CLIENT == "forever"`, interface `16000`–`19999`): no API names the rule, so the interface number decides. The Options toggle is hidden elsewhere.

`fsrFrame` (child of the bar) carries both halves. It registers `UNIT_SPELLCAST_SUCCEEDED` for `"player"` only while the bar shows mana, and restarts only when `C_Spell.GetSpellPowerCost` lists a mana entry: wand Shoot and Auto Shot fire the event every shot without spending mana. While shown, its `OnUpdate` positions the spark from `GetTime()` and hides the frame at 5 s, so a hidden bar resumes at the right spot and costs nothing when idle. A form shift away from mana runs `Refresh`, which stops it; the rest of that window is not shown when mana comes back. Whether a cast made free (Clearcasting) still lists its mana entry, and so restarts the spark, is unchecked. `fsrFrame` is re-levelled to the bar's +2 on each `Refresh`, so the spark rides above the breakpoint pips (OVERLAY regions of the bar itself) and the spend-prediction child (+1), and under `ApplyBarBorder`'s overlay (+5) carrying `percentText`. Spark width (`FSR_SPARK_WIDTH`) and its length of twice the band were picked by eye. Pinned by `tests/fivesecondrule_check.lua`.

## Augmentation Evoker Ebon Might mode

`augmentation_ebon_might`: replaces mana with an Ebon Might duration bar. **ALL auras — self-cast buffs included — are fully secret in combat** (live-confirmed 2026-07-23), so `C_UnitAuras.GetPlayerAuraBySpellID(395296)` returns nil exactly when the bar matters; the fill and remaining-time text are engine-bound through the `ebonMightTap` "ebonmight" aura slot (`SetDurationBar` with `StatusBarTimerDirection.RemainingTime` + `SetDurationText` — see the tap section below). The self-aura's `points` only carry percentage coefficients (e.g. `[1]=20` for the +20% damage buff), not the computed main-stat grant — the stat number only materializes on ally auras, and resolves out of combat only. **The Duplicate window is engine-bound the same way** (the `"duplicate"` slot below); nothing CPU-side simulates it, because the extension deltas that would drive such a sim come off the secret Ebon Might aura. **Text layout**: the engine-bound **Duplicate** remaining time sits centered ON the bar — the readout the player watches — with the engine-bound **Ebon Might** remaining time at the left inset (bottom for vertical) and `percentText` (stat readout) yielding the centre to it for the right inset (top for vertical); `percentText` is restored to the `value_font` profile anchor on every mode-exit path. `percentText` stays above the engine fill by **frame level within the bar's own strata**: `applyEbonMightTapSettings` gives the UIParent-rooted tap container the bar's strata and `powerBar` level + 2, so slot buttons sit at +3 and the bound StatusBar at +4 — one under the `ApplyBarBorder` overlay (+5) that parents `percentText`. Slot buttons are plain children of the container (`Blizzard_AuraContainerFrameProviders.lua:76`) and nothing in `Blizzard_AuraContainer` sets a level or strata. **Never lift either with a fixed strata:** the earlier `HIGH` container plus `DIALOG` overlay drew the fill through Blizzard's Settings panel (`HIGH`) and the bar border through CUE's options and Edit Mode (both `DIALOG`) — live report 2026-09-16. The Double Time countdown anchors below-right, outside the bar.

**Ally scan:** When a new self-instance appears (fresh cast), we schedule a 0.1s delayed scan of `party1..4`/`raid1..N` and for each ally iterate all helpful auras via `AuraUtil.ForEachAura(unit, "HELPFUL", nil, cb, true)`, picking the Ebon Might (spellID 395152, separate from the self ID 395296) whose `sourceUnit` matches the player. Iterating rather than calling `GetUnitAuraBySpellID` is required in raids where multiple Aug Evokers may have buffed the same ally — the single-aura API would pre-pick the wrong instance.

**Stat value:** We take the matched aura's `points[2]` as the stat value (`points[1]` is a static nominal coefficient ~8, `points[2]` is the live stat value ~intellect × effective %). The matched ally is cached as the reference unit. Ebon Might updates the ally's `points[2]` dynamically as the caster's Intellect changes mid-buff (trinket procs, gear swaps), so a 1s `C_Timer.NewTicker` (`augmentation_ebon_might_live_update`, default on) re-reads the reference ally's aura to keep the displayed value in sync; if the reference drops the buff, dies, or leaves, it falls back to a full group scan. The poller short-circuits when the player doesn't currently hold the self Ebon Might, so it never picks up another Aug's buff on a nearby ally.

`augmentation_ebon_might_show_stat` appends that value (abbreviated) to the bar text. `augmentation_ebon_might_show_duplicates` (default off) shows the remaining Duplicate duration via the engine-bound `"duplicate"` slot text centered on the bar. Hidden when no Duplicate is active.

### Crit detection

Ebon Might crits apply **Double Time** as a real, trackable buff on the Evoker (15s base, Mastery-scaled, extended on re-crit; CDM TrackedBuff cooldownID 198923 → base spell 431874, linked aura 460688). The display is entirely engine-driven through the aura tap below — the engine Shows the `"doubletime"` slot button exactly while the buff is up, and the pulsing border glow is that button's child. Nothing CPU-side derives crit state, so `augmentation_ebon_might_crit_glow` and `augmentation_ebon_might_crit_color_value` (the glow's border colour, default pale-gold `{1.0, 0.95, 0.55, 1.0}`) are the whole feature. `IsCritDetectionAvailable()` (i.e. `IsPlayerSpell(431874)`) soft-disables the Options toggles for specs without the talent, where the stat grant is deterministic and no crit exists.

### Ebon Might aura tap

A 1×1 `CustomAuraContainerTemplate` container (`CUE_PR_EbonMightTap`, UIParent-rooted, addon-owned) hosts **three** aura slots: `"ebonmight"` (filtered to `{395296}`) binding a StatusBar via `SetDurationBar` (`direction = RemainingTime`; engine drives `SetTimerDuration` on every aura update) plus a centered `SetDurationText` FontString created ON the bar (a child frame renders above its parent's regions) — this IS the Ebon Might fill + remaining-time display on 12.1 — `"doubletime"` filtered to `{431874, 460688}` for the crit signal, and `"duplicate"` filtered to `{1259171}` for the Duplicate window's remaining time (CDM TrackedBuff cooldownID 94196 → base spell 1259174, the passive talent node, with linked aura 1259171; only the linked id carries the buff, so only it is filtered). The engine Shows the slot button while the buff is present and Hides it when it drops (`Blizzard_ManagedAuraContainer.lua:199/209`), so decorations parented to the button render exactly during the Double Time window with zero addon branching on secret aura state. Anchoring model (mirrors SecondaryResources' bar-slot precedent): ONE cross-frame edge — the button `SetAllPoints(powerBar)` (dependent→plain direction, live anchor tracks bar moves/resizes) — with everything else in-family on the button:

- **Glow**: BackdropTemplate border child pulsing via a permanently-`Play()`ed BOUNCE alpha animation (renders only while the button is shown — no addon start/stop needed or possible in combat); border colored from `augmentation_ebon_might_crit_color_value`, shown per `augmentation_ebon_might_crit_glow`. There is deliberately **no fill/tint overlay**: any region spanning the bar rect renders in the tap's layer, above the bar's fill and text, and masks the Ebon Might duration readout (live incident 2026-07-23) — and re-coloring only the fill would need an unverified second cross-frame anchor to `powerBar.barTexture`.
- **Duration text**: FontString created on the button pre-bind (font before bind — the bind pushes text immediately) and engine-bound via `button:SetDurationText(fs)`; anchored past the bar's RIGHT (horizontal) or TOP (vertical); shown per `augmentation_ebon_might_double_time_text` (default on).
- **Duplicate text**: same pre-bind pattern on the `"duplicate"` slot button, centered ON the bar; shown per `augmentation_ebon_might_show_duplicates`. No stack count is composed — the engine Shows the button exactly while the buff is up. **Ceiling:** one slot, so a second concurrent Duplicate would not render. That is unreachable at current gear but expected to come back; the upgrade is `AddAuraGroup("duplicate", …)` with `maxFrameCount = 2` (Blizzard flow layout, one button per instance) in place of the slot.

Lifecycle: `ensureDoubleTimeTap()` (creation; OOC-only, retried from every Ebon-Might-mode Refresh) → `applyDoubleTimeTapSettings()` (anchors/colors/toggles; single load-bearing `C_Secrets.ShouldAurasBeSecret()` gate at the top — every write below touches the button or its children, all forbidden while auras are secret; skipped passes retry next OOC Refresh) → `resetEbonMightTracking()` Hides the container on mode exit (container itself is addon-owned, safe in any state). No Edit Mode preview: the button legitimately hides with no aura, and Ebon Might mode is skipped in Edit Mode anyway. In-game PTR verifications outstanding: button→powerBar cross-anchor survives a secrecy transition; `Hide()` on the bound duration FontString sticks across engine text updates.

### Ratio heuristic (removed)

Before Double Time became a trackable buff, crit was inferred from a `points / playerIntellectCache` ratio against a roster-normalized baseline `K = ratio × aliveDps ÷ duplicateFactor`, with a 1.4 threshold sitting below WoW's ~1.5× crit multiplier. It was already skipped on every shipping client behind an `IS_121` build gate, because both its inputs are secret in combat there: `UnitStat("player", 4)` zeroes the denominator and the ally `points[2]` read resolves out of combat only. The whole path is deleted — the baseline, the alive-DPS and Duplicate-stack counts, the Intellect snapshot with its combat-potion correction (and `ConsumableTracker`'s `RequestPotionTracking` / `GetActivePrimaryPotionInt` soft-enable machinery, whose only consumer it was), the `PLAYER_REGEN_*` / `PLAYER_EQUIPMENT_CHANGED` registrations that fed it, the CPU-side Duplicate window simulation, and the `augmentation_ebon_might_crit_color` bar-shift toggle it drove.

**Do not rebuild it.** Crit state has no readable CPU-side source while auras are secret; the aura tap above is the only working display path, and it renders without the addon ever knowing whether a crit happened.

### Extension preview and danger colouring (removed)

Both were built for the pre-12.1 client and were already disabled on 12.1 —
`isEbonMightExtensionDangerous` returned false, `updateEbonMightExtensionOverlay`
hid and returned, `registerEbonMightExtensionEvents` was a no-op, and Options
stripped the two toggles out of its own widget list after building them. The
whole subsystem is now deleted: the preview texture, the extension amount table,
the cast-lifecycle event frame, the simulated expiry/total clock and its spell-
description duration seed, and the `augmentation_ebon_might_extension_preview` /
`augmentation_ebon_might_danger_color` profile keys.

The reason it cannot work is not going to change on its own: each extension's
real amount depends on a secret crit roll (Double Time), so an addon-side sim
systematically under-estimates remaining and total, the preview seam drains
faster than the engine fill and slides behind it, and the danger alert fires far
too early. **If picked up again, do not rebuild the sim.** The two designs that
survive the secrecy rules are (a) an END-ALIGNED chip of width `ext / base`
pinned to the bar edge, which claims no seam position, and (b) an
engine-evaluated threshold warning via `SetTextColorCurve(curve,
Enum.DurationTextBindingProperty.RemainingDuration)` on the bound duration text
— the engine compares the real secret remaining against a colour curve built out
of combat, so it is exact, but threshold-based rather than cast-aware.

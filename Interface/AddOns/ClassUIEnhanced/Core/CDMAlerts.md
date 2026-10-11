# CDMAlerts.lua

CUE holds every CDM viewer at alpha 0 (`Core/CDMDataSource.md`, "Viewer suppression") — the
addon's whole point is to draw its own icons instead of Blizzard's. Suppression is NOT what
kills Blizzard's own per-item alerts: it writes alpha and mouse only, so a viewer Blizzard
shows stays shown, just invisible, and `CooldownViewerMixin:OnShow`/`OnUpdate`
(`CooldownViewer.lua:1733`/`:1747`) — the sound/text-to-speech/visual alert clock — keeps running
underneath ours. Two things do kill those alerts, and neither is reachable from here: the
ordinary CVar-off path most CUE profiles run under, where `ShouldBeShown`
(`CooldownViewer.lua:1897`) returns false before a viewer's own `visibleSetting` is ever
consulted; and the player's own "Hidden" / "In Combat" setting on that viewer, which since the
`visibleSetting` soft-override was deleted genuinely hides it (`Core/CDMDataSource.md`, "The
soft-override — removed"). Either way there is no `OnShow` and no `OnUpdate` at all.
`CDMAlerts.lua` reads Blizzard's own alert configuration and replays it from the addon side, so
turning the CDM's pixels off — by any path — does not also turn off the alerts the player
already set up for it.

It is first a **replay** of what the player authored in Blizzard's Cooldown Manager settings
window. A spell can also carry **CUE's own alert list**, edited from the Tracking tab's
**Alerts** menu, which replaces the Cooldown Manager's list for that spell (see "CUE's own
entries" below). Blizzard's data is never written either way. The one Options widget this
module owns (`cdm_alerts`) is the master on/off switch for both sources.

## The gate: `viewer:IsShown()`, not the CVar, not alpha

`blizzardOwnsAlerts(categoryId)` resolves the category's viewer (`Util.GetViewerFrame`) and
asks only `viewer:IsShown()`. Every other candidate is wrong in a way that matters:

- **The `cooldownViewerEnabled` CVar answers a different question in both directions.** CVar
  *on* does not imply Blizzard is firing: a viewer whose own `visibleSetting` resolves to
  Hidden is genuinely inert regardless of the CVar — `OnHide` unregisters everything `OnShow`
  registered, and a hidden frame runs no `OnUpdate`, which is the alert clock. That is also the
  *common* CUE setup: `CDMDataSource.EnsureEnabled` turns the CVar on only for `cdm_target_sounds`, so most
  characters run with the CVar off yet the viewers are still driven through `SetShown`. CVar
  *off* does not imply silence either — EditMode short-circuits `ShouldBeShown` and can show a
  viewer with the CVar off.
- **Suppressed ≠ hidden.** Suppression writes **alpha and mouse only** (`Core/CDMDataSource.md`)
  — it never touches shown state in either direction. A suppressed viewer Blizzard is showing
  still ran `OnShow` and is still ticking `OnUpdate`, so Blizzard's alerts really do still fire
  for it. Gating on "is CUE suppressing this viewer" would silence exactly the alerts this module
  exists to keep alive.

`viewer:IsShown()` is the one read that resolves every case, because it *is* what gates
Blizzard's own `OnShow`/`OnHide` registration. The gate is evaluated **per category/per
viewer**, never globally — a player can have one CDM category actually visible (Blizzard still
owns its alerts) while CUE replays the other three.

> ⚠️ **The gate governs AUDIBLE alerts only — sound and text-to-speech. Visuals always play.**
> A CUE visual is drawn on CUE's own icon, never on Blizzard's, so it cannot double theirs; and
> behind a CUE-suppressed viewer theirs renders at alpha 0, where nobody sees it. Blizzard's sound
> has no such escape — `CooldownViewerAlert_PlaySoundAlert` is a bare
> `C_Sound.PlaySoundWithOptions` with no visibility test (`CooldownViewerAlert.lua:171`) — so that
> half keeps the gate. Gating visuals too left every CDM glow dark whenever the player had hidden
> the Cooldown Manager through CUE (reported 2026-09-10).

**An item category always answers `false`, and the read is skipped entirely.** Categories 5-8
(`SpecAgnosticEssential`, `SpecAgnosticTracked`, `EquipSlotEssential`, `EquipSlotTracked`)
render in **no viewer at all**: every `CooldownViewerMixin:GetCooldownIDs` filters on
`cooldownInfo.category == self:GetCategory()`, and the four viewer categories are hardcoded 0-3
in `CooldownViewer.xml` (`:303/314/325/336`). So Blizzard's alert clock never runs for an entry
left in its default item category, and `Util.GetViewerFrame` could not be asked about one
anyway — it asserts `0 <= categoryId <= 3`.

## Item categories and the trinket bridge

`MODEL_CATEGORY_IDS` walks 5-8 alongside the four classic categories. An alert is configured on
the **entry**, not on wherever the entry currently sits, and a trinket the player has not
dragged into Essential/Utility stays in an item category — which used to put its alerts in
nobody's model: not Blizzard's, because no viewer renders that category, and not ours, because
the walk stopped at 3. CUE draws that trinket regardless, through
`Components/TrinketTracker.lua`.

> ⚠️ **That is a THIRD list, and merging it into `ALERT_CATEGORY_IDS` is a live bug, not a
> tidy-up.** `ALERT_CATEGORY_IDS` also answers "which viewers are there to hook", and
> `installAllAuraViewerHooks` feeds it straight to `Util.GetViewerFrame`, which asserts
> `0 <= categoryId <= 3`. Widening it in place threw on the first item category — at the very
> first line of `performRebuild`, so the whole model, cooldown side included, was never built
> and every alert went silent. Pick the list by the consequence you mean.

That component is the one consumer that cannot address the model by tracker key: it reads the
equipped item straight off inventory slot 13/14 and has never held a cooldownID. So the rebuild
also indexes `equipSlotKey[equipSlot] = key` for every alert-carrying entry whose
`CDMDataSource.GetIconSource(key)` reports an `equipSlot`, and
`CDMAlerts.OnEquipSlotCooldownChanged(equipSlot, onCooldown, icon)` is the same edge published
by slot instead of by key. TrinketTracker's own poll already resolves `isOnCooldown` for both
the on-use and the proc-ICD shape, so the call sits next to its existing
`icon.wasOnCooldown` edge and CDMAlerts does its own edge detection on top.

A slot with no alert-carrying entry returns before touching `prevOnCooldown`, so the first edge
after one appears is swallowed exactly as a freshly bound pooled button's is.

The icons need no alert mixin: a cooldown Visual alert is drawn on an addon-owned overlay
parented to the icon (see "Cooldown Visual alerts never touch Blizzard's pool").

## Two mechanisms, two enforcement points

The cooldown side and the aura side need different plumbing because of what the 12.1 aura
lockdown allows an addon to observe.

**Cooldown alerts (`Available`/`OnCooldown`) re-check the gate at fire time and are
self-correcting.** `OnCooldownStateChanged` calls `blizzardOwnsAlerts` fresh on every edge, so
if a viewer's shown state changes between rebuilds, the very next transition simply stops (or
starts) firing its audible alerts on its own; a Visual alert in the same bucket plays either way. No teardown bookkeeping is needed because there is nothing standing
to tear down — the "registration" is just a table lookup consulted at the moment of firing.

**Aura sounds (`OnAuraApplied`/`OnAuraRemoved`) are the opposite: standing engine-side
registrations with no fire-time check.** `C_UnitAuras.AddAuraSound` hands the *engine* a
trigger/spellID/sound and the engine plays it on its own from then on, with no addon callback —
there is no hook this module could re-check a gate from at fire time. So the enforcement has to
happen at the other end: every `AddAuraSound` id this module creates must be actively removed
the moment its owning viewer becomes shown, or Blizzard's alert and this module's registration
would both fire. That is what the per-viewer `OnShow`/`OnHide` → `CDMAlerts.Rebuild()` hooks
(`installAuraViewerHooks`) are for, and why `reapplyAuraRegistrations` always tears down
**every** held id (`removeAllAuraSounds`) before re-registering from the freshly rebuilt model —
a rebuild is the only place stale registrations get cleaned up, so it can never be allowed to
add without first removing.

**No registration changes in combat lockdown.** `AddAuraSound` is `HasRestrictions` and raises
`ADDON_ACTION_BLOCKED` in lockdown (reported 2026-10-06, a mid-fight `OnCDMSpellsChanged`
rebuild). `performRebuild` therefore stops before its tail in combat, keeps the held ids, leaves
`lastModelSignature`/`forceReapply` unconsumed, and registers a one-shot `OnLeaveCombat` →
`runRebuild`. Teardown waits too, so the old sounds keep playing until combat ends rather than
going silent. Pinned by `tests/spellalerts_check.lua` S14.

## Key resolution needs two indices

`performRebuild` walks all eight categories in `MODEL_CATEGORY_IDS` — the four classic viewer
categories plus the four item categories (5-8, "Item categories and the trinket bridge" above)
— and decodes each cooldownID's configured alerts
(`lm:GetAlerts(cooldownID, Enum.CDMLayoutMode.AccessOnly)`,
`.context/patterns-cooldownviewer.md` "Alert config: read-only layout-manager access") into two
separate maps, because the cooldown side and the aura side are keyed by two different things
that are NOT interchangeable:

- **`alertsByKey` / `entryCategory`**, keyed by `resolvedKey` (`CDMDataSource.GetResolvedEntry`)
  — the same key `IconTracker`'s pooled buttons publish through
  `CDMAlerts.OnCooldownStateChanged`. A 12.1 item-backed entry (potion, healthstone, trinket)
  has a synthetic negative key and a **nil** `resolvedSpellID` (`.context/api.md`, "spellID is
  nil for item entries") — it still needs to be reachable here, because `IconTracker` renders a
  real button and fires real cooldown-state transitions for it.
- **`alertsBySpellID` / `entryCategoryBySpellID`**, keyed by `resolvedSpellID` — the entry's
  **base** spell, which is what an aura registration has to start from. An item-backed entry
  has no `resolvedSpellID` (its key is synthetic) and no aura, so it has no place here.

Only `OnAuraApplied`/`OnAuraRemoved` alerts of type Sound are ever filed into the
`*BySpellID` maps — a cooldown alert has no use for a spellID index, and a Visual alert on an
aura event is unhonourable (see the coverage table below), so it is skipped rather than
indexed at all.

**`applyAuraRegistrations` walks `alertsBySpellID` itself** — every alert-carrying entry in
the four viewer categories, whatever CUE draws. For each entry Blizzard is not already playing
(`blizzardOwnsAlerts`), it **expands the whole identity set through `GetAuraIdentitySet`** and
calls `AddAuraSound` once per real id, skipping a (spellID, trigger) pair an earlier entry
already registered. A by-name custom aura (#55) expands to its name's ids instead
(`CustomSpells.GetAuraIdSetAny`, ahead of `GetAuraIdentitySet`, the same precedence as the
trackers' `identitySetFor`). The model signature sees neither the name nor its ids, so
`OnSpellNamesResolved` and the Tracking tab's **Match by name** toggle both call
`RebuildRegistrations`.

The expansion is the point: the engine has to watch for the id whose aura actually applies, and
that is very often NOT the base — DK Outbreak `77575` is never itself an aura, its linked
Virulent Plague `191587` is (`.context/api.md`).

It is deliberately not deduped down to one registration per entry: there is no way to know ahead
of time which id in an identity set manifests as a live aura on a given spec, and picking one
risks picking the wrong one — silently reproducing the bug this exists for. The accepted cost is
narrow: if two ids from the same entry both genuinely apply or remove together, the sound plays
once per id.

> ⚠️ **Until 2026-09-23 only spells a buff tracker SHOWED got a registration.** The loop walked
> the spell maps the two aura tracker factories registered (`RegisterAuraSpells` /
> `Unregister`), so a sound on an **Essential or Utility** entry, or on a **Tracked Bars** entry
> with CUE's bar tracker off, was registered nowhere and never played. Blizzard fires aura alerts
> from any viewer (`CooldownViewer.lua:1849-1873`), and a sound needs no icon, so the loop now
> reads the alert model. Gone with it: the provider API, both trackers'
> `registerAlertSpells`, the forced rebuild after an Additional Frame spell assignment, and the
> module's own spec-change handler, whose stated reason was the spell maps (the spec events still
> arrive as `OnCDMSpellsChanged`).

`GetTrackedCooldownIDs`'s `includeItemBacked` flag (added for this module; every other caller
keeps the default) is what lets the rebuild reach an item-backed cooldownID's alert config at
all: a synthetic-key entry has no `resolvedSpellID` (`.context/api.md` "spellID is nil for item
entries"), so without the flag `getTrackedCooldownIDs`'s spellID/key filter would drop it. That
covers a potion, healthstone or trinket wherever `performRebuild` finds it, because the walk asks
`GetTrackedCooldownIDs` about all eight ids in `MODEL_CATEGORY_IDS` ("Item categories and the
trinket bridge" above), the item's own default category (SpecAgnosticEssential/Tracked,
EquipSlotEssential/Tracked) included, not only the four classic ones — so an item the player has
dragged into a classic category (Blizzard's CDM category-transfer feature,
`CooldownViewerSettings.lua`'s `legalOriginalSourceCategoryToTargetCategory` — e.g. a trinket
moved into Essential, which rewrites the entry's *resolved* category, the CDM layout blob's
per-cooldownID override decoded by `CDMDataSource.buildResolvedCategories`, to the classic one)
and one left untouched in its default item category are reached the same way.
`resolveSpellName`'s `if key < 0 then return nil end` guard covers
exactly the reachable case — a synthetic negative key belongs to a real, player-arranged entry
here, and it correctly reads back nil from `C_Spell.GetSpellInfo` since it is not a spellID; the
practical effect is that such an entry's alert loses only its TTS phrase (no name to speak), not
its Sound/Visual alert.

The rebuild also passes `GetTrackedCooldownIDs`' third flag, `useBlizzardCategory`, so it
enumerates by **Blizzard's** effective category rather than CUE's display category
(`Core/CDMDataSource.md` "Two effective categories"). The enumeration decides which entries
reach `GetResolvedEntry` at all, so on the display table a CUE-only hide
(`cdm_category_overrides` → -1/-2) would drop the entry from the model and stop its Blizzard
alert being replayed while Blizzard's own viewer still shows it. A CUE move or hide never
changes this model. Whether an entry Blizzard itself hides is outside it depends on
`hiddenCategoryFor` (`Core/CDMDataSource.lua`): a `HideByDefault` entry with a bucket
(Essential/Utility/TrackedBuff/TrackedBar) maps to a negative category, which
`MODEL_CATEGORY_IDS` does not hold, so it's outside; a `HideByDefault` **item** entry
(trinket, potion, healthstone) stays in its own item category (5-8), which
`MODEL_CATEGORY_IDS` walks, so its alerts still replay. `tests/displaycategory_check.lua`
(E1–E5) pins it.

## Coverage table

| Event | Sound | Text-to-speech | Visual |
|---|---|---|---|
| `Available` | yes | yes | yes |
| `OnCooldown` | yes | yes | yes |
| `OnAuraApplied` | yes, Blizzard's chosen sound | Blizzard's viewer only | yes, as a persistent glow (slots or per-spell groups) |
| `OnAuraRemoved` | yes, Blizzard's chosen sound | Blizzard's viewer only | no |
| `ChargeGained` | Blizzard's viewer only | Blizzard's viewer only | not implementable |
| `PandemicTime` | Blizzard's viewer only | Blizzard's viewer only | not implementable |

"Blizzard's viewer only" means this module cannot replay it. Configuring one turns the CDM on
and hidden, so Blizzard plays it (see "Alerts only Blizzard can play").

With the CDM on, for that reason or `cdm_target_sounds`, this table does not apply to the four
viewer categories: Blizzard plays every event itself, and this module's audible half stands
down (see "Aura registrations" below).

**The player learns these limits from the `cdm_alerts` tooltip** (`CDM_ALERTS_DESC`; user
decision 2026-09-23). It names the alerts only Blizzard's Cooldown Manager can play and says
CUE turns it on for them, the one scope limit left (cooldown alerts only for drawn icons; aura
sounds lost theirs the same day), and points at Target Debuff Sounds for Blizzard's full set.

**`Available`/`OnCooldown` alerts are played by CUE's own code, reading Blizzard's config
only.** Both publishers reach `OnCooldownStateChanged`: `IconTracker`'s swipe pass by tracker
key, and `TrinketTracker`'s poll by equip slot (see "Item categories and the trinket bridge").

### Blizzard's alert code is read, never run

The rule (user, 2026-09-27): CUE reads the player's alert configuration out of Blizzard's
layout manager — `GetLayoutManager()`, `GetAlerts(id, AccessOnly)`, the
`CooldownViewerAlert_GetEvent/GetType/GetPayload` field getters, and the `CooldownViewerSoundData`
table — and calls nothing of Blizzard's that executes logic. A function called from addon code
runs tainted, so every write it makes is ours, and Blizzard's viewers read those writes next.
`CooldownViewerAlert_PlayAlert` broke that three ways:

| Half | Blizzard's path | Shared state it wrote | CUE's replacement |
|---|---|---|---|
| Visual | `VisualAlertsManager:AcquireAlert` | the pool, the alert frame, `alertIDCounter` | `playVisualAlert` (below) |
| Sound | `CooldownViewerAlert_GetPayloadContextData` → `CooldownViewerUtil.GetSoundTypeSoundKit` | builds its payload→kit lookup on first call (`CheckCreateSoundAlertData`) | `soundKitForAlert` walks `CooldownViewerSoundData` into a CUE table; `C_Sound.PlaySoundWithOptions` with `"Gameplay SFX"` |
| TTS | `TextToSpeechFrame_PlayCooldownAlertMessage` → `TextToSpeech_Speak` | `playbackActive`, `queuedMessages` | `speakAlert`: the Standard voice (`C_TTSSettings.GetVoiceOptionID`, voice 1 as fallback), `C_VoiceChat.SpeakText` with the player's rate and volume, overlap on — Blizzard's parameters |

`soundKitForAlert` is also what `resolveAuraSoundFile` uses, so the aura-sound registrations
no longer build Blizzard's mapping either. It does not cache while `CooldownViewerSoundData`
is absent.

### Cooldown Visual alerts never touch Blizzard's pool

Blizzard's visual player is `VisualAlertsManager:AcquireAlert` — the
**one** frame pool every Blizzard CDM viewer also draws from. An acquire writes the pool's
bookkeeping, the alert frame's fields, and `VisualAlert.lua`'s file-local `alertIDCounter`
(`VisualAlertMixin:GetAlertID`). Called from addon code, every one of those writes is tainted,
and the next secure viewer that plays or releases an alert reads them. Live 2026-09-27:
`BuffBarCooldownViewer`'s `UNIT_AURA` handler, tainted that way by a visual alert earlier in the
same pass, died indexing `auraInstanceIDToItemFramesMap` with a secret auraInstanceID
(`CheckAuraAddedAlertTriggers`, `CooldownViewer.lua:1864`, *"attempt to perform numeric
conversion on a secret number value (execution tainted by 'ClassUIEnhanced')"*). It became
reachable once visuals played even while Blizzard's viewer ran (`72320f5`) and the viewers stayed
shown at alpha 0 (`43f16d3`), so both sides used the pool at once.

`playVisualAlert` builds the same art as the aura path (`GlowEffect.CreateCdmAlertGlow`, one
overlay per shape per button, weak-keyed `visualOverlays`), restarts its animation, and hides it
after Blizzard's `durationSeconds` (2 s) from its own `OnUpdate`. `ReleaseButton` hides them.
Nothing in CUE calls `VisualAlertsManager` any more; keep it that way.

**`OnAuraApplied`/`OnAuraRemoved` sound is the one Blizzard's alert stores.** `AddAuraSound` is
the engine playing a sound with no callback into addon code at all, which is also why
text-to-speech on those two events is impossible — there is no moment at which to speak the
phrase. The **Visual** half of `OnAuraApplied` escapes that by never needing the moment; see
"Visual alerts on buff-tracker icons".

> **Speaking from a listener frame on the aura button does not work either (#54, 2026-09-29).**
> The engine does show that button exactly while the aura is up, so a child frame's
> `OnShow`/`OnHide` looked like the missing moment. But `SetParent` refused the listener in game
> (*"Reparenting disallowed as child object would inherit forbidden aspects:
> UntrustedScriptExecution, …"*). And a frame that carries the aspect is let in, but runs none of
> its scripts: see `.context/patterns-auracontainer.md` "No `SetScript` anywhere in a button's
> subtree". Aura text-to-speech comes only from Blizzard's own viewer, which configuring one
> turns on (see "Alerts only Blizzard can play").

`AddAuraSound` takes a sound **file** (`soundFileName`/`soundFileID`) while a CDM alert's payload
stores a sound **kit**, and nothing at runtime converts one to the other. The conversion is
therefore baked: `CDM_SOUNDKIT_FILE` maps each of the 93 kits in
`CooldownViewerSoundAlertData.lua` to its single DB2 `SoundKitEntry.FileDataID` (wago.tools,
2026-09-11), and `resolveAuraSoundFile` takes the alert's kit from `soundKitForAlert` and
passes the file as `soundFileID`. A kit
Blizzard adds later is simply absent and plays nothing until the table catches up — rebuild it
from `SoundKitEntry` filtered by the kits in that file.

Every sound is one of Blizzard's CDM sound kits, CUE's own entries included. A global
LibSharedMedia override (`cdm_alert_aura_sound`) existed briefly and was removed on 2026-09-11
in favour of the per-spell editor (the Alerts menu); stale saved values have no reader. Own
sound files per alert are #59.

> ⚠️ **This used to be opt-in on the override, and it read as broken.** With the key empty,
> `applyAuraRegistrations` returned before registering anything, so a sound configured in
> Blizzard's CDM played nothing at all — documented only in the Options tooltip. Reported
> 2026-09-11 as "there IS a sound registered". The premise behind it ("no kit→file
> conversion") was true of the runtime and false of the data.

**`ChargeGained` and `PandemicTime` are not implementable at all under the 12.1 lockdown.**
Charge counts are secret, so there is no edge to detect for the first; there is no readable
remaining-percent for an aura's duration, so there is nothing to compare against a pandemic
threshold for the second. Both events are absent from `AURA_EVENT_TRIGGERS` and from every
cooldown-side dispatch — not filtered out, simply never produced.

**Aura registrations are `unitToken = "player"` only, and have to stay that way.**
`AddAuraSound` fires for an aura from **any** source — reported by other addon authors
2026-09-11, not yet tested here — so a `"target"` registration would play for every player's
application of that spellID to your target. Blizzard's own viewer filters to the player's auras
before it plays (`CheckAuraAddedAlertTriggers`, `CooldownViewer.lua:1862`, over an aura list
only its own code can read), so an alert on **your debuff on the target** exists only there.
The `"player"` registrations carry the same flaw in a milder form — a buff another player casts
on you plays too — which is the accepted cost of having aura sounds at all with the CDM off.

**`cdm_target_sounds` is the way to get the target alerts.** It keeps Blizzard's CDM on and
hidden (`CDMDataSource.needsViewerChildren`, `Core/CDMDataSource.md` "CVar ownership");
`blizzardOwnsAlerts` then sees every viewer shown, and this module stops replaying their sounds
rather than doubling them.

## Alerts only Blizzard can play

Some alerts have no replay here at all: Sound or text-to-speech on `PandemicTime` and
`ChargeGained`, and text-to-speech on `OnAuraApplied` / `OnAuraRemoved`. `modelNeedsViewer`
finds them in the rebuilt model, and `CDMAlerts.NeedsBlizzardViewer()` reports it.
`CDMDataSource.needsViewerChildren` ORs it in beside `cdm_target_sounds`, so configuring one
in Blizzard's settings turns the CDM on and hidden. No option: the alert is the request.

- **Visual alerts don't count.** Blizzard's would draw at alpha 0 behind the suppression.
- **Item categories (5-8) don't count.** No viewer renders them, so the CDM being on would not
  play their alerts either.
- **The master switch gates it.** `cdm_alerts` off means no auto-enable.
- **It runs ahead of the signature test** in `performRebuild`. A pandemic alert added to an entry
  that already had alerts leaves the signature unchanged, but can change this answer. A change
  calls `CDMDataSource.EnsureEnabled()`.
- **It goes through the same `EnsureEnabled` path as `cdm_target_sounds`.** A player who chose
  Turn It Off gets that answer written back when the last such alert goes. The answer depends on
  the config only, never on `blizzardOwnsAlerts`, so the viewers' `OnShow` rebuild cannot flip it.
- **At login `EnsureEnabled` runs before the first rebuild** and sees `false`. The rebuild then
  turns the CDM on.

`tests/cvarkeepalive_check.lua` (K11, M1–M9) pins which alerts count.

## CUE's own entries (`spell_alerts`)

`profile.spell_alerts[key]` is a list of Blizzard-shaped records, `{ type, event, payload }`
(`CooldownViewerAlert_Create`), keyed by tracker key (a spellID), at profile level, so a spell
drawn by two trackers still alerts once. Because the shape is Blizzard's, every reader here
decodes both sources through the same `CooldownViewerAlert_Get*` getters, and one player serves
both. Written only by the Tracking tab's Alerts menu (`Core/UI/TrackingTab.md` "Alerts") through
`CDMAlerts.SetSpellAlerts`, and carried by the `spell_alerts` profile segment.

**The merge is per key, in `performRebuild`.** For every walked entry, the Cooldown Manager's
list goes into `cdmAlertsByKey` (the menu's pre-fill) and the event-bucketed `cdmByKey`, and is
filed into the replay (`fileAlert`) **only when the key has no CUE entry**. A key with an entry
files that instead (`fileCueEntry`), once, whatever number of cooldownIDs resolve to it. Then
every entry whose key the walk never met — a custom or spellbook spell with no CDM entry — is
filed with its key as its spellID. One model feeds every consumer: the cooldown lookup, the
aura-sound registrations and the aura visual.

| case | replay plays |
|---|---|
| no entry | the Cooldown Manager's list, standing down while Blizzard's viewer is shown |
| entry | the entry, never standing down |
| empty entry `{}` | nothing: the menu's Delete keeps an empty list, which is the "silence this spell" state |
| `nil` (Reset) | the Cooldown Manager's list again |

**A CUE entry is always CUE's to play.** Its keys are in `cueKeys`, which exempts them from the
cooldown-side stand-down in `OnCooldownStateChanged`, and `fileCueEntry` files their aura sounds
with no category, so `applyAuraRegistrations` never gates them on `blizzardOwnsAlerts` either.
Blizzard's viewer only ever plays the Cooldown Manager's list.

**That is also the known limit.** A CUE entry cannot silence Blizzard's own playback. While a
viewer is shown — a Blizzard-only alert anywhere, or `cdm_target_sounds` — Blizzard plays the
Cooldown Manager's alerts for the spell next to CUE's. Only removing them in Blizzard's settings
stops that. The menu says so (`CDMAlerts.BlizzardPlaysToo`).

**`NeedsBlizzardViewer` reads the Cooldown Manager's lists only** (`modelNeedsViewer(cdmByKey,
entryCategory)`), never the merged model. A Pandemic alert stays Blizzard's to play under an
override, and the merged model would throw there anyway: a CUE-only key has no category. CUE
entries never hold an event CUE cannot play, because the menu only offers `CDMAlerts.CanPlay`
combinations. The pre-fill copies only those, so the Blizzard-only ones keep playing from
Blizzard's list.

**Saved records are external data.** An imported profile can hold anything, so `fileCueEntry`
and `GetSpellAlerts` skip any record that is not three numbers (`isAlertRecord`).

**Rebuilds.** `SetSpellAlerts` and the segment's `refresh`/`layoutRefresh` call `Rebuild`. The
signature needs nothing new. A changed aura sound shows in `alertsBySpellID` (an override also
moves that spellID's category to nil). A changed visual triggers `OnCDMAlertsChanged`. The
cooldown side is rebuilt on every pass and read at fire time. Every rebuild then fires
`OnAlertModelRebuilt`, which only the Tracking tab listens to while shown: its Alerts buttons
mark what plays (`GetSpellAlertTypes`), and `cdmAlertsByKey` moves only here.

Not covered: items. `spell_alerts` is keyed by spellID, and an item entry's synthetic key is
not one, so an item's alerts stay the Cooldown Manager's.

`tests/spellalerts_check.lua` pins the merge, the empty entry, Reset, the stand-down exemption
and `CanPlay`.

## The one divergence from Blizzard's own gate

Blizzard requires `duration > MIN_GLOBAL_RECOVERY_TIME` before allowing an `Available` alert to
fire at all (`CooldownViewer.lua:1002`) — a sub-GCD "cooldown" (an instant proc reset, for
example) never triggers one. This module cannot reproduce that check: `cdInfo.duration` is a
secret value under the 12.1 lockdown (`.context/patterns-secrets.md`), unreadable from addon
code. `IconTracker.refreshButtonContent`'s `isRealCD` — already "on a real cooldown," already
excluding the GCD — is the whole gate here instead.

The consequence is narrow but real: a spell with a genuine cooldown shorter than the GCD, whose
CDM entry is not itself flagged `isOnGCD`, alerts here where Blizzard's own viewer would have
stayed silent. There is no addon-side fix available for this while `duration` stays secret.

## Visual alerts on buff-tracker icons — the engine is the trigger

A tracked buff/bar entry's alerts fire on `OnAuraApplied` (5) / `OnAuraRemoved` (6) — confirmed
per entry through `C_CooldownViewer.GetValidAlertTypes(cooldownID)`, which for buff entries
returns exactly those two and never `Available`/`OnCooldown`. And 12.1 reports neither to addon
code: `UNIT_AURA` payloads are secret, the aura button's own shown state is secret and
dispatches no script to hook (`.context/patterns-auracontainer.md`, "Mirroring is dead in every
variant"), and `AddAuraSound` works only because the **engine** plays it with no callback at
all. There is no moment at which to play anything.

**The `OnAuraApplied` Visual alert is honoured anyway, by not needing that moment.** The engine
shows the slot's aura button for exactly as long as the aura lasts, so an overlay built in that
button's subtree is switched on and off by the aura at no cost — the same mechanism
`active_glow` uses, generalised (`.context/patterns-auracontainer.md`, "an engine-shown button
IS a boolean Lua cannot read"). `CDMAlerts.GetAuraVisualAlert(spellID)` answers which
`Enum.VisualAlertType` a spell asks for; `AuraContainer.ApplyCdmAlertGlow` builds and shows it;
`AuraIconTracker.applyCdmAlertGlow` drives the pass.

Four consequences worth stating plainly:

- **It is Blizzard's animation, not a stand-in.** All ten payloads loop in Blizzard's own XML
  (`looping="REPEAT"` for the five MarchingAnts, `"BOUNCE"` for the five Flash), so running one
  for the aura's lifetime is the same thing they play. Their `durationSeconds = 2` is only the
  auto-release timer in `VisualAlertBaseMixin:OnUpdate`, which Blizzard themselves switch off
  with `SetManualRelease(true)`.
- **The art is rebuilt, not borrowed.** `VisualAlertsManager:AcquireAlert` would
  `SetParent(target)` onto a forbidden aura button, legal only inside `initializeFrame`, and
  hands back a pool-owned script-driven frame. `GlowEffect.CreateCdmAlertGlow` reproduces both
  templates from the public atlases instead — with a **flush** `SetAllPoints` rather than
  Blizzard's -8/+9 outset, because an outset anchor is the one construction observed to draw
  *nothing* inside a secret-rect subtree (see `CreateActiveBorder`).
- **`OnAuraRemoved` Visual is still impossible** and is deliberately not indexed: the button
  hosting the glow is gone at the moment that alert should fire.
- **It needs to know which spell a button holds, which rules out ONE of the three engines.**
  Slots answer it from the cell-to-spell map; **per-spell groups** answer it from the candidate
  filter, which is what lets `makeInit` stamp `cue_spellID` without a forbidden read
  (`.context/patterns-auracontainer.md`, "One group PER SPELL"). Only the plain groups engine —
  one group holding every tracked spell — cannot, and a button there resolves nil and stays
  dark. So this is **not** slots-only the way `syncProcGlow` is: that one needs an unrestricted
  *cell* for LibCustomGlow, while this glow lives in the button's own subtree like
  `active_glow` and is engine-agnostic once the spell is known.

There is no CUE setting for this beyond the alert itself, configured in Blizzard's Cooldown
Manager or in a CUE entry. It is gated only by `cdm_alerts` — never by `blizzardOwnsAlerts`,
since the glow is on CUE's own icon (see "The gate") — and that is the same reason the
cooldown-side alerts have no per-component toggle either.

> ⚠️ **The model lands AFTER the trackers have looked at it, so the rebuild must announce
> itself.** `OnCDMSpellsChanged` refreshes every aura tracker synchronously, while the same
> signal only *schedules* `performRebuild` (`REBUILD_DEBOUNCE`, 0.25 s). The glow pass therefore
> always read the previous `auraVisualBySpellID` — at login an empty one — and nothing re-ran it
> outside aura secrecy until combat ended (`OnEnterCombat` is already secret; a target change
> never calls `Refresh`). Reported as "the glow works on another class": pure timing.
> `performRebuild` now triggers `OnCDMAlertsChanged` whenever there are, or were, visuals, and
> `AuraIconTracker` refreshes on it.

## Options

Both keys are global/profile-level, not per-component, so there is no per-component EditMode
widget to mirror — `Core/UI/EditMode.lua` is deliberately unchanged.

| key | widget | effect |
|---|---|---|
| `cdm_alerts` | toggle, default `true` | Master switch. `CDMAlerts.IsEnabled()` and every fire-time check read it; off means this module produces nothing, cooldown or aura side, regardless of what is configured in Blizzard's settings, and no longer turns the CDM on for an alert only Blizzard can play. |
| `cdm_target_sounds` | toggle, default `false` | Keeps Blizzard's CDM on and hidden so it plays its own alerts — the only source of an alert on your debuff on the target (see "Aura registrations"). Read by `CDMDataSource.needsViewerChildren`, not by this module. |

The `cdm_alerts` setter calls `RebuildRegistrations()`, since the switch is invisible to the
rebuild's change detection. The `cdm_target_sounds` setter calls `CDMDataSource.EnsureEnabled()`
and nothing here: the viewers' own `OnShow`/`OnHide` hooks rebuild once Blizzard has shown or
hidden them, and `blizzardOwnsAlerts` is in the signature.

## Rebuild signals

**Without the Cooldown Manager (MoP Classic) the module never runs.** `Initialize` returns
before registering anything, and `runRebuild`, the one funnel every rebuild goes through, returns
too: `private.compat.HasCooldownManager()` is false there. Every alert record, CUE's own
`spell_alerts` entries included, is read through Blizzard's `CooldownViewerAlert_*` helpers, which
do not exist on that client. So the model stays empty, `IsEnabled()` is false, and nothing plays.
The Tracking tab drops its Alerts column on the same check.

`CDMAlerts.Rebuild()` is registered against every signal that can move either half of the
model: `OnCDMSpellsChanged`, `OnProfileChanged`, and every per-viewer `OnShow`/`OnHide`. A CUE
entry edit (`SetSpellAlerts`) and a `spell_alerts` import call it directly. The settings
window's `OnHide` flushes a rebuild parked while it was open. A spec change arrives as
`OnCDMSpellsChanged`: `CDMDataSource` registers `ACTIVE_PLAYER_SPECIALIZATION_CHANGED` (not
`PLAYER_SPECIALIZATION_CHANGED`, which fires for any group member's respec) along with the other
game events Blizzard's `CooldownViewerSettings.OnDataChanged` relays, and this module no longer
listens to that relay (2026-09-22) or keeps a spec handler of its own (2026-09-23). An Additional
Frame's spell assignment no longer triggers a rebuild either: since registrations stopped following
the trackers' spell maps (2026-09-23), assigning a spell changes nothing this module reads.

### Rebuilds are debounced, and the trigger list is worse than it looks

`OnCDMSpellsChanged` follows `CDMDataSource`'s direct registration of `SPELLS_CHANGED`,
`PLAYER_PVP_TALENT_UPDATE`, `COOLDOWN_VIEWER_TABLE_HOTFIXED`, `PLAYER_EQUIPMENT_CHANGED` and the
spec events — and `SPELLS_CHANGED` storms through a zone change. Until 2026-09-22 this module also
listened to Blizzard's `CooldownViewerSettings.OnDataChanged`, which relays the same events, so
every event in that storm cost **two** rebuilds, a frame apart. Each rebuild walks every category,
entry and alert and tears down and re-adds every `AddAuraSound` id.

The old `C_Timer.After(0, ...)` collapsed only signals landing in the *same* frame, which these
never do. `Rebuild` now uses a **trailing-edge debounce** (`REBUILD_DEBOUNCE`, 0.25s): each
signal cancels and reschedules, so an arbitrarily long burst becomes one rebuild once it stops.

`REBUILD_MAX_DELAY` (2s) bounds it. A trailing debounce on its own starves for as long as
signals keep arriving inside the window, and the failure is silent — alerts would simply stop
tracking config with nothing to show for it. Past the ceiling, the next signal rebuilds
immediately instead of rescheduling.

`Initialize` deliberately does **not** go through `Rebuild` for the first pass: anything
reading the model before it lands sees an empty one, so the initial build keeps the old
next-frame timing. The login burst behind it debounces normally.

### The debounce collapses bursts; only change detection collapses a drip

`PLAYER_EQUIPMENT_CHANGED` arrives one signal at a time, arbitrarily far apart, so a debounce has
nothing to merge: **every gear swap gets its own full rebuild**, and since the alert model is
user-configured it almost always rebuilds to exactly what it was. Reported from play as debug spam
on equipping an item.

**Dropping the trigger is not the fix, and it is worth knowing why.** The tempting move is to stop
`CDMDataSource` answering `PLAYER_EQUIPMENT_CHANGED`. But the event is not spurious: a trinket
**is** a CDM entry (`equipSlot` 13/14, `.context/api.md`), so an equip change can genuinely move the
tracked set. Every trigger upstream is a proxy; none of them knows whether anything changed.

So `performRebuild` decides for itself. It does the walk — cheap — and compares the result against
the last one it acted on (`modelSignature` / `lastModelSignature`). Identical, and it returns
before `reapplyAuraRegistrations`, which is what stops a gear swap tearing
down and re-adding every `AddAuraSound` id.

**The signature deliberately omits the alert objects.** `applyAuraRegistrations` tests the
*presence* of an event bucket (`if byEvent[alertEvent] then`) and never looks inside one, so an
alert's sound or type cannot change what it produces. What the signature does cover is exactly what
that function reads out of the model: the cooldown-side key set with each key's category and
Blizzard-owned state, and the aura-side `spellID -> events` index. Sorted, because `pairs` order is
not stable and an unstable signature would never match itself.

### `RebuildRegistrations` is for the inputs the signature cannot see

The signature is built from the CDM-derived model, so it is blind to the module's one *other*
input: the profile master switch. It can move while the model is byte-identical, and a plain
`Rebuild` would then correctly conclude "nothing changed" and skip precisely the work that was
needed.

`CDMAlerts.RebuildRegistrations()` sets a one-shot force flag and rebuilds. Its callers are the
`OnProfileChanged` callback and the `cdm_alerts` Options setter. Until 2026-09-23 the list also
held the aura trackers' `RegisterAuraSpells` / `Unregister`, `AdditionalFrameManager`'s
assigned-spells apply and a forced spec-change handler — all there because the trackers' spell
maps were an input; they no longer are (see "Key resolution needs two indices").

> It is a second function rather than a `Rebuild(force)` argument on purpose. `Rebuild` is
> registered directly as an event and callback handler in four places, where it is handed a frame,
> an event name or an owner as its first argument — a truthy-first-arg force would be on for every
> one of them, which is the behaviour this exists to stop.

### While the settings frame is open, nothing rebuilds at all

On top of the debounce, `runRebuild` parks the pass entirely while Blizzard's settings frame is
shown, and `CooldownViewerSettings.OnHide` — Blizzard's own event, so nothing hooks or writes
to a CooldownViewer frame — flushes it.

That is not only a cost saving. `performRebuild` reads its whole model from
`CooldownViewerSettings:GetLayoutManager()`, and while the frame is open that layout manager
holds **uncommitted** edits: Blizzard does not save until `CooldownViewerSettingsMixin:OnHide`
calls `CheckSaveCurrentLayout`. Rebuilding mid-edit was reacting to a layout the player had not
chosen yet, so parking until close matches Blizzard's own commit point rather than diverging
from it.

Two details keep it from latching:

- The frame test lives in `runRebuild`, i.e. after the debounce, not in `Rebuild`. Whether
  `IsShown()` has already gone false by the time Blizzard fires OnHide is therefore irrelevant
  — the flush's own rebuild lands a debounce later either way.
- `settingsFrameOpen()` reads the frame rather than tracking a flag of our own, so there is no
  state to leave stuck on. A missed `OnHide` costs one delayed rebuild — the next signal from
  any source rebuilds normally — not every future one.

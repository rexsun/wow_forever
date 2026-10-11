# Init.lua

Wires addon together. Creates DF addon object, minimap icon, AceDB callbacks (→ `ProfileManager.OnProfileChanged()`).

On `PLAYER_LOGIN`: sets `private.charDB = self.db.char` (AceDB's character scope, holding `cdm_never_ask` and `cdm_no_suppress` — see [CDMDataSource.md](CDMDataSource.md) *Turning the CDM off*; kept out of the profile so they survive profile switches and never travel in an export, where they would carry one player's addon environment onto another's), then calls `CDMDataSource.EnsureEnabled()` — the addon reads no viewer child any more, so `needsViewerChildren()` is `false` unless the `cdm_target_sounds` option asks for Blizzard's own alerts (then the CVar is written up and the viewers hidden); instead it **asks** rather than writing `"0"`, turning the CDM off only if the player says yes this session, and only once (an addon that re-enables it afterwards is conceded the CVar and answered with viewer suppression). Before components initialize; then initializes components.

**No longer captures Blizzard's CDM screen position as CooldownTracker's starting anchor.** That one-shot read the viewer's rect on first-ever profile load to preserve the player's Edit Mode placement. It was the last `Util.GetViewerFrame` caller outside the data path, and the rework obsoleted it from both ends: the capture required `IsDataAvailable()`, which §G turns off by default for every class but Evoker and Demon Hunter, so for most players it deferred forever; and the placement it was preserving is one the player can no longer make, since the addon now owns the CVar and keeps all four viewers suppressed at alpha 0. CooldownTracker uses its profile default (`TOP` of `UIParent`, `yoff = -140`). Profiles that already captured keep the anchor they were given — the write happened once and persisted; only the never-fired case changes. The `_blizzard_position_captured` flag survives in existing SavedVariables and is now read by nothing.

On `LOADING_SCREEN_DISABLED`: calls `CDMDataSource.Initialize()` — installs the viewer-suppression hooks and settles the four viewers against `suppressing` (`needsViewerChildren() or hidden` — the second half is what keeps a "turn it off" answer honoured when another addon re-enables the CDM; see [CDMDataSource.md](CDMDataSource.md) *Viewer suppression*), then registers the game events that change the CDM data (the ones Blizzard's own data provider listens to) behind the coalesced `OnCDMSpellsChanged` callback — then runs profile migrations (`MigrateCDMVisibility`, `MigrateHideWhenInactive`, …), `CustomSpells.Initialize()`, and the three-pass layout refresh.

Registers a `CVAR_UPDATE` listener that reconciles the CVar in both directions when something external (Blizzard's settings panel, console, another addon) changes it: `EnsureEnabled` re-derives the wanted value from the profile and guard-writes it, then viewer suppression is re-settled. The corrective `SetCVar` re-fires `CVAR_UPDATE`, which then no-ops on the guard. `EnsureEnabled` never writes in combat — a correction needed mid-pull is deferred to a one-shot `OnLeaveCombat` that re-evaluates the predicate at that point rather than replaying a stale decision, since flipping the CVar makes Blizzard show/hide the protected viewers and re-drives the whole tracker layout.

Does NOT write to viewer frame tables or fight the managed frame system — addon-owned containers handle positioning independently.

**The simulated-EditMode pass does not catch.** The first layout pass sets `private.isEditMode` /
`private.isInitializing` true to force full initialization of every component, including disabled
ones, then restores both. A throw inside the block skips the restore and pins `isEditMode` true for
the session: every later cast-bar `Refresh` then takes its EditMode branch and re-shows the static
dummy cast, so an unrelated component's error surfaces as permanently stuck target and focus cast
bars. That consequence is accepted rather than wrapped — the addon does not `pcall` its own code,
and a login-path throw is a defect to fix at the source.


**Registers CUE's tracker containers with Plater_UnitFrames.** On `PLAYER_LOGIN`, if
`PlaterUnitFrames.AddAnchors` exists, the four main tracker containers — `CUE_BT_Container`,
`CUE_BTB_Container`, `CUE_CT_Container`, `CUE_UT_Container` (Buff, Buff Bars, Cooldown, Utilities) —
are offered as anchor parents PUF's unit frames may ride on, labelled `"CUE <component name>"`. This
is the mirror of `ClassUIEnhancedAPI.AddAnchors`, which PUF calls on us for its own frames.

PUF's contract differs from CUE's external anchors in one respect: it inherits the registered
frame's **alpha** onto the frame riding it (position only otherwise — no reparenting, so strata,
scale and size do not cross, and hiding ours does not hide theirs). It resolves the global name on
every placement pass, so a container that does not exist yet is picked up when it is created, a
second registration just replaces the label, and there is no unregister on either side — a stored
anchor whose addon is gone simply stops resolving. Only the four main trackers are registered;
adding another is one line.

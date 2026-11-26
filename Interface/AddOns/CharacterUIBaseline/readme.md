# CharacterUIBaseline

Version 0.4.2, Interface 16001. Synchronizes the configured source character's supported UI baseline on every other character's login or UI reload, moves characters off Blizzard's preset Edit Mode layouts to the account layout `rex`, and keeps setup, guide and what's-new windows from opening by themselves at login. A session gate prevents repeated application on zone transitions. Upstream addon files are unchanged.

The layout switch and the login quieting need no source configuration, so they also run on installations without `Source.local.lua`, such as GitHub-synced ones.

## Configure the source

Edit `Interface/Settings/character-ui-source.local.json`. It is private and ignored by Git; `Settings/character-ui-source.example.json` documents its format.

- `sourceAccount`: source account folder under `WTF/Account`.
- `sourceRealm`: source realm folder, such as `70`.
- `sourceCharacter`: full source character folder, including surname when present.
- `sourceRealmName`: exact in-game realm name, used to identify the source at runtime.
- `fallbackLayoutName`: layout name recorded for the source until it first publishes its own. It is informational; the layout switch always targets `rex`.
- `enabled`: set to `false` to disable synchronization.

Close this installation of WoW after changing configuration, then run:

```powershell
uv run --no-project python Interface/tools/character_ui_baseline.py
```

Run from the game root, or omit `Interface/` when running from Interface. `--dry-run` validates without writing. The helper validates source paths, reads only approved UI fields and refreshes `Baseline.lua` plus private `Source.local.lua`, with backup/rollback. It never writes live WTF. Do not edit generated files directly. Source account/character identities stay out of the tracked baseline.

## Synchronization

The source character is excluded from target application. At source logout, the addon publishes current display CVars, the Edit Mode layout name last seen while in the world (the layout API reported the Modern preset during logout), chat font and normalized primary-window geometry, and EUI party/raid positions to account-level `CharacterUIBaselineAccountDB`. `/uib capture` publishes immediately on the source. Same-account characters use that publication on their next login; no client restart is required for character switching.

The existing post-exit settings watcher also refreshes the generated baseline from the configured source's persisted WTF and publication. This distributes source changes across accounts on the next full client start. WoW addons cannot read another account's files or another running client's unsaved settings. Log the source out to publish changes; after a full exit, let the watcher finish before reopening. A source change in the private JSON requires the helper and a new client load.

Targets apply the latest matching source publication, or the generated fallback, once on every login/reload, regardless of old per-character revision markers. The login sync never selects or imports an Edit Mode layout; `EditModeLayout.lua` handles the layout separately (below). CVars are written only when they differ from the source value. Combat and unavailable APIs defer application. Retries are bounded at thirty attempts; the last one prints why sync stopped. `/uib apply` retries manually (only the first word counts, so `/uib apply now` also applies); `/uib` reports whether this login is synchronized and, while it is not, the last reason (for example the screen size not being available yet, or an error). Later target changes survive only until the next login sync.

## Edit Mode layout `rex`

`EditModeLayout.lua` checks each character after world entry and after a spec-group change. When the active layout is one of Blizzard's presets (Modern/Classic) and an Edit Mode layout named `rex` is saved on the account, it selects `rex` and reloads the UI at once. Selecting a layout from addon code runs Blizzard's `EDIT_MODE_LAYOUTS_UPDATED` handler tainted, which in 0.2.0 broke Edit Mode and blocked logout because the session continued; the immediate reload discards that tainted state, the same pattern EllesmereUI's preset import uses. A new character therefore sees one extra loading screen on its first login, and once more for its second spec group.

- Each spec group is switched at most once and recorded in `CharacterUIBaselineDB.editModeLayout`. If the selection did not persist after the reload, it prints `Select it once in Edit Mode` instead of reloading again.
- A character that already used `rex`, or that uses another saved layout, is left alone, so a later deliberate choice survives.
- Combat, Edit Mode being open, unsaved Edit Mode changes and Edit Mode not yet initialized defer the check (bounded retries, restarted when combat ends).
- If the account has no `rex` layout (another account, or a reset), it says so once per login and changes nothing. The layout itself is never imported or edited.
- The target name is the `TARGET_LAYOUT` constant in `EditModeLayout.lua`.

## Login windows

`QuietLogin.lua` keeps windows from opening by themselves at any character's login: first-run setup on a new character or account, and notices after an add-on update. It runs when the addon loads (after the listed add-ons) and again at `PLAYER_LOGIN`:

| Source | Window | Handling |
| --- | --- | --- |
| YUI | Setup wizard (`Installer:CheckInstall`, every new character) | Replaced; the login task chain continues. The wizard stays available from YUI's game-menu button. |
| YUI | "Switch to the YUI Edit Mode layout" prompt | Replaced with a no-op; `rex` is selected by `EditModeLayout.lua`. |
| YUI | Changelog notice after an update | The new version is recorded as seen; the Changelog settings page still lists it. |
| EllesmereUI | First-install module picker and style picker (fresh account), incompatible-add-on popup | `firstInstallPopupShown` set, pending pickers cleared, `_EUI_ConflictCheckRan` set. Overlaps are covered by OverlapSettingsGuard. |
| GearInsight | Leveling window (per character below level 60) | Hidden and recorded per character while YUI loads, the condition of guard rule `gi.levelingstats`, so the guard no longer announces it. `/gif lv` reopens it. |
| GearInsight | What's New after an update | The version is recorded as seen. GearInsight 1.4 publishes it only after its own load, so the `PLAYER_LOGIN` pass catches it before its 4-second timer. |
| Details | Welcome wizard on an account's first Details run | The first call is skipped; the rest of the first-run setup still runs. |
| GatherLite | Controls guide on an account's first run | `controlsGuideSeen` is set. |
| MapUtils | What's New after an update | `MAUTTAB.WHATSNEW.enabled = false` ("Show what's new" off). |
| MapUtils | Map preset dialog (1.7.35+, an account without MapUtils settings) | `MAUTTAB.PRESETSHOWN = true`, creating `MAUTTAB` when MapUtils loads without saved settings; set again at `PLAYER_LOGIN` after MapUtils marks first use. `/maputils preset` and the settings button still open it. |
| Bagnon | Outdated-version popup | `Bagnon_Sets.latest.cooldown` is held at the maximum time. |
| Blizzard | Help tips (`closedInfoFrames`, per character) and account tips (`closedInfoFramesAccountWide`) | Every `LE_FRAME_TUTORIAL_*` bit is marked closed; `showTutorials` is set to `0` when the client has it at `1`. |

The Details profile picker, Auctionator, WaypointUI, Lueur, You Don't Need This and Skinner open nothing at login with this pack. GearInsight 1.4's departure checklist (rested in a city or inn), dungeon guide (inside a dungeon), Paladin aura bar and Hunter ammo alerts can appear right after login; OverlapSettingsGuard writes their switches off before login (`gi.xpprep`, `gi.dungeonnav`, `gi.auraremind`, `gi.ammoremind`), so they are not repeated here. Left unchanged: Bagnon's "invalid build" popup (only on an unsupported client build), GatherLite's login chat line, You Don't Need This's login chat lines and BugGrabber's chat reminder (chat text, not windows).

## Exact scope and exclusions

The supported baseline includes the source's Edit Mode layout name (published only), up to fifteen whitelisted display CVars, native chat font and primary-window position/size, and the active target EUI profile's `partyUnlockPos`/`unlockPos`. EUI/YUI shared account profiles continue to own the remaining addon appearance; this is not a copy of arbitrary per-character SavedVariables or an entire account database.

Specialization selection, talent choices/plans, spec-to-profile mappings, `contentBySpec`/`specDocuments`, macros, bindings, subscriptions, quest/currency/profession tracking and combat history are not copied. The initializer does not change EUI's active profile or its spec assignment table. Owner startup CVars still run normally.

`CharacterUIBaselineDB` is per-character telemetry, not a saved permission to skip future logins. `CharacterUIBaselineAccountDB` contains only the source publication. Both remain outside anonymous settings capture. Adoption copies the addon, private source configuration/metadata and full live WTF; source folder identifiers may need adjusting on another installation.

## Ownership and verification

This addon updates settings on the existing UI owners at login rather than creating a competing display. OverlapSettingsGuard retains its 23 continuous enforcement rules and its normal startup preferences. Login-sync overlaps and timing are documented in its policy readme.

```powershell
uv run --no-project --with lupa python tools/character-ui-baseline-tests.py
uv run --no-project python -m unittest discover -s tools -p test_character_ui_baseline.py
```

Runtime checks cover repeated logins, session idempotence, source exclusion/publication, changed sources, spec/talent preservation, a login sync without Edit Mode writes, unchanged-CVar skipping, combat deferral and all three supported resolutions; the `rex` switch (one reload per spec group, kept choices, missing layout, failed persistence, deferral, saved-variable timing); and each login-window suppression. Helper checks cover configurable sources, changed persisted settings, path validation, dry runs, disabling and atomic rollback. Live first-login timing, the reload after the layout switch and the suppressed windows still require in-game verification on a new character.

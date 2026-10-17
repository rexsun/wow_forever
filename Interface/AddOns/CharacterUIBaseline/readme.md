# CharacterUIBaseline

Version 0.3.0, Interface 16001. Synchronizes the configured source character's supported UI baseline on every other character's login or UI reload. A session gate prevents repeated application on zone transitions. Upstream addon files are unchanged.

## Configure the source

Edit `Interface/Settings/character-ui-source.local.json`. It is private and ignored by Git; `Settings/character-ui-source.example.json` documents its format.

- `sourceAccount`: source account folder under `WTF/Account`.
- `sourceRealm`: source realm folder, such as `70`.
- `sourceCharacter`: full source character folder, including surname when present.
- `sourceRealmName`: exact in-game realm name, used to identify the source at runtime.
- `fallbackLayoutName`: layout name to compare against until the source first publishes its active layout.
- `enabled`: set to `false` to disable synchronization.

Close this installation of WoW after changing configuration, then run:

```powershell
uv run --no-project python Interface/tools/character_ui_baseline.py
```

Run from the game root, or omit `Interface/` when running from Interface. `--dry-run` validates without writing. The helper validates source paths, reads only approved UI fields and refreshes `Baseline.lua` plus private `Source.local.lua`, with backup/rollback. It never writes live WTF. Do not edit generated files directly. Source account/character identities stay out of the tracked baseline.

## Synchronization

The source character is excluded from target application. At source logout, the addon publishes current display CVars, the Edit Mode layout name last seen while in the world (the layout API reported the Modern preset during logout), chat font and normalized primary-window geometry, and EUI party/raid positions to account-level `CharacterUIBaselineAccountDB`. `/uib capture` publishes immediately on the source. Same-account characters use that publication on their next login; no client restart is required for character switching.

The existing post-exit settings watcher also refreshes the generated baseline from the configured source's persisted WTF and publication. This distributes source changes across accounts on the next full client start. WoW addons cannot read another account's files or another running client's unsaved settings. Log the source out to publish changes; after a full exit, let the watcher finish before reopening. A source change in the private JSON requires the helper and a new client load.

Targets apply the latest matching source publication, or the generated fallback, once on every login/reload, regardless of old per-character revision markers. The Edit Mode layout is never selected or imported: doing so from addon code runs Blizzard's layout handler in tainted execution, which broke Edit Mode and blocked logout in 0.2.0. When the target's active layout name differs from the source's, the login message names both; select the layout in Edit Mode once per character (the choice persists). CVars are written only when they differ from the source value. Combat and unavailable APIs defer application. Retries are bounded at thirty attempts. `/uib apply` retries manually; `/uib` reports status. Later target changes survive only until the next login sync.

## Exact scope and exclusions

The supported baseline includes a read-only Edit Mode layout-name comparison, up to fifteen whitelisted display CVars, native chat font and primary-window position/size, and the active target EUI profile's `partyUnlockPos`/`unlockPos`. EUI/YUI shared account profiles continue to own the remaining addon appearance; this is not a copy of arbitrary per-character SavedVariables or an entire account database.

Specialization selection, talent choices/plans, spec-to-profile mappings, `contentBySpec`/`specDocuments`, macros, bindings, subscriptions, quest/currency/profession tracking and combat history are not copied. The initializer does not change EUI's active profile or its spec assignment table. Owner startup CVars still run normally.

`CharacterUIBaselineDB` is per-character telemetry, not a saved permission to skip future logins. `CharacterUIBaselineAccountDB` contains only the source publication. Both remain outside anonymous settings capture. Adoption copies the addon, private source configuration/metadata and full live WTF; source folder identifiers may need adjusting on another installation.

## Ownership and verification

This addon updates settings on the existing UI owners at login rather than creating a competing display. OverlapSettingsGuard retains its 23 continuous enforcement rules and its normal startup preferences. Login-sync overlaps and timing are documented in its policy readme.

```powershell
uv run --no-project --with lupa python tools/character-ui-baseline-tests.py
uv run --no-project python -m unittest discover -s tools -p test_character_ui_baseline.py
```

Runtime checks cover repeated logins, session idempotence, source exclusion/publication, changed sources, spec/talent preservation, layout mismatch reporting without Edit Mode writes, unchanged-CVar skipping, combat deferral and all three supported resolutions. Helper checks cover configurable sources, changed persisted settings, path validation, dry runs, disabling and atomic rollback. Live first-login timing and visuals still require in-game verification.

# WoW: Forever Interface

## Addon policies

- All addons have to be compatible with the current installed game version.
- Inspect the installed addons, report if there are feature overlaps.
- When an addon is installed or updated, add each overlapping setting to `AddOns/OverlapSettingsGuard/Policy.lua` and the policy table in `AddOns/OverlapSettingsGuard/readme.md`, then run its tests.
- When an addon is installed or updated, check that no window, dialog, wizard or what's-new panel opens by itself at any character's login, and suppress any that do in `AddOns/CharacterUIBaseline/QuietLogin.lua`. Chat messages are not covered.
- When an addon is removed from the pack, remove its obsolete overlap policies, adapters, TOC dependencies, tests and current documentation; preserve historical change-log entries.
- Maintain the source, version, and brief introduction of each installed addon in `AddOns/readme.md`.
- Keep each change log in `AddOns/updates-YYYY-QN.md`, where `QN` is the calendar quarter of the entry date; newest entries first. Start a new file each quarter and link it at the top of `CHANGELOG.md`, which lists one line per version linking to its log entry.
- Do NOT create any feature branches if the prompts do not explicitly ask to.

## Settings policies

- Addons' overlapping settings will be managed by the addon `OverlapSettingsGuard`.
- All settings need to be compatible with 3 resolutions:
  - Full HD / 1080P: 1920 × 1080
  - Quad HD / 2K / 1440P: 2560 × 1440
  - Ultra HD / 4K: 3840 × 2160
- Maintain the script `adopt_addons.ps1` to copy all files over.

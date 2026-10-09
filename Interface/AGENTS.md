# WoW: Forever Interface

## Addon policies

- All addons have to be compatible with the current installed game version
- Inspect the installed addons, report if there are feature overlaps
- When an addon is installed or updated, add each overlapping setting to `AddOns/OverlapSettingsGuard/Policy.lua` and the policy table in `AddOns/OverlapSettingsGuard/readme.md`, then run its tests
- Maintain the source, version, and brief introductions of each installed addons in `AddOns/readme.md`
- Maintain every single change logs in `AddOns/updates.md`, newest changes are first

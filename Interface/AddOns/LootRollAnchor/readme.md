# LootRollAnchor

Version 0.1.0, for Interface 16001. This local addon keeps Blizzard's group loot roll windows (`GroupLootContainer` and `GroupLootFrame1`-`4`) centred on screen, just above YUI's visible action bars and HUD groups. `/lra` prints whether it is placing the stack, the stack's current anchor and the spot it would use now.

## Why

On this client, Blizzard sets the roll stack's height from the first visible, default-position frame in `OverrideActionBar`, `MultiBarBottomLeft` and `MicroMenuContainer` (`Blizzard_EditMode/Camelot/EditModeUtil.lua`). YUI hides the micro menu and keeps the native bars as invisible copies, so that height is taken from frames that are not where the visible bars are. It also changes whenever Blizzard re-runs its bottom layout. The result is a roll window at an unrelated spot that can sit behind or among YUI's bars and HUD. YUI has a bridge that lifts the stack above its own frames (`YHUD/View/Bridges/Loot.lua`), but it loads only on retail.

## How

- The addon registers a placer for `GroupLootContainer` through EllesmereUI's `SetFramePlacer`, under the `cdm` owner. EllesmereUI applies it each time Blizzard's layout re-anchors the stack, before the frame draws. The roll windows themselves are anchored by Blizzard to the container and are not touched.
- Spot: horizontally centred on UIParent. Vertically it starts 120 UI units above the bottom of the screen, then steps above every shown YUI action-bar holder and YHUD group that overlaps the 286-unit roll column, keeping an 8-unit gap. The spot is computed each time the stack is laid out, so it follows the number of open rolls, YUI layout changes and UI scale. It never goes above the top of the screen.
- If a frame value is secret, the placer waits and EllesmereUI retries after combat. Without EllesmereUI's placer, Blizzard's position is kept and one chat line says so.
- `LootRollAnchorDB` keeps only a placement count and the last computed spot, for diagnosis.

## Limits

- EllesmereUICooldownManager, which is not installed, also uses the `cdm` owner. Installing it would replace this placer.
- YUI frames that are hidden when a roll opens and appear later (for example a HUD group shown only in combat) are not avoided until the next layout.
- Checked offline only. The placement, and how the fix interacts with the roll timer, are unverified in-game at 1080p, 1440p and 4K.

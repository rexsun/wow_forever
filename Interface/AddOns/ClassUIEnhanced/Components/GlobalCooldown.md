# GlobalCooldown

GCD timer bar with latency overlay. Uses the GCD reference spell `private.GCD_SPELL_ID` (`Core/Start.lua`: 61304, or 1283885 on WoW Forever, where 61304 does not exist) via `C_Spell.GetSpellCooldown`. Latency measured empirically (CURRENT_SPELL_CAST_CHANGED → UNIT_SPELLCAST_SENT timing), fallback to `GetNetStats()`. DetailsFramework TimeBar with red latency region on right edge proportional to latency/gcd ratio. Below PlayerCastBar. **Disabled by default.** Defaults: 200×8.

**Spell icon:** When `show_icon` is on, the cast spell's texture is drawn left-outside the bar, square-sized to bar height and zoom-cropped via `private.Util.GetIconZoomCoords` — matching the `CastBar.lua` convention. The texture is written directly to `gcdBar.statusBar.icon`; DF's `SetIcon` is bypassed so it does not overwrite the addon's anchor and texcoord. Sizing/anchoring is reapplied in `Refresh` (via `applyIconLayout`) so EditMode height changes propagate.

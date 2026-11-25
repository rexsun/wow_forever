# MapUtils by D4KiR

## [v1.7.37](https://github.com/d4kir92/MapUtils/tree/v1.7.37) (2026-11-25)
[Full Changelog](https://github.com/d4kir92/MapUtils/compare/v1.7.36...v1.7.37) [Previous Releases](https://github.com/d4kir92/MapUtils/releases)

- v1.7.37  
- Show tracked waypoint circle and raise frame level for library book pins  
    - Match library book entries and their source points in waypoint tracking so the yellow tracked circle appears behind the pin and the pin sits above the Blizzard waypoint marker  
- Defer SetPropagateMouseClicks on zone info frame during combat  
    - Skip calling protected SetPropagateMouseClicks while in combat lockdown and apply it once out of combat  
- Make library book map pins circular  
    - Mask library book pin icons and hover highlights into circles  
    - Replace the square four-edge book border with a circular colored ring  
- Make One Map smooth zoom taint-free on WoW Forever  
    - Drive smooth zoom and panning on WoW Forever purely via C++ canvas scale and scroll APIs without writing Blizzard ScrollContainer fields  
    - Intercept One Map mouse wheel, drag, and canvas clicks with an own frame parented to the scroll child below map pins  
    - Rescale Blizzard map pins and the player/group unit position pin via C++ APIs while zoomed  
    - Re-apply the smooth zoom viewport in the same frame after Blizzard MarkCanvasDirty resets to prevent zone-switch jumps  
    - Switch between continent and zone views using zone area thresholds (enter 3.2, leave 4.5) in One Map smooth zoom  
    - Read live canvas scale, scroll position, and cursor coordinates consistently across MapUtils modules  
    - Show live zoom factor, canvas scale, and continent/zone area ratios in the /maputils debug overlay  
- Switch world map zones through Blizzard's secure path on WoW Forever  
    - Zone changes made by MapUtils on the Forever world map no longer taint the map, reducing blocked-action errors when opening the map in combat  
- Stop CombatPins tainting the world map on WoW Forever  
    - Opening the world map in combat on Forever no longer taints map pins and the quest log through CombatPins  
- Fix Razorfen Kraul boss pins and Blackfathom Deeps level pin  
- data  
- data  
- d4  

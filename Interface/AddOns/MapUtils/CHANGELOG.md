# MapUtils by D4KiR

## [v1.7.39](https://github.com/d4kir92/MapUtils/tree/v1.7.39) (2026-11-26)
[Full Changelog](https://github.com/d4kir92/MapUtils/compare/v1.7.38...v1.7.39) [Previous Releases](https://github.com/d4kir92/MapUtils/releases)

- v1.7.39  
- Add viewport-weighted zone hysteresis to One Map  
    - One Map now picks the zone covering most of the visible land area instead of only the center pixel  
    - Keep the current zone active until another zone leads by at least 25% of the visible land area so pins from other map addons do not jump on small drags across borders  
- Restore world map addon compatibility and defer pin passthrough in combat on WoW Forever  
    - Use standard One Map smooth zoom on WoW Forever so third-party map addons (Spoken Places, Azeroth Fieldbook, RareScanner) and Blizzard quest areas work properly  
    - Re-enable combat pin passthrough deferral outside gamepad mode to prevent SetPassThroughButtons blocked-action errors when opening the world map in combat  
- Prevent terrain tile flicker on zone switches  
    - Keep terrain map alpha stable during One Map zone switches  
    - Preload a 1-tile ring around the viewport and hold off releasing terrain tiles during zone switches  
- Rescale third-party map pins during smooth zoom  
    - Third-party addon pins outside Blizzard's pin pools (such as RareScanner) now scale properly when zooming in with One Map on Forever  

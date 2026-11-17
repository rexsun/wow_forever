# MapUtils by D4KiR

## [v1.7.9](https://github.com/d4kir92/MapUtils/tree/v1.7.9) (2026-11-17)
[Full Changelog](https://github.com/d4kir92/MapUtils/compare/v1.7.8...v1.7.9) [Previous Releases](https://github.com/d4kir92/MapUtils/releases)

- v1.7.9  
- Reduce pin outline and map culling overhead  
    - Skip per-pin outline checks while the map is still  
    - Reuse the viewport margin and continent assignments when culling map layers  
- Optimize world map pin updates and center clusters  
    - Reduce idle pin updates and hide pins outside the viewport  
    - Reuse pin frames while zooming  
    - Center grouped pins across all member positions  
- Refine the Classic UI fullscreen icon and map layout  
    - Restore the four-corner fullscreen icon and center it at a smaller size  
    - Keep the ClassicUIForever map layout regardless of the Simple Frame setting  
- Fix Classic UI map controls and group nearby pins  
    - Preserve the Simple Frame button layout with ClassicUIForever enabled  
    - Match the fullscreen button to the Classic UI style  
    - Keep the quest log toggle above dungeon maps  
    - Group nearby world map pins by type with shared tooltips  

# MapUtils by D4KiR

## [v1.7.35](https://github.com/d4kir92/MapUtils/tree/v1.7.35) (2026-11-24)
[Full Changelog](https://github.com/d4kir92/MapUtils/compare/v1.7.34...v1.7.35) [Previous Releases](https://github.com/d4kir92/MapUtils/releases)

- v1.7.35  
- Make instance map floor switcher collapsible  
    - Add a collapse/expand toggle button and header click-to-toggle to the floating floor switcher panel  
    - Shrink the collapsed panel to a compact header bar with active-floor hover tooltip and persist its collapsed state  
- Show linked quest status on quest item tooltips  
    - Add quest item tooltip lines showing active progress, ready-to-turn-in, quest-starter, completed, or not-in-quest-log status  
    - Show active quests on normal items required by a quest currently in the quest log  
    - Add a Quests setting toggle to enable or disable quest item tooltips across all 11 locales  
- Use Compendium-style floating floor switcher on World Map instance maps  
    - Replaced the World Map instance map floor dropdown/navbar button via D4InstanceMap with the draggable floating "Floors" panel  
    - Added localized "Floors" (LID\_MAPLEVELS) across all 11 locale files and persisted the floor panel position  
- Color standalone native quest turn-in pins and update shared instance map pins  
    - Colored standalone Blizzard quest turn-in "?" pins on zone, continent, and world maps to match raid, dungeon, and PvP quest colors  
    - Updated Blackfathom Deeps instance pins (Lorgus Jett spawns, Baron Aquanis, and Amongst the Ruins) via shared InstancePins  
    - Guarded D4InstanceMap return SetMapID against InCombatLockdown and added killed-boss X support in D4InstancePins  

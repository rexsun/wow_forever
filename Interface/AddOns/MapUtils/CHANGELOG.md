# MapUtils by D4KiR

## [v1.7.10](https://github.com/d4kir92/MapUtils/tree/v1.7.10) (2026-11-18)
[Full Changelog](https://github.com/d4kir92/MapUtils/compare/v1.7.9...v1.7.10) [Previous Releases](https://github.com/d4kir92/MapUtils/releases)

- v1.7.10  
- Limit some map icons to zone maps and polish world map window  
    - Zone crossings, spirit healers, meeting stones and ley lines only have a zone map toggle  
    - These icons no longer appear on world and continent maps  
    - Toggle bar, tooltip and map menu show only the zone toggle for them  
    - Quest log toggle no longer shows its corner shadow  
    - World map window minimum width raised to 500  
- Separate world map grip from quest log toggle  
    - Size grip sits further in the bottom-right corner  
    - Quest log toggle moves up while the quest log is collapsed so it no longer overlaps the grip  
- Add world map window resizing  
    - Drag the world map grip to change width and height  
    - Shift-drag the grip to scale the map  
    - Right-click the grip to reset the size, Shift-right-click to reset the scale  
    - Grip tooltip shows size, scale and controls  
    - Quest details panel follows the map height  
    - MapUtils now handles the world map even when MoveAny is loaded  
- Rework world map zoom and panning  
    - Larger, faster mouse wheel zoom steps on the stepless world map  
    - Zoom limits are the same on every map: zoom out until the whole world fits, zoom depth follows what is under the cursor  
    - Zooming out no longer switches maps mid-step, the map switches once the view settles  
    - Dragging the map no longer stops a running zoom  
    - Fully zoomed out, the world is centred; panning room grows smoothly while zooming in, wide windows and fullscreen allow more side panning  
- d4  

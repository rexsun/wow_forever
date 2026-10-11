local _, YUI = ...
YUI.API = YUI.API or {}
local Map = YUI.API.Map or {}
YUI.API.Map = Map

-- Map-art metadata, not unit positions. Nil means unavailable; no cached result tables.
function Map.GetArtID(mapID)
    if C_Map and C_Map.GetMapArtID then return C_Map.GetMapArtID(mapID) end
end

function Map.GetArtLayers(mapID)
    if C_Map and C_Map.GetMapArtLayers then return C_Map.GetMapArtLayers(mapID) end
end

function Map.GetExploredTextures(mapID)
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
        return C_MapExplorationInfo.GetExploredMapTextures(mapID)
    end
end

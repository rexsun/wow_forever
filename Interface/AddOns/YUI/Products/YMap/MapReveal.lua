local YUI = _G.YUI
if not (YUI and (YUI.IsRetail or YUI.IsForever) and YUI.YMap) then return end
local YMap = YUI.YMap
local MapAPI = YUI.API and YUI.API.Map
local Security = YUI.API and YUI.API.Security
local Event = YUI.Event
local Reveal = {}
YMap.MapReveal = Reveal

local TEMPLATE = "MapExplorationPinTemplate"
local owner = {}
local pins = setmetatable({}, { __mode = "k" })
local maps = setmetatable({}, { __mode = "k" })
local enabled = false
local tint = true
local red, green, blue, alpha = 0.65, 0.75, 1, 0.65
local refreshes, activeTextures = 0, 0
local AttachMap
local cachedArt, cachedSource, cachedOverlays
local decodes = 0

local function ClearDataCache()
    cachedArt, cachedSource, cachedOverlays = nil, nil, nil
end

-- Retail keeps static records packed; only the current art is expanded.
-- Table snapshots (including Forever) retain their original representation.
function Reveal:GetOverlays(art)
    local data = YMap.RevealData
    local source = data and data.maps[art]
    if type(source) ~= "string" then
        ClearDataCache()
        return source
    end
    if cachedArt == art and cachedSource == source then return cachedOverlays end
    ClearDataCache()
    local overlays = {}
    for record in source:gmatch("[^;]+") do
        local overlay, files, index = {}, {}, 0
        for token in record:gmatch("%-?%d+") do
            index = index + 1
            if index <= 6 then overlay[index] = tonumber(token)
            else files[index - 6] = tonumber(token) end
        end
        overlay[7] = files
        overlays[#overlays + 1] = overlay
    end
    cachedArt, cachedSource, cachedOverlays = art, source, overlays
    decodes = decodes + 1
    return overlays
end

-- Reset before native textures can be acquired again. Never replace the shared pool resetter.
local function ClearPin(pin, release)
    local state = pins[pin]
    if not state then return end
    for index = #state.textures, 1, -1 do
        local texture = state.textures[index]
        texture:SetVertexColor(1, 1, 1, 1)
        if release then pin.overlayTexturePool:Release(texture) end
        state.textures[index] = nil
        activeTextures = activeTextures - 1
    end
end

local function OnRemoveAllData(pin)
    -- Native ReleaseAll already hid/released the textures; only clear our tint and references.
    ClearPin(pin, false)
end

local function IsExplored(overlay, explored)
    if not explored then return false end
    for index = 1, #explored do
        local entry = explored[index]
        if entry.textureWidth == overlay[1] and entry.textureHeight == overlay[2]
            and entry.offsetX == overlay[3] and entry.offsetY == overlay[4] then
            return true
        end
    end
    return false
end

local function FileSize(pixels, tileSize)
    if pixels == tileSize then return tileSize end
    local size = 16
    while size < pixels do size = size * 2 end
    return size
end

local function OnRefreshOverlays(pin, fullUpdate)
    if not enabled then return end
    local map = pin:GetMap()
    if map ~= _G.WorldMapFrame or not map:IsShown() then return end
    local state = pins[pin]
    if not state or not pin.overlayTexturePool then return end
    local mapID = map:GetMapID()
    if not mapID then return end
    local art = MapAPI.GetArtID(mapID)
    local layerIndex = map:GetCanvasContainer():GetCurrentLayerIndex()
    -- The shipped DB2 snapshot contains only layer zero (canvas layer one).
    if layerIndex ~= 1 then return end
    local layers = MapAPI.GetArtLayers(mapID)
    local layer = layers and layers[layerIndex]
    if not layer or not layer.tileWidth or not layer.tileHeight
        or layer.tileWidth <= 0 or layer.tileHeight <= 0 then return end
    local overlays = Reveal:GetOverlays(art)
    if not overlays then return end
    local explored = MapAPI.GetExploredTextures(mapID)
    local drawLayer, subLevel = pin.dataProvider:GetDrawLayer()
    subLevel = math.max(-8, (subLevel or 0) - 1)
    refreshes = refreshes + 1
    local tw, th = layer.tileWidth, layer.tileHeight
    for index = 1, #overlays do
        local overlay = overlays[index]
        if not IsExplored(overlay, explored) then
            local width, height, x, y = overlay[1], overlay[2], overlay[3], overlay[4]
            local columns, rows, files = overlay[5], overlay[6], overlay[7]
            -- A changed art layout fails closed rather than drawing shifted tiles.
            if columns <= math.ceil(width / tw) and rows <= math.ceil(height / th) then
                for row = 0, rows - 1 do
                    local h = math.min(th, height - row * th)
                    for column = 0, columns - 1 do
                        local file = files[row * columns + column + 1]
                        if file and file > 0 then
                            local w = math.min(tw, width - column * tw)
                            local texture = pin.overlayTexturePool:Acquire()
                            state.textures[#state.textures + 1] = texture
                            activeTextures = activeTextures + 1
                            map:AddMaskableTexture(texture)
                            texture:SetSize(w, h)
                            texture:SetTexCoord(0, w / FileSize(w, tw), 0, h / FileSize(h, th))
                            texture:SetPoint("TOPLEFT", x + column * tw, -(y + row * th))
                            texture:SetTexture(file, nil, nil, "TRILINEAR")
                            texture:SetVertexColor(tint and red or 1, tint and green or 1,
                                tint and blue or 1, tint and alpha or 1)
                            texture:SetDrawLayer(drawLayer, subLevel)
                            texture:Show()
                            if fullUpdate or pin.isWaitingForLoad then
                                pin.textureLoadGroup:AddTexture(texture)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function AttachPins(map)
    if not enabled or not map.EnumeratePinsByTemplate then return end
    for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
        if not pins[pin] and pin.RemoveAllData and pin.RefreshOverlays then
            pins[pin] = { textures = {} }
            local reset = Security.SafeHook("YMap.Reveal.reset", pin, "RemoveAllData", OnRemoveAllData)
            if reset then
                pins[pin].ready = Security.SafeHook("YMap.Reveal.refresh", pin, "RefreshOverlays", OnRefreshOverlays)
            end
        end
    end
end

local function RefreshPins(map)
    if not (map and map:IsShown()) then return end
    for pin, state in pairs(pins) do
        if state.ready and pin:GetMap() == map then pin:RefreshOverlays(true) end
    end
end

local function OnAcquirePin(map, template)
    if enabled and template == TEMPLATE then AttachPins(map) end
end

local function OnMapShow(map)
    if enabled then AttachPins(map) end
end

local function OnMapHide(map)
    ClearDataCache()
    for pin in pairs(pins) do
        if pin:GetMap() == map then ClearPin(pin, true) end
    end
end

AttachMap = function(map)
    if not map then return end
    if not maps[map] then
        maps[map] = true
        Security.SafeHook("YMap.Reveal.acquire", map, "AcquirePin", OnAcquirePin)
        map:HookScript("OnShow", OnMapShow)
        map:HookScript("OnHide", OnMapHide)
    end
    AttachPins(map)
    RefreshPins(map)
end

local function OnAddonLoaded(_, addon)
    if enabled and addon == "Blizzard_WorldMap" then
        Event:OffOwner(owner)
        AttachMap(_G.WorldMapFrame)
    end
end

function Reveal:Disable()
    enabled = false
    ClearDataCache()
    if Event and Event.OffOwner then Event:OffOwner(owner) end
    for pin in pairs(pins) do ClearPin(pin, true) end
end

function Reveal:Enable()
    local db = YMap:GetDB()
    local config = db.worldMap.reveal
    if not (config and config.enabled and db.worldMap.enabled and MapAPI and Security
        and Security.SafeHook and YMap.RevealData) then
        self:Disable()
        return false
    end
    local color = config.color
    local changed = not enabled or tint ~= config.tint or red ~= color[1]
        or green ~= color[2] or blue ~= color[3] or alpha ~= color[4]
    enabled, tint = true, config.tint
    red, green, blue, alpha = color[1], color[2], color[3], color[4]
    if _G.WorldMapFrame then
        if Event and Event.OffOwner then Event:OffOwner(owner) end
        if changed or not maps[_G.WorldMapFrame] then AttachMap(_G.WorldMapFrame) end
    elseif Event and Event.On then
        Event:OffOwner(owner)
        Event:On("ADDON_LOADED", OnAddonLoaded, owner, {
            moduleId = "ymap", traceName = "YMap:reveal-load",
        })
    end
    return true
end

function Reveal:GetStats(target)
    target = target or {}
    target.mapRevealEnabled = enabled
    target.mapRevealActiveTextures = activeTextures
    target.mapRevealRefreshes = refreshes
    target.mapRevealCachedArt = cachedArt
    target.mapRevealDataDecodes = decodes
    return target
end

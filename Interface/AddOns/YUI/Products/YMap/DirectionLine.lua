local YUI = _G.YUI
local YMap = YUI and YUI.YMap
if not YMap then return end

local Direction = { enabled = false, active = false, reads = 0, writes = 0, usedDots = 0 }
YMap.DirectionLine = Direction
local GUI2 = YUI.GUI2
local MAX_DOTS = 512
local function MediaPath(file)
    return YUI.Assets:Component("ymap", file)
end
local sin, cos, sqrt, min, max, abs = math.sin, math.cos, math.sqrt, math.min, math.max, math.abs

local function PublicNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

-- A normalized map is generally not square in world space. Project the facing
-- vector through both world dimensions before intersecting the map boundary.
function Direction:ProjectRay(x, y, facing, worldWidth, worldHeight)
    x, y, facing = PublicNumber(x), PublicNumber(y), PublicNumber(facing)
    worldWidth, worldHeight = PublicNumber(worldWidth), PublicNumber(worldHeight)
    if not x or not y or not facing or not worldWidth or not worldHeight
        or worldWidth <= 0 or worldHeight <= 0 or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local dx, dy = -sin(facing) / worldWidth, -cos(facing) / worldHeight
    local distance = math.huge
    if abs(dx) > 1e-12 then distance = min(distance, (dx > 0 and 1 - x or -x) / dx) end
    if abs(dy) > 1e-12 then distance = min(distance, (dy > 0 and 1 - y or -y) / dy) end
    if distance == math.huge or distance <= 0 then return nil end
    return max(0, min(1, x + dx * distance)), max(0, min(1, y + dy * distance))
end

local function HideVisuals()
    if Direction.overlay then Direction.overlay:Hide() end
    Direction.visible = false
    Direction.lastX, Direction.lastY, Direction.lastFacing = nil, nil, nil
end

function Direction:Stop()
    self.active = false
    YMap.CoordinateDriver:SetDirectionActive(false)
    HideVisuals()
end

function Direction:EnsureVisuals(canvas, dashed)
    if not self.overlay then
        self.overlay = GUI2:CreateFrame(canvas, { kind = "YMapDirectionLine", mouse = false })
        self.overlay:SetAllPoints(canvas)
        -- Native Line is the rendering adapter for arbitrary-angle solid lines.
        self.line = self.overlay:CreateLine(nil, "ARTWORK")
        self.line:SetTexture(MediaPath("direction-line.tga"))
        if self.line.SetSnapToPixelGrid then self.line:SetSnapToPixelGrid(false) end
        if self.line.SetTexelSnappingBias then self.line:SetTexelSnappingBias(0) end
        self.dots = {}
    end
    if self.canvas ~= canvas then
        self.overlay:SetParent(canvas)
        self.overlay:SetAllPoints(canvas)
        self.canvas = canvas
    end
    if dashed and #self.dots == 0 then
        for index = 1, MAX_DOTS do
            local dot = GUI2:CreateTexture(self.overlay, { texture = MediaPath("direction-dot.tga"), layer = "ARTWORK",
                pixelPolicy = { snapToPixelGrid = false, texelSnappingBias = 0 } })
            dot:Hide()
            self.dots[index] = dot
        end
    end
end

local function SyncFrameLevel(frame)
    local overlay = Direction.overlay
    if not overlay or not overlay.GetFrameLevel or not overlay.SetFrameLevel
        or not frame.GetPinFrameLevelsManager then return end
    local manager = frame:GetPinFrameLevelsManager()
    if not manager or not manager.GetValidFrameLevel then return end
    local explorationLevel = PublicNumber(manager:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION"))
    if not explorationLevel then return end
    -- Exploration textures live on high-level native pins, above the canvas.
    -- Use their current level so the ray clears map artwork but stays below icons.
    local level = explorationLevel + 1
    if overlay:GetFrameLevel() ~= level then overlay:SetFrameLevel(level) end
end

function Direction.Update()
    local self = Direction
    local frame, canvas, config = self.frame, self.canvas, self.config
    if not self.enabled or not frame or not frame:IsShown() then self:Stop(); return end
    if not config or not C_Map or not C_Map.GetPlayerMapPosition or not C_Map.GetMapWorldSize
        or not GetPlayerFacing or (UnitOnTaxi and UnitOnTaxi("player")) then HideVisuals(); return end
    local mapID = frame:GetMapID()
    if not mapID then HideVisuals(); return end
    self.reads = self.reads + 1
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    local facing = PublicNumber(GetPlayerFacing())
    if not position or (issecretvalue and issecretvalue(position)) or not facing then HideVisuals(); return end
    local x, y
    if position.GetXY then x, y = position:GetXY() else x, y = position.x, position.y end
    x, y = PublicNumber(x), PublicNumber(y)
    if not x or not y then HideVisuals(); return end
    local width, height = canvas:GetSize()
    local scale = canvas.GetEffectiveScale and canvas:GetEffectiveScale() or 1
    width, height, scale = PublicNumber(width), PublicNumber(height), PublicNumber(scale)
    if not width or not height or not scale or width <= 0 or height <= 0 or scale <= 0 then HideVisuals(); return end
    SyncFrameLevel(frame)
    if self.visible and x == self.lastX and y == self.lastY and facing == self.lastFacing
        and mapID == self.lastMapID and width == self.lastWidth and height == self.lastHeight
        and scale == self.lastScale then return end
    if mapID ~= self.worldMapID then
        self.worldWidth, self.worldHeight = C_Map.GetMapWorldSize(mapID)
        self.worldMapID = mapID
    end
    local endX, endY = self:ProjectRay(x, y, facing, self.worldWidth, self.worldHeight)
    if not endX then HideVisuals(); return end
    local sx, sy, ex, ey = x * width, -y * height, endX * width, -endY * height
    if config.style == "dashed" then
        self.line:Hide()
        local dx, dy = ex - sx, ey - sy
        local distance = sqrt(dx * dx + dy * dy)
        local spacing = max(config.dotSpacing / scale, distance / MAX_DOTS)
        local used = min(MAX_DOTS, math.floor(distance / spacing))
        for index = 1, used do
            local dot, offset = self.dots[index], index * spacing / distance
            if self.lastScale ~= scale then dot:SetSize(config.dotSize / scale, config.dotSize / scale) end
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", self.overlay, "TOPLEFT", sx + dx * offset, sy + dy * offset)
            dot:Show()
        end
        for index = used + 1, self.usedDots do self.dots[index]:Hide() end
        self.usedDots = used
    else
        for index = 1, self.usedDots do self.dots[index]:Hide() end
        self.usedDots = 0
        self.line:SetThickness(config.thickness / scale)
        self.line:SetStartPoint("TOPLEFT", self.overlay, sx, sy)
        self.line:SetEndPoint("TOPLEFT", self.overlay, ex, ey)
        self.line:Show()
    end
    self.lastX, self.lastY, self.lastFacing, self.lastMapID = x, y, facing, mapID
    self.lastWidth, self.lastHeight, self.lastScale = width, height, scale
    self.visible = true
    self.writes = self.writes + 1
    self.overlay:Show()
end

function Direction:Refresh()
    local db = YMap:GetDB()
    local config = db.worldMap and db.worldMap.directionLine
    local frame = _G.WorldMapFrame
    if not self.enabled or not config or not config.enabled or not db.worldMap.enabled
        or not frame or not frame.GetCanvas or not frame:IsShown() then self:Stop(); return end
    local canvas = frame:GetCanvas()
    if not canvas or not GUI2 then self:Stop(); return end
    self.frame, self.config = frame, config
    self:EnsureVisuals(canvas, config.style == "dashed")
    local color = config.color
    self.line:SetVertexColor(color[1], color[2], color[3], color[4])
    local scale = PublicNumber(canvas.GetEffectiveScale and canvas:GetEffectiveScale() or 1)
    if not scale or scale <= 0 then self:Stop(); return end
    for _, dot in ipairs(self.dots) do
        dot:SetSize(config.dotSize / scale, config.dotSize / scale)
        dot:SetVertexColor(color[1], color[2], color[3], color[4])
    end
    self.lastX = nil
    self.active = true
    YMap.CoordinateDriver:RegisterDirectionConsumer(self.Update)
    YMap.CoordinateDriver:SetDirectionActive(true)
    self.Update()
end

local function OnShow() if Direction.enabled then Direction:Refresh() end end
local function OnHide() Direction:Stop() end
local function AttachMap()
    local frame = _G.WorldMapFrame
    if not frame then return end
    if Direction.addonHandle then YUI.Event:Off(Direction.addonHandle); Direction.addonHandle = nil end
    if Direction.hookedFrame ~= frame then
        frame:HookScript("OnShow", OnShow)
        frame:HookScript("OnHide", OnHide)
        if hooksecurefunc and frame.OnCanvasScaleChanged then
            hooksecurefunc(frame, "OnCanvasScaleChanged", OnShow)
        end
        Direction.hookedFrame = frame
    end
    Direction:Refresh()
end

function Direction:Enable()
    if not self.enabled then
        self.enabled = true
        if YUI.Event and not _G.WorldMapFrame then self.addonHandle = YUI.Event:On("ADDON_LOADED", function(_, name)
            if name == "Blizzard_WorldMap" then AttachMap() end
        end, self) end
    end
    AttachMap()
end

function Direction:Disable()
    self.enabled = false
    self:Stop()
    if self.addonHandle then YUI.Event:Off(self.addonHandle); self.addonHandle = nil end
end

function Direction:GetStats(target)
    target.directionLineActive, target.directionLineVisible = self.active, self.visible == true
    target.directionLineReads, target.directionLineWrites = self.reads, self.writes
    target.directionLineDotPool = self.dots and #self.dots or 0
    return target
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or not YHUD.Client or YHUD.Client.id ~= "retail" then return end

local Security = YUI.API and YUI.API.Security
if not Security then return end

local Loot = { active = false, stats = {} }
YHUD.NativeLootLayout = Loot
local watched = setmetatable({}, { __mode = "k" })
local excluded = {}
local obstacles = {}
local obstacleCount = 0
local Watch
local categories = { "essential", "utility", "trackedBuff" }
local Unpack = unpack or table.unpack
local EPSILON = 0.01
-- The container is narrower than the artwork of its roll windows.
local ROLL_ART_WIDTH = 286
local WRITE_CHECKS = { "IsForbidden", "IsProtected", "IsAnchoringRestricted" }
local GEOMETRY_METHODS = { "SetPoint", "SetAllPoints", "SetSize", "SetHeight", "SetScale" }
local VISIBILITY_METHODS = { "Show", "Hide", "SetShown" }
local ACTION_FRAMES = {
    "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
    "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar", "StanceBar",
    "ExtraAbilityContainer",
}

local function Count(key)
    Loot.stats[key] = (Loot.stats[key] or 0) + 1
end

local function Public(value)
    return not Security.IsSecretValue(value)
end

local function Number(value)
    if not Public(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function Read(frame, method, ...)
    if not frame or type(frame[method]) ~= "function" then return false end
    return pcall(frame[method], frame, ...)
end

local function True(frame, method)
    local ok, value = Read(frame, method)
    return ok and Public(value) and value == true
end

local function CanWrite(frame)
    for _, method in ipairs(WRITE_CHECKS) do
        if method ~= "IsAnchoringRestricted" or frame[method] then
            local ok, value = Read(frame, method)
            if not ok or not Public(value) or value ~= false then return false end
        end
    end
    return true
end

local function Near(a, b)
    return a and b and math.abs(a - b) < EPSILON
end

local function OwnPoint(point, relative, relativePoint, x, y)
    return Loot.owned and point == "TOP" and relative == Loot.column
        and relativePoint == "TOP" and Near(x, 0) and Near(y, Loot.offset)
end

local function Write(point, relative, relativePoint, x, y)
    Loot.writing = true
    local cleared = Security.SafeMethod("YHUD.Loot.Clear", Loot.frame, "ClearAllPoints")
    local placed = cleared and Security.SafeMethod(
        "YHUD.Loot.Anchor", Loot.frame, "SetPoint", point, relative, relativePoint, x, y
    )
    Loot.writing = false
    if not placed then Count("lootWriteFailures") end
    return placed == true
end

function Loot:Cancel()
    if self.timer then self.timer:Cancel(); self.timer = nil end
end

function Loot:OnCombatEnded()
    self.retry = nil
    self:Request(true)
end

local function Retry()
    if not Loot.retry and YUI.Event and YUI.Event.Once then
        Loot.retry = YUI.Event:Once("PLAYER_REGEN_ENABLED", "OnCombatEnded", Loot)
        Count("lootDeferred")
    end
end

-- Keep a later mover's anchors even when it added a point without clearing ours.
-- Read every point before writing; restricted inputs leave the frame untouched.
local function ReadAnchors()
    local frame = Loot.frame
    local ok, count = Read(frame, "GetNumPoints")
    count = ok and Number(count)
    if not count then return nil end
    local anchors = {}
    local foundOwn = false
    for i = 1, count do
        local got, point, relative, relativePoint, x, y = Read(frame, "GetPoint", i)
        if not got or not Public(point) or not Public(relative) or not Public(relativePoint)
            or not Number(x) or not Number(y) then return nil end
        if relative == nil then
            local parentOK, parent = Read(frame, "GetParent")
            if not parentOK then return nil end
            relative = parent
        end
        if not Public(relative) then return nil end
        if OwnPoint(point, relative, relativePoint, x, y) then
            foundOwn = true
        else
            anchors[#anchors + 1] = { point, relative, relativePoint, x, y }
        end
    end
    return anchors, foundOwn
end

local function Release()
    if not Loot.owned then return true end
    local ok, parent = Read(Loot.frame, "GetParent")
    if not ok or not Public(parent) then Retry(); return false end
    if parent ~= Loot.column then Loot.owned, Loot.offset = false, nil; return true end
    if not CanWrite(Loot.frame) then Retry(); return false end
    local anchors, foundOwn = ReadAnchors()
    if not anchors then Retry(); return false end
    if foundOwn then
        if #anchors == 0 then
            if not Write("TOP", Loot.column, "TOP", 0, 0) then return false end
        else
            Loot.writing = true
            local ok = Security.SafeMethod("YHUD.Loot.Release", Loot.frame, "ClearAllPoints")
            if ok then
                for i = 1, #anchors do
                    ok = Security.SafeMethod(
                        "YHUD.Loot.Release", Loot.frame, "SetPoint", Unpack(anchors[i])
                    ) and ok
                end
            end
            Loot.writing = false
            if not ok then Count("lootWriteFailures"); return false end
        end
        Count("lootRestores")
    end
    Loot.owned, Loot.offset = false, nil
    return true
end

local function AddObstacle(frame)
    if not frame or excluded[frame] or frame == Loot.frame then return true end
    local ok, shown = Read(frame, "IsShown")
    if not ok or not Public(shown) then return false end
    if not shown then return true end
    local got, left, bottom, width, height = Read(frame, "GetRect")
    local scaled, scale = Read(frame, "GetEffectiveScale")
    left, bottom, width, height = Number(left), Number(bottom), Number(width), Number(height)
    scale = scaled and Number(scale)
    if not got or not left or not bottom or not width or not height or not scale then return false end
    if width <= 0 or height <= 0 or scale <= 0 then return true end
    obstacleCount = obstacleCount + 1
    local rect = obstacles[obstacleCount] or {}
    obstacles[obstacleCount] = rect
    rect.left, rect.right = left * scale, (left + width) * scale
    rect.bottom, rect.top = bottom * scale, (bottom + height) * scale
    return true
end

local function AddColumnChildren(ok, ...)
    if not ok then return false end
    for i = 1, select("#", ...) do
        local frame = select(i, ...)
        if not Public(frame) then return false end
        if frame and not excluded[frame] and frame ~= Loot.frame then
            if not Public(frame.layoutIndex) or not Public(frame.ignoreInLayout) then return false end
            if frame.layoutIndex and not frame.ignoreInLayout then
                if not AddObstacle(frame) then return false end
            end
        end
    end
    return true
end

local function EarlierBottom(a, b)
    return a.bottom < b.bottom
end

local function VisitContent(callback)
    local view = YHUD.View
    for _, runtime in pairs(view and view.groups or {}) do
        if runtime.frame and callback(runtime.frame) == false then return false end
    end
    local bars = YUI.YActionBar and YUI.YActionBar.BarManager
    for _, record in pairs(bars and bars.bars or {}) do
        if record.holder and callback(record.holder) == false then return false end
    end
    for i = 1, #ACTION_FRAMES do
        local frame = _G[ACTION_FRAMES[i]]
        if frame and callback(frame) == false then return false end
    end
    return true
end

local function CalculateOffset()
    local frame, column = Loot.frame, Loot.column
    local _, scale = Read(frame, "GetEffectiveScale")
    local _, columnScale = Read(column, "GetEffectiveScale")
    local _, uiScale = Read(UIParent, "GetEffectiveScale")
    local _, left, bottom, width, height = Read(column, "GetRect")
    local _, rollWidth = Read(frame, "GetWidth")
    local _, rollHeight = Read(frame, "GetHeight")
    local _, uiBottom = Read(UIParent, "GetBottom")
    local _, uiTop = Read(UIParent, "GetTop")
    scale, columnScale, uiScale = Number(scale), Number(columnScale), Number(uiScale)
    left, bottom, width, height = Number(left), Number(bottom), Number(width), Number(height)
    rollWidth, rollHeight = Number(rollWidth), Number(rollHeight)
    uiBottom, uiTop = Number(uiBottom), Number(uiTop)
    if not scale or not columnScale or not uiScale or not left or not bottom
        or not width or not height or not rollWidth or not rollHeight or not uiBottom or not uiTop
        or scale <= 0 or columnScale <= 0 or uiScale <= 0 or rollHeight <= 0 then return nil end

    obstacleCount = 0
    if not AddColumnChildren(Read(column, "GetChildren")) then return nil end
    if not VisitContent(AddObstacle) then return nil end
    -- Sorting vertical intervals finds the lowest free slot without repeatedly
    -- moving native frames or trusting their enlarged container height.
    for i = #obstacles, obstacleCount + 1, -1 do obstacles[i] = nil end
    table.sort(obstacles, EarlierBottom)
    local center = (left + width * 0.5) * columnScale
    local halfWidth = math.max(rollWidth, ROLL_ART_WIDTH) * scale * 0.5
    local rollPixels = rollHeight * scale
    if not Public(column.spacing) then return nil end
    local gap = Number(column.spacing)
    if column.spacing ~= nil and not gap then return nil end
    gap = math.max(0, gap or 0) * columnScale
    local floor = math.max(bottom * columnScale, uiBottom * uiScale)
    for i = 1, obstacleCount do
        local rect = obstacles[i]
        if center - halfWidth < rect.right and center + halfWidth > rect.left
            and floor < rect.top + gap and floor + rollPixels + gap > rect.bottom then
            floor = rect.top + gap
        end
    end
    local top = math.min(floor + rollPixels, uiTop * uiScale)
    return (top - (bottom + height) * columnScale) / scale
end

function Loot:Repair()
    Count("lootChecks")
    if not self.frame then return end
    local parentOK, parent = Read(self.frame, "GetParent")
    if not parentOK or not Public(parent) then Retry(); return end
    if parent ~= self.column then self.owned, self.offset = false, nil; return end
    if not self.active then Release(); return end
    if not True(self.frame, "IsShown") then return end
    local manager = _G.EditModeManagerFrame
    if manager then
        local shownOK, shown = Read(manager, "IsShown")
        if not shownOK or not Public(shown) then Retry(); return end
        if shown then Release(); return end
    end
    if not CanWrite(self.frame) then Retry(); return end
    local anchors, foundOwn = ReadAnchors()
    if not anchors then Retry(); return end
    if foundOwn and #anchors > 0 then
        Release()
        Count("lootYields")
        return
    end
    if not foundOwn then
        self.owned, self.offset = false, nil
        local anchor = anchors[1]
        if #anchors ~= 1 or anchor[1] ~= "TOP" or anchor[2] ~= self.column
            or anchor[3] ~= "TOP" or not Near(anchor[4], 0) or not Near(anchor[5], 0) then
            Count("lootYields")
            return
        end
    end
    VisitContent(Watch)
    local offset = CalculateOffset()
    if not offset then Retry(); return end
    if foundOwn and Near(offset, self.offset) or not foundOwn and Near(offset, 0) then return end
    if Write("TOP", self.column, "TOP", 0, offset) then
        self.owned, self.offset = not Near(offset, 0), offset
        Count("lootPlacements")
    end
end

local function Run()
    Loot.timer = nil
    Loot:Repair()
end

function Loot:Request(restoring)
    if self.timer or not self.frame or not (self.active or restoring and self.owned) then return end
    if not restoring and not True(self.frame, "IsShown") then return end
    if C_Timer and C_Timer.NewTimer then self.timer = C_Timer.NewTimer(0, Run) end
end

local function Changed()
    if not Loot.writing then Loot:Request() end
end

local function ColumnLayoutComplete()
    if Loot.active and not Loot.writing and True(Loot.frame, "IsShown") then
        -- Finish after the native layout, so a layout running from OnUpdate
        -- cannot overwrite a timer's correction immediately before drawing.
        Loot:Cancel()
        Loot:Repair()
    end
end

Watch = function(frame, isLoot)
    if not frame or watched[frame] then return end
    watched[frame] = true
    for i = 1, #GEOMETRY_METHODS do
        local method = GEOMETRY_METHODS[i]
        if frame[method] then Security.SafeHook("YHUD.Loot.Geometry", frame, method, Changed) end
    end
    for i = 1, #VISIBILITY_METHODS do
        local method = VISIBILITY_METHODS[i]
        if frame[method] then Security.SafeHook("YHUD.Loot.Visibility", frame, method, Changed) end
    end
    if isLoot then
        Security.SafeHook("YHUD.Loot.Clear", frame, "ClearAllPoints", Changed)
        Security.SafeHook("YHUD.Loot.Parent", frame, "SetParent", Changed)
    elseif frame.Layout then
        Security.SafeHook("YHUD.Loot.Column", frame, "Layout", ColumnLayoutComplete)
    end
end

function Loot:OnGeometryChanged()
    self:Request()
end

function Loot:Disable()
    self.active = false
    self:Cancel()
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(self) end
    self.listening, self.retry = false, nil
    Release()
end

function Loot:Sync(bridge)
    local active = false
    for viewer in pairs(excluded) do excluded[viewer] = nil end
    if bridge.active and not bridge.editModeActive then
        for i = 1, #categories do
            local state = bridge.states[categories[i]]
            if state and state.attached and state.viewer then
                excluded[state.viewer] = true
                active = true
            end
        end
    end
    if not active then self:Disable(); return end
    local frame, column = _G.GroupLootContainer, _G.BottomManagedFrameContainer
    if not frame or not column then self:Disable(); return end
    if self.frame ~= frame or self.column ~= column then
        self:Disable()
        self.frame, self.column = frame, column
    end
    self.active = true
    Watch(frame, true)
    Watch(column)
    if not self.listening and YUI.Event and YUI.Event.On then
        YUI.Event:On("UI_SCALE_CHANGED", "OnGeometryChanged", self)
        YUI.Event:On("DISPLAY_SIZE_CHANGED", "OnGeometryChanged", self)
        self.listening = true
    end
    self:Request()
end

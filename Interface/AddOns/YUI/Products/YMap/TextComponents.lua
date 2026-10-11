local YUI = _G.YUI
local YMap = YUI and YUI.YMap
if not YMap then return end

-- Shared only by the four minimap text components; no runtime driver is owned here.
local Text = {}
YMap.TextComponents = Text
local GUI2 = YUI.GUI2
local states = setmetatable({}, { __mode = "k" })
local unpackValues = unpack or table.unpack
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", shadow="", outlineShadow="OUTLINE" }
local ORDER = {"clock","zoneName","coordinates","metrics"}
local DEFAULT_STYLE = { font="inherit", outline="inherit", shadow="inherit", layoutMode="auto" }
local GETTERS = { SetFont="GetFont", SetTextColor="GetTextColor", SetShadowColor="GetShadowColor", SetShadowOffset="GetShadowOffset" }
local POINTS = { TOPLEFT=true, TOP=true, TOPRIGHT=true, LEFT=true, CENTER=true,
    RIGHT=true, BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true }

local function Read(object, method)
    if not object or not object[method] then return nil end
    local ok, a, b, c, d = pcall(object[method], object)
    if ok then return a, b, c, d end
end

local function Capture(object)
    local state = states[object]
    if state then return state end
    state = { original={}, applied={}, methods={} }
    for _, pair in ipairs({ {"GetFont","SetFont"}, {"GetTextColor","SetTextColor"},
        {"GetShadowColor","SetShadowColor"}, {"GetShadowOffset","SetShadowOffset"} }) do
        state.original[pair[2]] = { Read(object, pair[1]) }
        state.methods[pair[2]] = object[pair[2]]
    end
    states[object] = state
    return state
end

local function Write(object, state, method, a, b, c, d)
    if not object[method] then return end
    local old = state.applied[method]
    if old and old[1]==a and old[2]==b and old[3]==c and old[4]==d then
        local currentA,currentB,currentC,currentD = Read(object, GETTERS[method])
        if not object[GETTERS[method]] or (currentA==a and currentB==b and currentC==c and currentD==d) then return end
    end
    if pcall(object[method], object, a, b, c, d) then
        state.applied[method] = {a,b,c,d}
    end
end

function Text:Apply(object, config, size, color)
    if not object or not config then return false end
    local state = Capture(object)
    local original = state.original.SetFont
    local font = object.gui2ColorKey and GUI2.GetFont and GUI2:GetFont("font.family.body") or original[1]
    if config.font and config.font ~= "inherit" and LSM then
        font = LSM:Fetch("font", config.font, true) or font
    end
    size = size or config.fontSize
    if not size or size == 0 then size = original[2] end
    local flags = (not config.outline or config.outline == "inherit") and original[3] or FLAGS[config.outline]
    if font and size then Write(object, state, "SetFont", font, size, flags or "") end
    local base = state.original.SetTextColor
    local r,g,b,a = base[1],base[2],base[3],base[4]
    if object.gui2ColorKey and GUI2.GetColor then r,g,b,a = GUI2:GetColor(object.gui2ColorKey) end
    -- A false override leaves the base color neutral for text with inline value colors.
    if config.customColor and color ~= false then
        color = color or config.color
        if color then r,g,b,a = color[1],color[2],color[3],color[4] end
    end
    if r then Write(object, state, "SetTextColor", r,g,b,a or 1) end
    local combinedShadow = config.outline == "shadow" or config.outline == "outlineShadow"
    if combinedShadow then
        Write(object, state, "SetShadowColor", 0,0,0,1)
        Write(object, state, "SetShadowOffset", 1,-1)
    elseif config.shadow == "inherit" or config.shadow == nil then
        local shadow, offset = state.original.SetShadowColor, state.original.SetShadowOffset
        if shadow[1] then Write(object, state, "SetShadowColor", unpackValues(shadow)) end
        if offset[1] then Write(object, state, "SetShadowOffset", unpackValues(offset)) end
    else
        Write(object, state, "SetShadowColor", 0,0,0, config.shadow == "on" and 0.6 or 0)
        Write(object, state, "SetShadowOffset", config.shadow == "on" and 1 or 0, config.shadow == "on" and -1 or 0)
    end
    return true
end

function Text:GetOutlineSelection(config)
    local outline=config.outline or "inherit"
    if config.shadow == "on" and outline ~= "shadow" and outline ~= "outlineShadow" then
        return (outline == "none" or outline == "inherit") and "shadow" or "outlineShadow"
    end
    return outline
end

function Text:Restore(object)
    local state = object and states[object]
    if not state then return end
    for _, pair in ipairs({ {"GetFont","SetFont"}, {"GetTextColor","SetTextColor"},
        {"GetShadowColor","SetShadowColor"}, {"GetShadowOffset","SetShadowOffset"} }) do
        local applied, original = state.applied[pair[2]], state.original[pair[2]]
        if applied and original[1] ~= nil and object[pair[2]] == state.methods[pair[2]] then
            local a,b,c,d = Read(object, pair[1])
            if a==applied[1] and b==applied[2] and c==applied[3] and d==applied[4] then
                pcall(object[pair[2]], object, unpackValues(original))
            end
        end
    end
    states[object] = nil
end

function Text:GetConfig(appearance, key)
    if key == "clock" then return appearance.clock or DEFAULT_STYLE, appearance.clockPosition end
    if key == "zoneName" then return appearance.zoneName or DEFAULT_STYLE, appearance.zoneName and appearance.zoneName.position or "TOP" end
    return appearance[key] or DEFAULT_STYLE, appearance[key] and appearance[key].position
end

local function Enabled(appearance, key)
    if key == "clock" then return (appearance.clockMode or "never") ~= "never" end
    if key == "zoneName" then return appearance.zoneNameMode ~= "never" end
    local config = appearance[key]
    return config and config.enabled and (key ~= "metrics" or config.showFPS or config.showLatency)
end

-- Auto order is clock, zone, coordinates, metrics. Explicit placements never reserve rows.
function Text:Placement(appearance, key, owner)
    local config, point = self:GetConfig(appearance, key)
    point = POINTS[point] and point or "BOTTOM"
    if config.layoutMode == "custom" then return point, config.offsetX or 0, config.offsetY or 0 end
    local inset = 5
    local left, right = point:find("LEFT"), point:find("RIGHT")
    local top, bottom = point:find("TOP"), point:find("BOTTOM")
    local x = left and inset or right and -inset or 0
    local y = top and -inset or bottom and inset or 0
    local direction = top and -1 or 1
    for _, otherKey in ipairs(ORDER) do
        if otherKey == key then break end
        local other, otherPoint = self:GetConfig(appearance, otherKey)
        if Enabled(appearance, otherKey) and otherPoint == point and other.layoutMode ~= "custom" then
            local height = otherKey == "clock" and owner:GetSquareClockReservedHeight()
                or (otherKey == "zoneName" and appearance.zoneNameFontSize or other.fontSize) + 4
            y = y + direction * height
        end
    end
    -- Separate automatic offsets preserve saved custom placements when switching modes.
    return point,x+(config.autoOffsetX or 0),y+(config.autoOffsetY or 0)
end

function Text:Anchor(object, parent, appearance, key, owner)
    local point,x,y = self:Placement(appearance,key,owner)
    object:ClearAllPoints()
    object:SetPoint(point,parent,point,x,y)
    if object.SetJustifyH then
        object:SetJustifyH(point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER")
    end
end

function Text:RefreshTheme()
    local owner = YMap.Minimap
    if not owner or not owner.active or owner.appliedStyle ~= "square" then return end
    local appearance = YMap:GetDB().minimap.squareAppearance
    self:Apply(owner.zoneLabel, appearance.zoneName, appearance.zoneNameFontSize)
    self:Apply(owner.coordinateText, appearance.coordinates)
    self:Apply(_G.TimeManagerClockTicker, appearance.clock)
    if YMap.MetricsWidget then YMap.MetricsWidget:Refresh() end
end

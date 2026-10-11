local YUI = _G.YUI
local UF = YUI and YUI.YUnitFrames
if not UF then return end

UF.PRODUCT_ID, UF.STORAGE_KEY, UF.SETTINGS_ENTRY = "yunitframes", "YUnitFrames", "yunitframes.settings"
UF.UnitOrder = { "player", "target", "focus", "pet", "targettarget", "focustarget", "boss", "castbar" }
UF.Placements = { "CENTER", "LEFT_INSIDE", "LEFT_OUTSIDE", "RIGHT_INSIDE", "RIGHT_OUTSIDE", "TOP_INSIDE", "TOP_OUTSIDE", "BOTTOM_INSIDE", "BOTTOM_OUTSIDE" }
local placementSet = {}; for _, value in ipairs(UF.Placements) do placementSet[value] = true end
function UF:ElementPosition(element, root)
    local x, y, mode = element.x, element.y, element.placement
    if mode == "LEFT_INSIDE" then x = x - root.width / 2 + element.width / 2
    elseif mode == "LEFT_OUTSIDE" then x = x - root.width / 2 - element.width / 2
    elseif mode == "RIGHT_INSIDE" then x = x + root.width / 2 - element.width / 2
    elseif mode == "RIGHT_OUTSIDE" then x = x + root.width / 2 + element.width / 2
    elseif mode == "TOP_INSIDE" then y = y + root.height / 2 - element.height / 2
    elseif mode == "TOP_OUTSIDE" then y = y + root.height / 2 + element.height / 2
    elseif mode == "BOTTOM_INSIDE" then y = y - root.height / 2 + element.height / 2
    elseif mode == "BOTTOM_OUTSIDE" then y = y - root.height / 2 - element.height / 2 end
    return x, y
end
function UF:ElementBounds(element, root)
    if (element.kind == "absorbs" or element.kind == "healabsorbs") and element.absorbMode == "overlay" then
        for _, item in ipairs(root.elements) do
            if item.kind == "health" and item.enabled then
                local x, y = self:ElementPosition(item, root)
                return x, y, item.width, item.height
            end
        end
    end
    local x, y = self:ElementPosition(element, root)
    return x, y, element.width, element.height
end
UF.BarKinds = { health = true, power = true, cast = true, absorbs = true, healabsorbs = true }
UF.PreviewData = { health = 82, absorbs = false, absorbAmount = 25, healabsorbs = false, healAbsorbAmount = 20, auraCount = 5 }
function UF:BorderOutset(config, region)
    if not config.borderStyle or config.borderStyle == "none" then return 0 end
    local size = region and YUI.GUI2:GetPixelSize(region, config.borderSize, 1) or config.borderSize
    local pixel = region and YUI.GUI2:GetPixelSize(region, 1, 1) or 1
    return config.borderStyle == "double" and size * 2 + pixel or size
end
function UF:HealthTarget(element, root)
    for _, item in ipairs(root.elements) do
        if item.kind == "health" and item.enabled and (element.healthID == "" or element.healthID == item.id) then return item end
    end
end
local originalBounds = UF.ElementBounds
function UF:ElementBounds(element, root, region)
    if element.kind == "power" and element.powerMode == "attached" then
        local health = self:HealthTarget(element, root)
        if health then
            local x, y, w, h = self:ElementBounds(health, root, region)
            local ho, po = self:BorderOutset(health, region), self:BorderOutset(element, region)
            local gap = region and YUI.GUI2:SnapLayoutBoundary(region, element.attachGap) or element.attachGap
            local thick = region and YUI.GUI2:SnapLayoutBoundary(region, element.attachThickness) or element.attachThickness
            local joined = gap == 0 and ho > 0
            local distance = ho + gap + (joined and 0 or po) + thick / 2
            local side = element.attachSide
            if side == "TOP" or side == "BOTTOM" then
                return x, y + (side == "TOP" and 1 or -1) * (h / 2 + distance), math.max(2, w + 2 * ho - 2 * po), thick, false, joined and (side == "TOP" and "BOTTOM" or "TOP") or nil
            end
            return x + (side == "RIGHT" and 1 or -1) * (w / 2 + distance), y, thick, math.max(2, h + 2 * ho - 2 * po), true, joined and (side == "RIGHT" and "LEFT" or "RIGHT") or nil
        end
    end
    local x, y, w, h = originalBounds(self, element, root)
    if region then
        local left = YUI.GUI2:SnapLayoutBoundary(region, x - w / 2)
        local right = YUI.GUI2:SnapLayoutBoundary(region, x + w / 2)
        local bottom = YUI.GUI2:SnapLayoutBoundary(region, y - h / 2)
        local top = YUI.GUI2:SnapLayoutBoundary(region, y + h / 2)
        x, y, w, h = (left + right) / 2, (bottom + top) / 2, right - left, top - bottom
    end
    return x, y, w, h, element.vertical
end
function UF:AuraLayout(config)
    local vertical = config.growth == "UP" or config.growth == "DOWN"
    local extent, spacing = vertical and config.height or config.width, vertical and config.spacingY or config.spacing
    local perLine = config.perLine > 0 and config.perLine or math.max(1, math.floor((extent + spacing) / (config.iconSize + spacing)))
    return perLine, vertical
end
function UF:AuraOffset(config, index)
    local perLine, vertical = self:AuraLayout(config)
    local major, minor = (index - 1) % perLine, math.floor((index - 1) / perLine)
    local col, row = vertical and minor or major, vertical and major or minor
    local right = config.startCorner == "TOPRIGHT" or config.startCorner == "BOTTOMRIGHT"
    local bottom = config.startCorner == "BOTTOMLEFT" or config.startCorner == "BOTTOMRIGHT"
    return (right and -1 or 1) * col * (config.iconSize + config.spacing),
        (bottom and 1 or -1) * row * (config.iconSize + config.spacingY)
end
UF.KindOrder = { "text", "health", "power", "portrait", "cast", "casticon", "castname", "casttarget", "casttime", "absorbs", "healabsorbs", "auras", "indicator", "texture", "border" }
UF.Kinds = {}
for _, kind in ipairs(UF.KindOrder) do UF.Kinds[kind] = true end
UF.MAX_ELEMENTS = 32
function UF:OutlineMode(value)
    if value == "NONE" then return "none" end
    if value == "OUTLINE" then return "outline" end
    if value == "none" or value == "outline" or value == "thick" or value == "shadow" or value == "outlineShadow" then return value end
    return "outline"
end
UF.Presets, UF.Materials = {}, {}
UF.Stats = { enabled = false, events = 0, textWrites = 0, valueWrites = 0, frames = 0, pending = false, listeners = 0 }

function UF.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = UF.Copy(item) end
    return result
end

local function Number(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return math.max(minimum, math.min(maximum, value))
end
UF.Number = Number

function UF:NewElement(kind, id)
    local element = {
        id = id, kind = kind, enabled = true, x = 0, y = 0, width = 220, height = 36,
        color = { 0.22, 0.72, 0.65, 1 }, texture = "flat", alpha = 1,
        fontSize = 13, font = "", outline = "OUTLINE", align = "LEFT", text = "[name]",
        colorMode = "custom", widthMode = "auto", reverse = false, vertical = false, placement = "CENTER",
    }
    if kind == "text" then
        element.height, element.color = 22, { 0.94, 0.94, 0.96, 1 }
    elseif kind == "castname" or kind == "casttarget" or kind == "casttime" then
        element.height, element.color, element.align = 22, { 0.94, 0.94, 0.96, 1 }, "CENTER"
    elseif kind == "casticon" then
        element.width, element.height, element.color = 22, 22, { 1, 1, 1, 1 }
    elseif kind == "health" then
        element.colorMode = "class"
    elseif kind == "power" then
        element.height, element.y, element.colorMode = 5, -23, "power"
        element.powerMode, element.healthID, element.attachSide = "independent", "", "BOTTOM"
        element.attachThickness, element.attachGap = 5, 0
    elseif kind == "portrait" then
        element.width, element.height, element.x = 42, 42, -139
        element.mode, element.shape, element.portraitBorder = "2d", "square", "thin"
        element.borderColor = { 0, 0, 0, 1 }
        element.placement, element.x = "LEFT_OUTSIDE", -6
    elseif kind == "cast" then
        element.showTicks, element.tickCount = true, 0
        element.height, element.y = 18, -42
        element.color = { 0.91, 0.74, 0.35, 1 }
        element.iconPosition, element.iconGap, element.showName, element.showTime = "LEFT", 3, true, true
        element.placement, element.y = "BOTTOM_OUTSIDE", -6
    elseif kind == "absorbs" or kind == "healabsorbs" then
        element.height, element.y = 3, 22
        element.color = kind == "absorbs" and { 0.55, 0.86, 1, 0.85 } or { 0.85, 0.22, 0.35, 1 }
        element.absorbMode, element.overflow = "overlay", false
        element.reverse = kind == "healabsorbs"
        element.height, element.y = 36, 0
    elseif kind == "auras" then
        element.width, element.height, element.y = 220, 26, 46
        element.filter, element.count, element.iconSize, element.spacing = "HARMFUL", 8, 24, 4
        element.growth, element.duration, element.stacks = "RIGHT", true, true
        element.perLine, element.spacingY, element.startCorner = 0, 4, "TOPLEFT"
        element.cooldown, element.hideSingle = true, true
        element.auraBorder, element.auraBorderColor = 1, { 0, 0, 0, 1 }
        element.durationStyle = { font = "default", fontSize = 10, outline = "outline", color = { 1, 1, 1, 1 }, point = "TOP", x = 0, y = -1 }
        element.stackStyle = { font = "default", fontSize = 11, outline = "outline", color = { 1, 1, 1, 1 }, point = "BOTTOMRIGHT", x = -1, y = 1 }
    elseif kind == "indicator" then
        element.width, element.height, element.y = 18, 18, 22
        element.indicator = "raid"
    elseif kind == "texture" then
        element.color = { 0.045, 0.05, 0.065, 0.95 }
        element.width, element.height = 224, 54
    elseif kind == "border" then
        element.width, element.height, element.y = 224, 48, -4
        element.borderStyle, element.borderSize = "solid", 1
        element.color = { 0, 0, 0, 1 }
    end
    if self.BarKinds[kind] then
        element.backgroundEnabled, element.backgroundColor = true, { 0.045, 0.05, 0.065, 1 }
        element.borderStyle, element.borderSize, element.borderColor = "none", 1, { 0, 0, 0, 1 }
    end
    return element
end

local positions = {
    player = { -280, -180 }, target = { 280, -180 }, focus = { 350, 10 }, pet = { -280, -260 },
    targettarget = { 280, -270 }, focustarget = { 350, -75 }, boss = { 650, 140 }, castbar = { 0, -260 },
}
function UF:DefaultUnit(unit)
    local elements = {}
    local function Add(kind, id, changes)
        local item = self:NewElement(kind, id)
        for key, value in pairs(changes or {}) do item[key] = value end
        elements[#elements + 1] = item
    end
    local mini = unit == "pet" or unit == "targettarget" or unit == "focustarget"
    if unit == "castbar" then
        Add("casttime", "casttime", { width = 48, placement = "RIGHT_INSIDE", x = -4, align = "RIGHT" })
        Add("castname", "castname", { width = 184, placement = "LEFT_INSIDE", x = 4, align = "LEFT" })
        Add("casttarget", "casttarget", { width = 260, placement = "BOTTOM_OUTSIDE", y = -4 })
        Add("casticon", "casticon", { placement = "LEFT_OUTSIDE", x = -3 })
        Add("cast", "cast", { width = 260, height = 22, placement = "CENTER", x = 0, y = 0,
            iconPosition = "NONE", showName = false, showTime = false })
        return { enabled = true, hideNative = true, width = 260, height = 22, scale = 1, point = "CENTER", relativePoint = "CENTER",
            x = 0, y = -260, spacing = 96, elements = elements, nextID = 1 }
    end
    Add("text", "name", { text = "[name]", width = 125, placement = "LEFT_INSIDE", x = 8, fontSize = mini and 11 or 13 })
    Add("text", "healthText", { text = "[perhp]%", width = 70, placement = "RIGHT_INSIDE", x = -8, align = "RIGHT" })
    if unit ~= "player" and unit ~= "pet" then Add("indicator", "raid", { x = 0, y = 26 }) end
    if not mini then Add("absorbs", "absorbs") end
    if not mini and unit ~= "player" then
        Add("cast", "cast")
        Add("auras", "debuffs", { filter = unit == "boss" and "HARMFUL|PLAYER" or "HARMFUL" })
        if unit ~= "boss" then Add("auras", "buffs", { filter = "HELPFUL", y = 78 }) end
    end
    if not mini or unit == "pet" then Add("power", "power", { powerMode = "attached", healthID = "" }) end
    Add("health", "health", { height = mini and 26 or 36 })
    return { enabled = true, hideNative = true, width = 224, height = 54, scale = mini and 0.85 or 1, point = "CENTER", relativePoint = "CENTER",
        x = positions[unit][1], y = positions[unit][2], spacing = 96, elements = elements, nextID = 1 }
end

function UF:Defaults()
    local db = { version = 1, castPartsMigrated = true, enabled = self.Client.defaultEnabled == true, hideNative = true, units = {}, colors = { class = {}, power = {} } }
    for _, unit in ipairs(self.UnitOrder) do db.units[unit] = self:DefaultUnit(unit) end
    return db
end

local function ColorTable(kind) return kind == "class" and RAID_CLASS_COLORS or PowerBarColor end
function UF:ColorKeys(kind)
    local keys = {}
    for token, color in pairs(ColorTable(kind) or {}) do
        if type(token) == "string" and type(color) == "table" and type(color.r) == "number"
            and type(color.g) == "number" and type(color.b) == "number" then keys[#keys + 1] = token end
    end
    table.sort(keys)
    return keys
end
function UF:GetColor(kind, token)
    local colors = self:GetDB().colors[kind]
    local override = token and colors and colors[token]
    if override then return override[1], override[2], override[3] end
    local defaults = ColorTable(kind)
    local color = token and defaults and defaults[token]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end
function UF:ColorCode(kind, token)
    local r, g, b = self:GetColor(kind, token)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function UF:SetColor(kind, token, color)
    if self:InCombat() or (kind ~= "class" and kind ~= "power") then return false end
    local defaults = ColorTable(kind)
    if not defaults or not defaults[token] or type(color) ~= "table" then return false end
    self:GetDB().colors[kind][token] = { Number(color[1], 0, 1, 1), Number(color[2], 0, 1, 1), Number(color[3], 0, 1, 1) }
    return true
end
function UF:ResetColors(kind, token)
    if self:InCombat() then return false end
    if kind and kind ~= "class" and kind ~= "power" then return false end
    if kind and token then self:GetDB().colors[kind][token] = nil
    else self:GetDB().colors = { class = {}, power = {} } end
    return true
end

local aligns = { LEFT = true, CENTER = true, RIGHT = true }
local points = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local filters = { HELPFUL = true, HARMFUL = true, ["HELPFUL|PLAYER"] = true, ["HARMFUL|PLAYER"] = true, ["HARMFUL|RAID"] = true }
function UF:NormalizeElement(element, index, used)
    if type(element) ~= "table" or not self.Kinds[element.kind] then return nil end
    local default = self:NewElement(element.kind, "element" .. index)
    local result = {}
    for key, fallback in pairs(default) do
        local value = element[key]
        if type(value) == type(fallback) then result[key] = self.Copy(value) else result[key] = self.Copy(fallback) end
    end
    if #result.id > 64 or not result.id:match("^[%w_-]+$") or used[result.id] then result.id = "repaired" .. index end
    while used[result.id] do result.id = result.id .. "x" end
    used[result.id] = true
    result.x = Number(result.x, -1000, 1000, 0)
    -- Older layouts stored centre-relative offsets. Preserve their screen positions.
    result.placement = placementSet[element.placement] and element.placement or "CENTER"
    if result.kind == "absorbs" or result.kind == "healabsorbs" then
        result.absorbMode = element.absorbMode == "overlay" and "overlay" or "independent"
    end
    result.y = Number(result.y, -1000, 1000, 0)
    result.width = Number(result.width, 4, 800, default.width)
    result.height = Number(result.height, 2, 300, default.height)
    result.alpha = Number(result.alpha, 0, 1, 1)
    result.fontSize = Number(result.fontSize, 8, 64, 13)
    result.font = result.font:sub(1, 160)
    result.text = result.text:sub(1, 512)
    result.texture = result.texture:sub(1, 160)
    result.align = aligns[result.align] and result.align or "LEFT"
    result.widthMode = result.widthMode == "fixed" and "fixed" or "auto"
    result.outline = self:OutlineMode(result.outline)
    result.colorMode = (result.colorMode == "class" or result.colorMode == "power") and result.colorMode or "custom"
    for i = 1, 4 do result.color[i] = Number(result.color[i], 0, 1, default.color[i]) end
    if self.BarKinds[result.kind] then
        result.borderStyle = (result.borderStyle == "solid" or result.borderStyle == "double") and result.borderStyle or "none"
        result.borderSize = Number(result.borderSize, 1, 8, 1)
        for i = 1, 4 do result.borderColor[i] = Number(result.borderColor[i], 0, 1, default.borderColor[i]) end
    end
    if self.BarKinds[result.kind] then
        for i = 1, 4 do result.backgroundColor[i] = Number(result.backgroundColor[i], 0, 1, default.backgroundColor[i]) end
    end
    if result.kind == "power" then
        result.powerMode = result.powerMode == "attached" and "attached" or "independent"
        result.attachSide = ({ TOP = true, BOTTOM = true, LEFT = true, RIGHT = true })[result.attachSide] and result.attachSide or "BOTTOM"
        result.attachThickness = Number(result.attachThickness, 2, 80, 5)
        result.attachGap = Number(result.attachGap, 0, 40, 0)
        result.healthID = result.healthID:sub(1, 64)
    end
    if result.kind == "auras" then
        result.filter = filters[result.filter] and result.filter or "HARMFUL"
        result.count = math.floor(Number(result.count, 1, 16, 8))
        result.iconSize = Number(result.iconSize, 12, 64, 24)
        result.spacing = Number(result.spacing, 0, 20, 4)
        result.growth = ({ LEFT = true, RIGHT = true, UP = true, DOWN = true })[result.growth] and result.growth or "RIGHT"
        result.perLine = math.floor(Number(result.perLine, 0, 16, 0))
        result.spacingY = Number(element.spacingY, 0, 20, result.spacing)
        result.startCorner = ({ TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true })[element.startCorner] and element.startCorner or (result.growth == "LEFT" and "TOPRIGHT" or "TOPLEFT")
        result.auraBorder = Number(result.auraBorder, 0, 8, 1)
        for i = 1, 4 do result.auraBorderColor[i] = Number(result.auraBorderColor[i], 0, 1, default.auraBorderColor[i]) end
        for _, key in ipairs({ "durationStyle", "stackStyle" }) do
            local style, fallback = result[key], default[key]
            style.font = type(style.font) == "string" and style.font:sub(1, 160) or fallback.font
            style.fontSize = Number(style.fontSize, 8, 32, fallback.fontSize)
            style.outline = self:OutlineMode(style.outline)
            style.widthMode = style.widthMode == "fixed" and "fixed" or "auto"
            style.width = Number(style.width, 4, 600, 40)
            style.point = points[style.point] and style.point or fallback.point
            style.x, style.y = Number(style.x, -80, 80, fallback.x), Number(style.y, -80, 80, fallback.y)
            if type(style.color) ~= "table" then style.color = self.Copy(fallback.color) end
            for i = 1, 4 do style.color[i] = Number(style.color[i], 0, 1, fallback.color[i]) end
        end
    elseif result.kind == "portrait" then
        result.mode = result.mode == "3d" and "3d" or "2d"
        result.shape = (result.shape == "circle" or result.shape == "rounded") and result.shape or "square"
        result.portraitBorder = (result.portraitBorder == "none" or result.portraitBorder == "thick") and result.portraitBorder or "thin"
        for i = 1, 4 do result.borderColor[i] = Number(result.borderColor[i], 0, 1, default.borderColor[i]) end
    elseif result.kind == "cast" then
        result.tickCount = math.floor(Number(result.tickCount, 0, 32, 0))
        result.iconPosition = (result.iconPosition == "RIGHT" or result.iconPosition == "NONE") and result.iconPosition or "LEFT"
        result.iconGap = Number(result.iconGap, 0, 20, 3)
    elseif result.kind == "indicator" then
        result.indicator = (result.indicator == "leader" or result.indicator == "combat") and result.indicator or "raid"
    elseif result.kind == "border" then
        result.borderStyle = result.borderStyle == "double" and "double" or "solid"
        result.borderSize = Number(result.borderSize, 1, 8, 1)
    end
    return result
end

function UF:Normalize(source)
    local result = self:Defaults()
    if type(source) ~= "table" then return result end
    if source.enabled ~= nil then result.enabled = source.enabled == true end
    result.hideNative = source.hideNative ~= false
    if type(source.colors) == "table" then
        for _, kind in ipairs({ "class", "power" }) do
            if type(source.colors[kind]) == "table" then
                for _, token in ipairs(self:ColorKeys(kind)) do
                    local color = source.colors[kind][token]
                    if type(color) == "table" then
                        result.colors[kind][token] = { Number(color[1], 0, 1, 1), Number(color[2], 0, 1, 1), Number(color[3], 0, 1, 1) }
                    end
                end
            end
        end
    end
    for _, unit in ipairs(self.UnitOrder) do
        local from = type(source.units) == "table" and source.units[unit]
        local to = result.units[unit]
        if type(from) == "table" then
            to.enabled = from.enabled ~= false
            to.hideNative = from.hideNative == nil and source.hideNative ~= false or from.hideNative == true
            to.point = points[from.point] and from.point or "CENTER"
            to.relativePoint = points[from.relativePoint] and from.relativePoint or "CENTER"
            for _, key in ipairs({ "x", "y" }) do to[key] = Number(from[key], -4000, 4000, to[key]) end
            to.width = Number(from.width, 40, 800, to.width)
            to.height = Number(from.height, 20, 300, to.height)
            to.scale = Number(from.scale, 0.5, 2, to.scale)
            to.spacing = Number(from.spacing, 35, 300, to.spacing)
            to.nextID = math.floor(Number(from.nextID, 1, 1000000, 1))
            if type(from.elements) == "table" then
                to.elements = {}
                local used = {}
                for i = 1, math.min(#from.elements, self.MAX_ELEMENTS) do
                    local element = self:NormalizeElement(from.elements[i], i, used)
                    if element then to.elements[#to.elements + 1] = element end
                end
            end
        end
    end
    local castUnit = result.units.castbar
    local old = castUnit.elements[1]
    if #castUnit.elements == 1 and old.kind == "cast" and not source.castPartsMigrated then
        local parts = self:DefaultUnit("castbar").elements
        for _, part in ipairs(parts) do
            if part.kind ~= "cast" then
                part.placement = "CENTER"
                local x, y = self:ElementPosition(old, castUnit)
                part.x, part.y = x, y
                part.font, part.fontSize, part.outline = old.font, old.fontSize, old.outline
                if part.kind == "casticon" then
                    part.width, part.height = old.height, old.height
                    part.x = x + (old.iconPosition == "RIGHT" and 1 or -1) * (old.width / 2 + old.height / 2 + old.iconGap)
                    part.enabled = old.iconPosition ~= "NONE"
                elseif part.kind == "castname" then part.width = math.max(4, old.width - 48); part.x = x - 20; part.enabled = old.showName
                elseif part.kind == "casttime" then part.x = x + old.width / 2 - 28; part.enabled = old.showTime
                else part.width = old.width; part.y = y - old.height / 2 - 15 end
            end
        end
        old.iconPosition, old.showName, old.showTime = "NONE", false, false
        parts[#parts] = old; castUnit.elements = parts
    end
    result.castPartsMigrated = true
    return result
end

function UF:GetDB()
    local profile = YUI.DB and YUI.DB:GetProfile(self.PRODUCT_ID)
    if not profile then self.scratch = self.scratch or self:Defaults(); return self.scratch end
    if self.profile ~= profile or self.db ~= profile[self.STORAGE_KEY] then
        self.profile = profile
        self.db = self:Normalize(profile[self.STORAGE_KEY])
        profile[self.STORAGE_KEY] = self.db
    end
    return self.db
end

function UF:AddElement(unit, kind)
    local config = self:GetDB().units[unit]
    if not config or not self.Kinds[kind] or #config.elements >= self.MAX_ELEMENTS then return nil end
    local id
    repeat
        id = "custom" .. config.nextID; config.nextID = config.nextID + 1
        local found = false
        for _, element in ipairs(config.elements) do if element.id == id then found = true end end
        if not found then break end
    until false
    local element = self:NewElement(kind, id)
    table.insert(config.elements, 1, element)
    return element
end

function UF:MoveElement(unit, id, delta)
    local elements = self:GetDB().units[unit].elements
    for i, element in ipairs(elements) do
        if element.id == id then
            local target = math.max(1, math.min(#elements, i + delta))
            if target == i then return false end
            table.remove(elements, i); table.insert(elements, target, element); return true
        end
    end
    return false
end

function UF:RegisterMaterial(id, path)
    if type(id) ~= "string" or id == "" or type(path) ~= "string" or path == "" or #id > 160 or self.Materials[id] then return false end
    self.Materials[id] = path
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    if media then media:Register("statusbar", id, path) end
    return true
end

function UF:RegisterPreset(id, definition)
    if type(id) ~= "string" or type(definition) ~= "table" or type(definition.settings) ~= "table" then return false end
    if self.Presets[id] then return false end
    self.Presets[id] = { name = definition.name or id, settings = self:Normalize(definition.settings) }
    return true
end

function UF:ApplyPreset(id)
    if self:InCombat() or not self.Presets[id] then return false end
    local db = self:GetDB()
    local replacement = self:Normalize(self.Presets[id].settings)
    replacement.enabled = db.enabled
    if self.profile then self.profile[self.STORAGE_KEY] = replacement else self.scratch = replacement end
    self.db = replacement
    self:ApplySettings()
    if self.RefreshSettings then self:RefreshSettings() end
    return true
end

function UF:T(key)
    return YUI.Locale:Get("YUnitFrames")[key]
end

-- A clipboard captures values, never references to another unit's configuration.
UF.CopyGroups = { "textStyle", "barStyle", "size", "position", "content" }
local textKinds = { text = true, castname = true, casttarget = true, casttime = true }
local groupFields = {
    textStyle = { "font", "fontSize", "outline", "color", "colorMode" },
    barStyle = { "texture", "color", "colorMode", "backgroundEnabled", "backgroundColor", "borderStyle", "borderSize", "borderColor" },
    size = { "width", "height", "widthMode", "iconSize", "attachThickness" },
    position = { "placement", "x", "y", "vertical", "reverse", "attachSide", "attachGap", "perLine", "spacing", "spacingY", "growth", "startCorner" },
}
local contentFields = {
    text = { "text" }, auras = { "filter", "count", "duration", "stacks", "hideSingle", "cooldown" },
    cast = { "showTicks", "tickCount", "showName", "showTime", "iconPosition", "iconGap" },
    indicator = { "indicator" }, portrait = { "mode", "shape", "portraitBorder", "borderColor" },
    absorbs = { "absorbMode", "overflow" }, healabsorbs = { "absorbMode", "overflow" },
}
function UF:CanCopySettings(element, group)
    if group == "content" then return contentFields[element.kind] ~= nil end
    if group == "textStyle" then return textKinds[element.kind] == true or element.kind == "auras" end
    if group == "barStyle" then return self.BarKinds[element.kind] == true end
    return groupFields[group] ~= nil
end
function UF:CopySettings(element, group)
    if self:InCombat() or not self:CanCopySettings(element, group) then return false end
    local fields = group == "content" and contentFields[element.kind] or groupFields[group]
    if group == "textStyle" and element.kind == "auras" then fields = { "durationStyle", "stackStyle" } end
    if not fields or (group == "textStyle" and not textKinds[element.kind] and element.kind ~= "auras")
        or (group == "barStyle" and not self.BarKinds[element.kind]) then return false end
    local values = {}
    for _, key in ipairs(fields) do if element[key] ~= nil then values[key] = self.Copy(element[key]) end end
    self.settingsClipboard = { group = group, kind = element.kind, mode = element.powerMode, values = values }
    return true
end
function UF:CanPasteSettings(target)
    local clip = self.settingsClipboard
    if not clip then return false end
    if clip.group == "textStyle" then return (textKinds[clip.kind] and textKinds[target.kind]) or (clip.kind == "auras" and target.kind == "auras") end
    if clip.group == "barStyle" then return self.BarKinds[target.kind] == true end
    if clip.kind ~= target.kind then return false end
    if clip.group == "size" or clip.group == "position" then return clip.mode == target.powerMode end
    return true
end
function UF:PasteSettings(target)
    if self:InCombat() or not self:CanPasteSettings(target) then return false end
    for key, value in pairs(self.settingsClipboard.values) do
        if self.settingsClipboard.group == "textStyle" and target.kind == "auras" then
            for _, field in ipairs({ "font", "fontSize", "outline", "color" }) do target[key][field] = self.Copy(value[field]) end
        else target[key] = self.Copy(value) end
    end
    return true
end

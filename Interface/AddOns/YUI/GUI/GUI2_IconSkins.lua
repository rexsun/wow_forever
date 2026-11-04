local YUI = _G.YUI
local GUI2 = YUI and YUI.GUI2
if not GUI2 then return end

-- 定义和参数仅在配置链路解析；热状态绘制只接收展开后的快照。
local Skins = { defaultId = "minimal-square", definitions = {}, order = {} }
GUI2.IconSkins = Skins
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local function Finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function Color(value)
    if type(value) ~= "table" then return nil end
    local result = { value.r or value[1], value.g or value[2], value.b or value[3], value.a or value[4] }
    for i = 1, 4 do if not Finite(result[i]) or result[i] < 0 or result[i] > 1 then return nil end end
    return result
end
local parameters = {
    { key = "border", type = "select", choices = { "none", "thin", "medium", "thick", "extraThick", "contour", "shade" }, aliases = { soft = "thin" } },
    { key = "borderColor", type = "color", inlineWith = "border", enabledWhen = { key = "border", values = { thin = true, medium = true, thick = true, extraThick = true } } },
    { key = "background", type = "select", choices = { "custom", "transparent", "blizzard" }, products = { Flare = true } },
    { key = "backgroundColor", type = "color", products = { Flare = true }, inlineWith = "background", enabledWhen = { key = "background", value = "custom" } },
    { key = "shadow", type = "boolean" },
    { key = "shadowColor", type = "color", inlineWith = "shadow", enabledWhen = { key = "shadow", value = true } },
    { key = "zoom", type = "number", min = 0, max = 0.24, step = 0.01, displayScale = 100, suffix = "%" },
}
function Skins:Register(id, definition)
    assert(type(id) == "string" and type(definition) == "table", "invalid icon skin")
    assert(not self.definitions[id], "duplicate icon skin")
    self.definitions[id] = definition
    self.order[#self.order + 1] = id
end
local function Recipe(label, shape)
    return { label = label, shape = shape, border = "thin", zoom = 0.08,
        borderColor = { 0, 0, 0, 1 }, background = "custom", backgroundColor = { 0, 0, 0, 0.72 },
        shadow = true, shadowColor = { 0, 0, 0, 0.6 }, parameters = Copy(parameters) }
end
Skins:Register("minimal-square", Recipe("方形", "square"))
Skins:Register("minimal-rounded", Recipe("圆角方形", "roundedSquare"))
Skins:Register("minimal-flat", Recipe("扁平方形", "flatSquare"))
Skins:Register("minimal-flat-rounded", Recipe("扁平圆角", "flatRounded"))
Skins:Register("minimal-wide-square", Recipe("微扁方形", "wideSquare"))
Skins:Register("minimal-wide", Recipe("微扁圆角", "wideRounded"))
Skins:Register("minimal-circle", Recipe("圆形", "circle"))
Skins:Register("minimal-diamond", Recipe("菱形", "diamond"))
local shapeIds = {}
for id, definition in pairs(Skins.definitions) do shapeIds[definition.shape] = id end
local aliases = { ["borderless-square"] = "minimal-square", ["shadow-rounded"] = "minimal-rounded" }

function Skins:IsValidId(id)
    return type(id) == "string" and #id <= 80 and id:match("^[%w_-]+$") ~= nil
end
function Skins:Label(key, fallback)
    local L = YUI.Locale and YUI.Locale:Get("Core")
    local text = L and L["icon_skin." .. key]
    return text and text ~= "icon_skin." .. key and text or fallback
end
function Skins:GetOptions(current, native)
    local options = {}
    current = aliases[current] or current
    if current and current ~= "legacy" and current ~= "masque" and current ~= "native" and not self.definitions[current] then
        options[#options + 1] = { value = current, label = self:Label("unavailable", "皮肤不可用（使用默认外观）") }
    end
    if native then options[#options + 1] = { value = "native", label = self:Label("native", "原生外观") } end
    for _, id in ipairs(self.order) do
        options[#options + 1] = { value = id, label = self:Label(id, self.definitions[id].label) }
    end
    options[#options + 1] = { value = "masque", label = "Masque" }
    for _, option in ipairs(options) do option.text = option.label end
    return options
end
function Skins:GetParameters(id, product)
    local definition = self.definitions[aliases[id] or id]
    local specs = definition and definition.parameters
    if not specs or not product then return specs end
    local visible = {}
    for _, spec in ipairs(specs) do
        if not spec.products or spec.products[product] then visible[#visible + 1] = spec end
    end
    return visible
end
local function Parameter(definition, key)
    for _, spec in ipairs(definition and definition.parameters or {}) do
        if spec.key == key then return spec end
    end
end
local function ValidateValue(spec, value)
    if spec.type == "color" then return Color(value) end
    if spec.type == "boolean" then if type(value) == "boolean" then return value end
    elseif spec.type == "number" then
        if Finite(value) and value >= spec.min and value <= spec.max then return value end
    elseif spec.type == "select" then
        value = spec.aliases and spec.aliases[value] or value
        for _, choice in ipairs(spec.choices) do if value == choice then return value end end
    end
end
-- 有界纯数据；未知皮肤的参数保留用于跨安装分享，不参与当前绘制。
function Skins:NormalizeOptions(source)
    if type(source) ~= "table" then return nil, "invalid skin options" end
    local result, count = {}, 0
    for id, values in pairs(source) do
        count = count + 1
        if count > 32 or not self:IsValidId(id) or type(values) ~= "table" then return nil, "invalid skin options" end
        local target, fields = {}, 0
        for key, value in pairs(values) do
            fields = fields + 1
            if fields > 32 or not self:IsValidId(key) then return nil, "invalid skin parameter" end
            local spec = Parameter(self.definitions[aliases[id] or id], key)
            local normalized
            if spec then normalized = ValidateValue(spec, value)
            elseif type(value) == "boolean" or (type(value) == "string" and #value <= 128) or Finite(value) then normalized = value
            elseif type(value) == "table" then normalized = Color(value) end
            if normalized == nil then return nil, "invalid skin parameter " .. key end
            target[key] = normalized
        end
        result[id] = target
    end
    return result
end
local function LegacyValues(style, product)
    local flare = product == "Flare"
    local border = (flare and style.border or style.iconBorder) or "thin"
    if border == "soft" then border = "thin" end
    local background = flare and style.background or style.iconBackground
    if background == "black" or not background then background = "custom" end
    local function LegacyColor(value, fallback)
        if type(value) ~= "table" then return Copy(fallback) end
        local channels = { value.r or value[1], value.g or value[2], value.b or value[3], value.a or value[4] }
        for i = 1, 4 do channels[i] = Finite(channels[i]) and math.max(0, math.min(1, channels[i])) or fallback[i] end
        return channels
    end
    return {
        border = border,
        zoom = style.iconZoom or 0.08,
        borderColor = LegacyColor(flare and style.borderColor or style.iconBorderColor, { 0, 0, 0, 1 }),
        background = background,
        backgroundColor = LegacyColor(flare and style.backgroundColor or style.iconBackgroundColor,
            flare and { 34 / 255, 34 / 255, 34 / 255, 0.72 } or { 0, 0, 0, 0.72 }),
        shadow = (flare and style.shadow ~= false) or (not flare and style.iconShadow ~= false),
        shadowColor = LegacyColor(flare and style.shadowColor or style.iconShadowColor, { 0, 0, 0, 0.5 }),
    }
end
function Skins:NormalizeSettings(style, product)
    local id = style.skinId
    if not self:IsValidId(id) then id = nil end
    local options = type(style.skinOptions) == "table" and self:NormalizeOptions(style.skinOptions) or nil
    if not id or id == "legacy" then
        local shape = product == "Flare" and style.skin or style.iconShape
        id = product == "Flare" and shape == "blizzard" and "native" or shapeIds[shape == "rounded" and "roundedSquare" or shape] or self.defaultId
        options = options or {}
        if id ~= "native" then options[id] = LegacyValues(style, product) end
    elseif not options then
        options = {}
        -- 早期完整预设覆盖旧字段；按当时实际配方迁移，不能复活隐藏的旧参数。
        local definition = self.definitions[aliases[id] or id]
        if definition then
            local values = {}
            for _, spec in ipairs(definition.parameters or {}) do values[spec.key] = Copy(definition[spec.key]) end
            -- 旧完整预设只有 shadow-rounded 启用阴影，不随新版默认值改变。
            values.shadow = id == "shadow-rounded"
            if id == "borderless-square" then values.border = "none" end
            if id == "shadow-rounded" then values.border = "medium" end
            options[aliases[id] or id] = values
            if product == "Halo" then style.cooldownSwipeColor = { 0, 0, 0, 0.82 } end
        end
    end
    if aliases[id] then
        if options[id] then options[aliases[id]], options[id] = options[id], nil end
        id = aliases[id]
    end
    style.skinId, style.skinOptions = id, options
    return style
end
function Skins:Resolve(style, product, selectedId)
    -- 不改变配置；旧配置在其所属产品的加载/应用入口持久迁移。
    if not style.skinOptions or not style.skinId or style.skinId == "legacy" or aliases[style.skinId] then
        style = self:NormalizeSettings(Copy(style), product)
    end
    local id = selectedId or style.skinId
    local definition = self.definitions[id] or self.definitions[self.defaultId]
    local values = style.skinOptions and style.skinOptions[id]
    local recipe = {}
    for key, value in pairs(definition) do if key ~= "parameters" then recipe[key] = Copy(value) end end
    for _, spec in ipairs(definition.parameters or {}) do
        local value = values and values[spec.key]
        if value ~= nil then
            local normalized = ValidateValue(spec, value)
            if normalized ~= nil then recipe[spec.key] = normalized end
        end
    end
    return recipe
end
function Skins:WithSelection(style, product, id)
    if not self:IsValidId(id) then return nil end
    local copy = self:NormalizeSettings(Copy(style), product)
    local source, target = self.definitions[copy.skinId], self.definitions[id]
    -- 仅现有形状变体共用调整项；独立皮肤仍使用自己的参数定义和记忆。
    if id ~= copy.skinId and source and target
        and shapeIds[source.shape] == copy.skinId and shapeIds[target.shape] == id then
        local values = self:Resolve(copy, product)
        local options = copy.skinOptions[id] or {}
        for _, spec in ipairs(self:GetParameters(id, product) or {}) do
            local value = ValidateValue(spec, values[spec.key])
            if value ~= nil then options[spec.key] = Copy(value) end
        end
        copy.skinOptions[id] = options
    end
    return { skinId = id, skinOptions = copy.skinOptions }
end
function Skins:WithParameter(style, product, key, value)
    local copy = self:NormalizeSettings(Copy(style), product)
    local spec = Parameter(self.definitions[copy.skinId], key)
    local normalized
    if spec then normalized = ValidateValue(spec, value) end
    if normalized == nil then return nil end
    copy.skinOptions[copy.skinId] = copy.skinOptions[copy.skinId] or {}
    copy.skinOptions[copy.skinId][key] = Copy(normalized)
    return copy.skinOptions
end
local function WriteColor(target, color)
    target = type(target) == "table" and target or {}
    for i = 1, 4 do target[i] = color[i] end
    target.r, target.g, target.b, target.a = nil, nil, nil, nil
    return target
end
function Skins:ApplyRecipe(style, product)
    if product == "Flare" and (style.skinId == "native"
        or ((not style.skinId or style.skinId == "legacy") and style.skin == "blizzard")) then
        style.skin = "blizzard"
        return style
    end
    local recipe = self:Resolve(style, product)
    if product == "Flare" then
        style.skin, style.border, style.iconZoom = recipe.shape, recipe.border, recipe.zoom
        style.borderColor = WriteColor(style.borderColor, recipe.borderColor)
        style.backgroundColor = WriteColor(style.backgroundColor, recipe.backgroundColor)
        style.background = recipe.background
        style.shadow, style.shadowColor = recipe.shadow, WriteColor(style.shadowColor, recipe.shadowColor)
    else
        style.iconShape, style.iconBorder, style.iconZoom = recipe.shape, recipe.border, recipe.zoom
        style.iconBorderColor, style.iconBackgroundColor = Copy(recipe.borderColor), Copy(recipe.backgroundColor)
        style.iconBackground = recipe.background
        if recipe.background == "transparent" then style.iconBackgroundColor[4] = 0 end
        style.iconShadow, style.iconShadowColor = recipe.shadow, Copy(recipe.shadowColor)
    end
    return style
end
function Skins:GetMasque()
    return LibStub and LibStub("Masque", true) or nil
end

local YUI = _G.YUI
local GUI = YUI and YUI.GUI2
if not GUI then return end

-- Presentation metadata only. No power reads, events or animation drivers.
local Points = {}
GUI.ResourcePoints = Points
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function Media(name)
    return YUI.Assets and YUI.Assets:Core("gui2\\shapes\\" .. name .. ".tga")
        or "Interface\\AddOns\\YUI\\Media\\Core\\gui2\\shapes\\" .. name .. ".tga"
end
local shapes = {}
for _, name in ipairs({ "circle", "square", "diamond", "star" }) do
    local prefix = name == "circle" and "circle" or "point-" .. name
    local borders = {}
    for index = 1, 4 do borders[index] = Media(prefix .. "-border-" .. index) end
    shapes[name] = { mask = Media(prefix .. "-mask"), borders = borders,
        inverse = Media(name == "circle" and "duration-ring-inner-mask" or prefix .. "-inverse-mask") }
end

-- Atlas names are from the fixed Mainline 12.1.5.70575 UnitFrame templates.
-- Missing client art is detected before use; the public count renderer remains.
local natives = {
    arcane = { "UF-Arcane-BG", "UF-Arcane-Icon", shape = "circle" },
    essence = { "UF-Essence-BG", "UF-Essence-Icon-Active", recharge = "UF-Essence-Icon-Prog", shape = "circle" },
    -- Both 14x15 rogue glyphs have their alpha center about 1/4 texel below
    -- the symmetric druid glyph. Match that visual center without changing art.
    rogue = { "uf-roguecp-bg-dis", "uf-roguecp-icon-red", charged = "uf-roguecp-icon-blue", fillY = 0.25, shape = "circle" },
    druid = { "UF-DruidCP-BG-Dis", "UF-DruidCP-Icon", shape = "circle" },
    chi = { "uf-chi-bg", "uf-chi-icon", backgroundY = -2.5, shape = "circle" },
    holy = { "uf-holypower-rune%d", "uf-holypower-rune%d-active", variants = 3, shape = "diamond" },
    shards = { "UF-SoulShard-Holder", "UF-SoulShard-Icon", backgroundY = -4.5, fillY = -3, shape = "diamond" },
    runeBlood = { "UF-DKRunes-BGDis", "UF-DKRunes-Blood-SkullActive", shape = "circle" },
    runeFrost = { "UF-DKRunes-BGDis", "UF-DKRunes-Frost-SkullActive", shape = "circle" },
    runeUnholy = { "UF-DKRunes-BGDis", "UF-DKRunes-Unholy-SkullActive", shape = "circle" },
}
local atlasCache, nativeCache = {}, {}
local function Atlas(name)
    if atlasCache[name] ~= nil then return atlasCache[name] or nil end
    local query = C_Texture and C_Texture.GetAtlasInfo
    local ok, info
    if query then ok, info = pcall(query, name) end
    local texture = ok and info and (info.file or info.filename)
    if (type(texture) ~= "string" and type(texture) ~= "number") or texture == "" or texture == 0 then
        atlasCache[name] = false; return nil
    end
    local value = { texture = texture, textureAtlas = name, textureU0 = info.leftTexCoord or 0,
        textureU1 = info.rightTexCoord or 1, textureV0 = info.topTexCoord or 0,
        textureV1 = info.bottomTexCoord or 1, width = info.width or 1, height = info.height or 1 }
    atlasCache[name] = value
    return value
end

local function CompileNativeLayout(definition, background, fill, recharge, charged)
    local layout = {
        background = { width = background.width, height = background.height, y = definition.backgroundY or 0 },
        fill = { width = fill.width, height = fill.height, y = definition.fillY or 0 },
        recharge = { width = recharge.width, height = recharge.height, y = definition.fillY or 0 },
        charged = { width = charged.width, height = charged.height, y = definition.fillY or 0 },
    }
    local width, bottom, top = 0, math.huge, -math.huge
    for _, art in pairs(layout) do
        width = math.max(width, art.width)
        bottom = math.min(bottom, art.y - art.height * 0.5)
        top = math.max(top, art.y + art.height * 0.5)
    end
    -- All states share one square canvas and one scale. Native active art may
    -- extend beyond its background; fitting each layer separately loses that
    -- relationship and stretches non-square holders.
    local size, centerY = math.max(1, width, top - bottom), (top + bottom) * 0.5
    for _, art in pairs(layout) do
        art.width, art.height, art.y = art.width / size, art.height / size, (art.y - centerY) / size
    end
    return layout
end

function Points:GetNativeStyle(name, index)
    local definition = natives[name]
    if not definition then return nil end
    local variant = definition.variants and ((index or 1) - 1) % definition.variants + 1 or 1
    local key = name .. ":" .. variant
    if nativeCache[key] ~= nil then return nativeCache[key] or nil end
    local backgroundName, fillName = definition[1], definition[2]
    if definition.variants then
        backgroundName, fillName = backgroundName:format(variant), fillName:format(variant)
    end
    local background, fill = Atlas(backgroundName), Atlas(fillName)
    local recharge = definition.recharge and Atlas(definition.recharge) or fill
    if not background or not fill or not recharge then nativeCache[key] = false; return nil end
    local charged = definition.charged and Atlas(definition.charged) or fill
    local layout = CompileNativeLayout(definition, background, fill, recharge, charged)
    local style = { background = background, fill = fill, recharge = recharge,
        charged = charged, layout = layout,
        width = layout.fill.width, height = layout.fill.height,
        shadow = shapes[definition.shape] }
    nativeCache[key] = style
    return style
end

function Points:GetShape(name) return shapes[name] or shapes.circle end

function Points:ConfigureCell(frame, cell, index)
    local config = frame.gui2ResourceDisplayConfig or {}
    local points = config.mode == "dots"
    local native = points and self:GetNativeStyle(config.nativePointStyle, index) or nil
    local shape = points and not config.nativePointStyle and self:GetShape(config.pointShape) or shapes.circle
    cell.gui2ResourcePointNative = native
    cell.gui2ResourcePointShape = shape
    if cell.mask then
        cell.mask:SetTexture(shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
    end
    local background = native and native.background
    cell.background:SetTexture(background and background.texture or WHITE)
    cell.background:SetTexCoord(background and background.textureU0 or 0, background and background.textureU1 or 1,
        background and background.textureV0 or 0, background and background.textureV1 or 1)
    if native then cell.background:SetVertexColor(1, 1, 1, 1) end
    local shadow = native and native.shadow or shape
    cell.gui2ResourcePointShadowMask, cell.gui2ResourcePointShadowFill = shadow.inverse, shadow.mask
    for _, key in ipairs({ "statusBar", "rechargeBar", "thresholdLow", "thresholdReset", "thresholdHigh" }) do
        local bar = cell[key]
        bar.gui2ResourceNativePoint = native ~= nil
        bar.gui2ResourcePointStyle = native and (key == "rechargeBar" and native.recharge
            or key == "thresholdHigh" and native.charged or native.fill) or nil
    end
end

local function LayoutNativeArt(region, anchor, size, art)
    region:ClearAllPoints()
    region:SetPoint("CENTER", anchor, "CENTER", 0, size * art.y)
    region:SetSize(size * art.width, size * art.height)
end

function Points:LayoutCellArt(cell)
    local native = cell.gui2ResourcePointNative
    local size = math.min(cell.gui2ResourceShadowWidth, cell.gui2ResourceShadowHeight)
    if native then
        LayoutNativeArt(cell.background, cell.host, size, native.layout.background)
    else
        cell.background:ClearAllPoints()
        cell.background:SetAllPoints(cell.host)
    end
    for _, key in ipairs({ "statusBar", "rechargeBar", "thresholdLow", "thresholdReset", "thresholdHigh" }) do
        local bar = cell[key]
        if native then
            local art = key == "rechargeBar" and native.layout.recharge
                or key == "thresholdHigh" and native.layout.charged or native.layout.fill
            LayoutNativeArt(bar, cell.host, size, art)
        else
            bar:ClearAllPoints()
            bar:SetAllPoints(cell.host)
        end
    end
end

function Points:LayoutBorder(cell, thickness, r, g, b, a)
    if cell.gui2ResourcePointNative then cell.border:Hide(); return end
    local shape = cell.gui2ResourcePointShape or shapes.circle
    cell.border:SetTexture(shape.borders[math.max(1, math.min(4, math.floor(thickness + .5)))])
    cell.border:SetVertexColor(r, g, b, a)
    cell.border:SetShown(thickness > 0)
end

-- The Aura application's native driver is wider than one point. Keep its
-- geometry as the visibility gate; render the complete glyph inside that gate.
function Points:CreateFilteredMaterial(frame, driver, clip, cell)
    local native = cell and cell.gui2ResourcePointNative
    if not native then return end
    local texture = driver:GetStatusBarTexture()
    texture:SetAlpha(0)
    local gate = GUI:CreateFrame(driver, { mouse = false, background = false, border = false })
    gate:SetFrameLevel(driver:GetFrameLevel())
    gate:SetPoint("TOPLEFT", texture, "TOPLEFT", 0, 0)
    gate:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT", 0, 0)
    gate:SetClipsChildren(true)
    local material = CreateFrame("StatusBar", nil, gate)
    material:SetFrameLevel(driver:GetFrameLevel())
    material:SetMinMaxValues(0, 1)
    material:SetValue(1)
    LayoutNativeArt(material, clip, math.min(cell.gui2ResourceShadowWidth, cell.gui2ResourceShadowHeight), native.layout.fill)
    GUI:ApplyNativeStatusBarStyle(material, native.fill, "horizontal", "forward", true)
    material:SetStatusBarColor(1, 1, 1, 1)
    material:Show()
    driver.gui2ResourcePointMaterial = material
end

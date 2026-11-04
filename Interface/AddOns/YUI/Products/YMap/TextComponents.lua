local YUI = _G.YUI
local YMap = YUI and YUI.YMap
if not YMap then return end

-- Shared only by the four minimap text components; no runtime driver is owned here.
local Text = {}
YMap.TextComponents = Text
local GUI2 = YUI.GUI2
local Style = GUI2 and GUI2.FontStyle
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

local function FontFlags(original, config)
    local flags = (not config.outline or config.outline == "inherit") and original or FLAGS[config.outline]
    if config.monochrome == nil then return flags or "" end
    local monochrome = config.monochrome == true
        or config.monochrome == "inherit" and (original or ""):upper():find("MONOCHROME", 1, true) ~= nil
    local values = {}
    for token in (flags or ""):gmatch("[^,%s]+") do
        if token:upper() ~= "MONOCHROME" then values[#values+1] = token end
    end
    if monochrome then values[#values+1] = "MONOCHROME" end
    return table.concat(values, ",")
end

local function ShadowEnabled(original, config)
    if type(config.fontShadow) == "boolean" then return config.fontShadow end
    if config.fontShadow ~= "inherit" then
        if config.outline == "shadow" or config.outline == "outlineShadow" then return true end
        if config.shadow == "on" then return true end
        if config.shadow == "off" then return false end
    end
    local color, offset = original.SetShadowColor or {}, original.SetShadowOffset or {}
    return (color[4] or 0) > 0 and ((offset[1] or 0) ~= 0 or (offset[2] or 0) ~= 0)
end

function Text:Apply(object, config, size, color)
    if not object or not config then return false end
    local state = Capture(object)
    local original = state.original.SetFont
    local font = object.gui2ColorKey and GUI2.GetFont and GUI2:GetFont("font.family.body") or original[1]
    if config.font and config.font ~= "inherit" then
        if config.font:find("\\", 1, true) or config.font:find("/", 1, true) then font = config.font
        elseif LSM then font = LSM:Fetch("font", config.font, true) or font end
    end
    size = size or config.fontSize
    if not size or size == 0 then size = original[2] end
    if state.flags == nil or state.outline ~= config.outline or state.monochrome ~= config.monochrome then
        state.flags = FontFlags(original[3], config)
        state.outline, state.monochrome = config.outline, config.monochrome
    end
    local flags = state.flags
    if font and size then Write(object, state, "SetFont", font, size, flags or "") end
    local base = state.original.SetTextColor
    local r,g,b,a = base[1],base[2],base[3],base[4]
    if object.gui2ColorKey and GUI2.GetColor then r,g,b,a = GUI2:GetColor(object.gui2ColorKey) end
    -- A false override leaves the base color neutral for text with inline value colors.
    if config.fontColor and Style and color ~= false then
        r,g,b,a = Style.ColorRGBA(config.fontColor)
    elseif config.customColor and color ~= false then
        color = color or config.color
        if color then r,g,b,a = color[1],color[2],color[3],color[4] end
    end
    if r then Write(object, state, "SetTextColor", r,g,b,a or 1) end
    local combinedShadow = config.outline == "shadow" or config.outline == "outlineShadow"
    if type(config.fontShadow) == "boolean" then
        Write(object, state, "SetShadowColor", 0,0,0,config.fontShadow and 1 or 0)
        Write(object, state, "SetShadowOffset", config.fontShadow and 1 or 0,config.fontShadow and -1 or 0)
    elseif combinedShadow and config.fontShadow ~= "inherit" then
        Write(object, state, "SetShadowColor", 0,0,0,1)
        Write(object, state, "SetShadowOffset", 1,-1)
    elseif config.fontShadow == "inherit" or config.shadow == "inherit" or config.shadow == nil then
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

-- Read the existing view or its original style without creating a view or normalizing DB.
local function NativeStyle(key)
    local owner, metrics = YMap.Minimap or {}, YMap.MetricsWidget
    local object = key == "clock" and _G.TimeManagerClockTicker
        or key == "zoneName" and owner.zoneLabel or key == "coordinates" and owner.coordinateText
        or key == "metrics" and metrics and metrics.buttons and metrics.buttons[1] and metrics.buttons[1].text
    local original = object and states[object] and states[object].original or {
        SetFont = {Read(object, "GetFont")}, SetTextColor = {Read(object, "GetTextColor")},
        SetShadowColor = {Read(object, "GetShadowColor")}, SetShadowOffset = {Read(object, "GetShadowOffset")},
    }
    local font, color = original.SetFont, original.SetTextColor
    local themed = key ~= "clock"
    return original, themed and GUI2.GetFont and GUI2:GetFont("font.family.body") or font[1] or STANDARD_TEXT_FONT,
        font[2] or (key == "clock" and 12 or 11),
        themed and GUI2.GetColor and {GUI2:GetColor(object and object.gui2ColorKey
            or key == "zoneName" and "color.text.heading" or "color.text.primary")}
            or color[1] and Style.Copy(color) or {1,1,1,1}
end

if Style then
    local fields = {font={"font"}, size={"fontSize"}, outline={"outline"},
        shadow={"shadow","fontShadow"}, monochrome={"monochrome"}, color={"customColor","color","fontColor"}}
    Style:Register("ymap", function()
        local profile = YMap.GetProfile and YMap:GetProfile()
        local db = profile and profile[YMap.STORAGE_KEY] or not profile and YMap.db
        local appearance = db and db.minimap and db.minimap.squareAppearance
        if not appearance then return end
        local originals, targets = {}, {}
        local group = {label=YMap:T("product.title", "Map"), targets={}}
        group.current = function()
            local current = YMap.GetProfile and YMap:GetProfile()
            local root = current and current[YMap.STORAGE_KEY] or not current and YMap.db
            if current ~= profile or root ~= db or not root.minimap or root.minimap.squareAppearance ~= appearance then return false end
            for key, config in pairs(originals) do if appearance[key] ~= config then return false end end
            return true
        end
        local function Values(key, config, size)
            local original, font, nativeSize = NativeStyle(key)
            local value = Style.Decode(FontFlags(original.SetFont[3], config), ShadowEnabled(original, config))
            value.font = config.font and config.font ~= "inherit" and Style.FontPath(config.font, font) or font
            value.size = size and size > 0 and size or nativeSize
            if key ~= "metrics" then
                value.color = config.fontColor and Style.Copy(config.fontColor)
                    or config.customColor and Style.Copy(config.color) or nil
            end
            return value
        end
        local function Refresh()
            -- An inactive map returns false from Refresh; its saved settings are still editable.
            if YMap.RefreshTextStyle then YMap:RefreshTextStyle() else YMap:Refresh("font-style") end
            return true
        end
        group.snapshot = function(key)
            local config, snapshot = appearance[key], {}
            for attribute, names in pairs(fields) do
                if key~="metrics" or attribute~="color" then
                    for _, name in ipairs(names) do snapshot[name] = Style.Copy(config[name]) end
                end
            end
            if key == "zoneName" then snapshot.fontSize = appearance.zoneNameFontSize end
            return snapshot
        end
        local function RestoreAttribute(key, source, attribute)
            for _, name in ipairs(fields[attribute]) do
                if key == "zoneName" and name == "fontSize" then appearance.zoneNameFontSize = source[name]
                else appearance[key][name] = Style.Copy(source[name]) end
            end
        end
        group.restore = function(snapshots, attributes)
            if not group.current() then return false, "stale" end
            for key in pairs(snapshots) do if not targets[key] then return false, "stale" end end
            for key, snapshot in pairs(snapshots) do
                for attribute in pairs(fields) do
                    if targets[key].capabilities[attribute] and (not attributes or attributes[attribute]) then RestoreAttribute(key, snapshot, attribute) end
                end
            end
            return Refresh()
        end
        group.apply = function(changes)
            if not group.current() then return false, "stale" end
            for key, patch in pairs(changes) do
                if not targets[key] then return false, "stale" end
                if next(patch.values or {}) then
                    local attributes={}
                    for attribute in pairs(patch.values) do attributes[attribute]=true end
                    local ok, code = Style.Validate(targets[key], patch.values, attributes)
                    if not ok then return false, code end
                end
            end
            for key, patch in pairs(changes) do
                local config, values, reset = appearance[key], patch.values or {}, patch.reset or {}
                if (values.outline or reset.outline) and config.monochrome == nil then
                    local original = NativeStyle(key)
                    config.monochrome = Style.Decode(FontFlags(original.SetFont[3], config)).monochrome
                end
                -- Changing the outline must not switch off an old combined shadow preset.
                if (values.outline or reset.outline) and config.fontShadow == nil
                    and (config.outline == "shadow" or config.outline == "outlineShadow") then config.fontShadow = true end
                for attribute, value in pairs(values) do
                    if attribute == "font" then config.font = value
                    elseif attribute == "size" then
                        if key == "zoneName" then appearance.zoneNameFontSize=value else config.fontSize=value end
                    elseif attribute == "outline" then config.outline = value == "NONE" and "none" or value == "OUTLINE" and "outline" or "thick"
                    elseif attribute == "shadow" then config.fontShadow = value
                    elseif attribute == "monochrome" then config.monochrome = value
                    elseif attribute == "color" then
                        config.customColor = not value.mode or value.mode == "custom"
                        config.fontColor = value.mode == "class" and Style.Copy(value) or nil
                        if config.customColor then config.color=Style.Copy(value) end
                    end
                end
                local defaults = YMap.Defaults.minimap.squareAppearance
                for attribute in pairs(reset) do
                    if attribute == "shadow" then config.fontShadow="inherit"; config.shadow="inherit"
                    elseif attribute == "monochrome" then config.monochrome="inherit"
                    elseif attribute == "size" and key == "zoneName" then appearance.zoneNameFontSize=defaults.zoneNameFontSize
                    elseif fields[attribute] then RestoreAttribute(key, defaults[key], attribute) end
                end
            end
            return Refresh()
        end
        for _, key in ipairs(ORDER) do
            if type(appearance[key]) == "table" then
                originals[key] = appearance[key]
                local target = {id=key, label=YMap:T("settings.minimap.square_element."..key, key),
                    capabilities={font=true,size=true,outline=true,shadow=true,monochrome=true,color=key~="metrics"},
                    colorModes={state=true,class=true}, minSize=8,maxSize=24,
                    fontOptionsPosition="last",
                    fontOptions=function()
                        local _, font = NativeStyle(key)
                        return {{text=YMap:T("settings.minimap.text_inherit", "Inherit"),value="inherit",fontPath=font}}
                    end,
                    read=function() return Values(key, appearance[key], key=="zoneName" and appearance.zoneNameFontSize or appearance[key].fontSize) end,
                    parent=function(attribute)
                        if attribute=="color" then return {mode="state"} end
                        local defaults=YMap.Defaults.minimap.squareAppearance
                        return Values(key, defaults[key], key=="zoneName" and defaults.zoneNameFontSize or defaults[key].fontSize)[attribute]
                    end,
                }
                if key ~= "metrics" then target.colorInfo=function(mode)
                    local config=appearance[key]
                    mode=mode or (config.fontColor and "class" or config.customColor and "custom" or "state")
                    local _,_,_,nativeColor=NativeStyle(key)
                    return {mode=mode,color=mode=="state" and nativeColor or mode=="class"
                        and {Style.ColorRGBA(config.fontColor or {mode="class",alpha=1})} or Style.Copy(config.color)}
                end end
                targets[key]=target; group.targets[#group.targets+1]=target
            end
        end
        return group
    end)
end

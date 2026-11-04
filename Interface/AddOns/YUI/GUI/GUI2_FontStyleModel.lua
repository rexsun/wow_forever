-- Explicit font-style participants; enumeration never constructs settings or views.
local YUI = _G.YUI
if not (YUI and YUI.GUI2) then return end
local Style = { providers = {}, attributes = { "font", "size", "outline", "shadow", "monochrome", "color" } }
YUI.GUI2.FontStyle = Style

function Style.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Style.Copy(item) end
    return copy
end
function Style.Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Style.Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
function Style.Decode(value, shadow, monochrome)
    value = type(value) == "string" and value:upper() or value == true and "OUTLINE" or "NONE"
    return {
        outline = value:find("THICK", 1, true) and "THICKOUTLINE"
            or value:find("OUTLINE", 1, true) and "OUTLINE" or "NONE",
        shadow = shadow == true or value:find("SHADOW", 1, true) ~= nil,
        monochrome = monochrome == true or value:find("MONOCHROME", 1, true) ~= nil,
    }
end
function Style.Flags(value)
    local outline = value.outline ~= "NONE" and value.outline or ""
    if value.monochrome then return outline ~= "" and (outline .. ",MONOCHROME") or "MONOCHROME" end
    return outline
end
-- A false return alone is not enough to discard a font that is already active.
-- Keep this on the appearance/preview path, never on a text update or timer.
function Style.TryFont(text, path, size, flags)
    local ok, result = pcall(text.SetFont, text, path, size, flags)
    if not ok then return false, tostring(result) end
    if result ~= false then return true end
    if text.GetFont then
        local read, actual, actualSize, actualFlags = pcall(text.GetFont, text)
        local function FontPath(value)
            return type(value) == "string" and value:gsub("/", "\\"):lower() or value
        end
        local function FontFlags(value)
            value = (value or ""):upper():gsub("%s", "")
            return value:gsub("MONOCHROME", ""):gsub(",", ""), value:find("MONOCHROME", 1, true) ~= nil
        end
        local requestedOutline, requestedMono = FontFlags(flags)
        local actualOutline, actualMono = FontFlags(actualFlags)
        if read and FontPath(actual) == FontPath(path) and actualSize == size
            and actualOutline == requestedOutline and actualMono == requestedMono then return true end
    end
    return false, "SetFont returned false"
end
function Style:Register(id, capture)
    self.providers[id] = capture
end
-- Config-backed participants share transactions, not rendering or configuration ownership.
-- get() must only read the current store; refresh() remains the business owner's entry.
function Style.ComponentConfig(product, key)
    local profile = YUI.DB and YUI.DB:GetProfile(product)
    local store = profile and profile.Components
    local value = type(store)=="table" and store[key]
    if type(value)~="table" and profile and type(profile.YBox)=="table" then value=profile.YBox[key] end
    return value, profile
end
function Style.FontPath(value, fallback)
    if type(value) == "string" and (value:find("\\", 1, true) or value:find("/", 1, true)) then return value end
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    return media and media:Fetch("font", value, true) or fallback or STANDARD_TEXT_FONT
end
function Style.EncodeEffect(value, format)
    local base = value.outline == "THICKOUTLINE" and "thick" or value.outline == "OUTLINE" and "outline" or "none"
    if format == "stats" then
        local result = base == "thick" and "THICK_OUTLINE" or base == "outline" and "OUTLINE" or "NONE"
        return value.shadow and (base == "none" and "SHADOW" or result.."_SHADOW") or result
    end
    if not value.shadow then return format == "flags" and (base == "none" and "" or value.outline) or base end
    if base == "none" then return format == "flags" and "SHADOW" or "shadow" end
    if format == "camel" then return base .. "Shadow" end
    if format == "flags" then return (base == "thick" and "THICKOUTLINE" or "OUTLINE") .. "_SHADOW" end
    return base .. "_shadow"
end
local MODULE_COLOR = { mode = "state" }
function Style.ConfigValue(def, source, key, context)
    local field = def.fields[key]
    local raw = field and source[field]
    if raw == nil and field then raw = def.defaults[field] end
    if raw == nil and def.inherit then raw = def.inherit(key, context or source) end
    if raw == nil and def.styleDefaults then raw = def.styleDefaults[key] end
    if type(raw) == "function" then raw = raw() end
    if key == "font" then return def.fontPath and def.fontPath(raw) or Style.FontPath(raw) end
    if key == "monochrome" and raw == nil then return false end
    return raw
end
-- New attributes stay absent in old profiles; only an explicit edit stores them.
function Style.FullConfig(def, prefix, options)
    options = options or {}
    for _, key in ipairs({"font","outline","shadow","monochrome","color"}) do
        if not def.fields[key] and not (def.effect and (key == "outline" or key == "shadow")) then
            def.fields[key] = prefix .. key:sub(1,1):upper() .. key:sub(2)
        end
    end
    def.styleDefaults = {font=options.font or function() return YUI.GUI2:GetFont("font.family.body") end,
        outline=options.outline or "OUTLINE",shadow=options.shadow == true,monochrome=false,color=MODULE_COLOR}
    def.colorModes = {state=true,class=true}
    def.moduleColor = options.color
    def.dynamicColor, def.colorHint = options.dynamicColor, options.colorHint
    def.shadowAlpha = options.shadowAlpha or 0.9
    return def
end
local playerClass, playerClassColor
function Style.ColorRGBA(value, fallback)
    if value and value.mode == "class" then
        local unit = YUI.API and YUI.API.Unit
        local token = unit and unit.GetClassToken and unit.GetClassToken("player")
        if token and (token ~= playerClass or not playerClassColor) then
            playerClass,playerClassColor = token,unit.GetClassColor(token)
        end
        local color = playerClassColor
        return color and color.r or 1, color and color.g or 1, color and color.b or 1, value.alpha or 1
    end
    local color = value and (not value.mode or value.mode=="custom") and value or fallback
    if type(color) == "string" then return YUI.GUI2:GetColor(color) end
    color = color or {}
    return color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1
end
function Style.ConfigColor(def, db, fallback)
    return Style.ColorRGBA(Style.ConfigValue(def, db, "color"), fallback)
end
-- No allocations or font writes on unchanged appearances. Business code owns
-- state colors, text updates and layout; this cache owns only font rendering.
function Style.ApplyConfigFont(text, def, db, size)
    if not text then return end
    local font = Style.ConfigValue(def,db,"font")
    size = size or Style.ConfigValue(def,db,"size")
    local outline = Style.ConfigValue(def,db,"outline")
    local shadow = Style.ConfigValue(def,db,"shadow")
    local mono = Style.ConfigValue(def,db,"monochrome")
    local cache = text.yuiConfigFont
    if cache and cache.font==font and cache.size==size and cache.outline==outline and cache.shadow==shadow and cache.monochrome==mono then return end
    cache = cache or {}; text.yuiConfigFont = cache
    cache.font,cache.size,cache.outline,cache.shadow,cache.monochrome = font,size,outline,shadow,mono
    if not Style.TryFont(text,font,size,Style.Flags(cache)) then
        local fallback = Style.ConfigValue(def,def.defaults,"font",db) or STANDARD_TEXT_FONT
        Style.TryFont(text,fallback,size,Style.Flags(cache))
    end
    text:SetShadowColor(0,0,0,shadow and def.shadowAlpha or 0)
    text:SetShadowOffset(shadow and 1 or 0,shadow and -1 or 0)
end
function Style:RegisterConfig(id, spec)
    self:Register(id, function()
        local db, identity = spec.get()
        if type(db) ~= "table" then return end
        local group = { targets = {}, targetsByKey = {}, label = type(spec.label) == "function" and spec.label() or spec.label }
        group.current = function() local current, token = spec.get(); return current == db and token == identity end
        local definitions, owned = {}, {}
        local function Read(def, source, context)
            local value = def.effect and Style.Decode(source[def.effect] or def.defaults[def.effect]) or {}
            for key, field in pairs(def.fields) do
                local raw = Style.ConfigValue(def, source, key, context)
                value[key] = Style.Copy(raw)
            end
            return value
        end
        for _, def in ipairs(spec.targets) do
            if not def.available or def.available(db) then
                definitions[def.id], owned[def.id] = def, {}
                local capabilities = {}
                for key, field in pairs(def.fields) do capabilities[key] = true; owned[def.id][field] = key end
                for key, fields in pairs(def.aliases or {}) do
                    for _, field in ipairs(fields) do owned[def.id][field] = key end
                end
                if def.effect then
                    capabilities.outline, capabilities.shadow = true, true
                    owned[def.id][def.effect] = "effect"
                end
                group.targets[#group.targets + 1] = { id = def.id,
                    label = type(def.label) == "function" and def.label() or def.label,
                    capabilities = capabilities, minSize = def.minSize or 8, maxSize = def.maxSize or 48,
                    hasAlpha = def.hasAlpha, fontOptions = def.fontOptions, colorModes = def.colorModes,
                    position = def.position and def.position(db, group.current) or nil,
                    read = function() return Read(def, db) end,
                    parent = function(key) return Read(def, def.defaults, db)[key] end,
                    colorInfo = def.colorInfo and function(mode) return def.colorInfo(db,mode) end or def.colorModes and function(mode)
                        local value = Style.ConfigValue(def,db,"color")
                        if mode=="state" then value=MODULE_COLOR
                        elseif mode=="class" then value={mode="class",alpha=value.alpha or value[4] or 1} end
                        if value.mode == "state" and def.dynamicColor then
                            return {mode="state",dynamic=true,
                                hint=type(def.colorHint)=="function" and def.colorHint(db) or def.colorHint}
                        end
                        local fallback = type(def.moduleColor)=="function" and def.moduleColor(db) or def.moduleColor
                        return {mode=value.mode or "custom",color={Style.ColorRGBA(value,fallback)}}
                    end or nil }
                group.targetsByKey[id..":"..def.id] = group.targets[#group.targets]
            end
        end
        group.snapshot = function(id)
            local copy = {}
            for field in pairs(owned[id]) do copy[field] = Style.Copy(db[field]) end
            return copy
        end
        group.apply = function(changes)
            if not group.current() then return false, "stale" end
            for targetId in pairs(changes) do if not definitions[targetId] then return false,"missing" end end
            -- Shared defaults precede role overrides when both are selected.
            for _, def in ipairs(spec.targets) do
                local patch = changes[def.id]
                if patch then
                    local values = patch.values or {}
                    local current = Read(def, db)
                    for key, value in pairs(values) do current[key] = Style.Copy(value) end
                    for key in pairs(patch.reset or {}) do current[key] = Read(def, def.defaults, db)[key] end
                    for key, field in pairs(def.fields) do
                        if patch.reset and patch.reset[key] then
                            db[field] = Style.Copy(def.defaults[field])
                        elseif values[key] ~= nil then
                            db[field] = Style.Copy(current[key])
                        end
                    end
                    for key, fields in pairs(def.aliases or {}) do
                        for _, field in ipairs(fields) do
                            if patch.reset and patch.reset[key] then db[field]=Style.Copy(def.defaults[field])
                            elseif values[key]~=nil then db[field]=Style.Copy(values[key]) end
                        end
                    end
                    if def.effect and (values.outline ~= nil or values.shadow ~= nil
                        or patch.reset and (patch.reset.outline or patch.reset.shadow)) then
                        db[def.effect] = Style.EncodeEffect(current, def.format)
                    end
                end
            end
            spec.refresh(db)
            return true
        end
        group.restore = function(snapshots, attributes)
            if not group.current() then return false, "stale" end
            for targetId, snapshot in pairs(snapshots) do
                for field, attribute in pairs(owned[targetId]) do
                    if not attributes or attributes[attribute] or attribute == "effect" and (attributes.outline or attributes.shadow) then
                        db[field] = Style.Copy(snapshot[field])
                    end
                end
            end
            spec.refresh(db)
            return true
        end
        return group
    end)
end
function Style:Capture()
    local catalog = { entries = {}, groups = {} }
    local ids = {}
    for id in pairs(self.providers) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local group = self.providers[id]()
        if group then
            catalog.groups[#catalog.groups + 1] = group
            for _, target in ipairs(group.targets) do
                target.key = id .. ":" .. target.id
                target.group = group
                catalog.entries[#catalog.entries + 1] = target
            end
        end
    end
    return catalog
end
function Style:Find(catalog, key)
    for _, target in ipairs(catalog.entries) do if target.key == key then return target end end
end
function Style.Validate(target, values, attributes)
    local count = 0
    for _, key in ipairs(Style.attributes) do
        if attributes[key] then
            count = count + 1
            if not target.capabilities[key] or values[key] == nil then return false, "unsupported" end
            local value = values[key]
            if key == "size" and (type(value) ~= "number" or value ~= value or value < target.minSize or value > target.maxSize) then
                return false, "size_range"
            elseif key == "font" and (type(value) ~= "string" or value == "") then return false, "invalid"
            elseif key == "outline" and value ~= "NONE" and value ~= "OUTLINE" and value ~= "THICKOUTLINE" then return false, "invalid"
            elseif (key == "shadow" or key == "monochrome") and type(value) ~= "boolean" then return false, "invalid"
            elseif key == "color" then
                if type(value) ~= "table" then return false, "invalid" end
                local mode = value.mode or "custom"
                if mode ~= "custom" then
                    if mode ~= "class" and mode ~= "state" then return false, "invalid" end
                    if not (target.colorModes and target.colorModes[mode]) then return false, "color_mode" end
                    if mode == "class" and (type(value.alpha) ~= "number" or value.alpha ~= value.alpha or value.alpha < 0 or value.alpha > 1) then
                        return false, "invalid"
                    end
                else
                    for index = 1, 4 do
                        local part = value[index]
                        if type(part) ~= "number" or part ~= part or part < 0 or part > 1 then return false, "invalid" end
                    end
                    if target.hasAlpha == false and value[4] ~= 1 then return false, "unsupported" end
                end
            end
        end
    end
    return count > 0, "empty"
end
-- Preflight is reviewable and all-or-nothing. Invalid targets stay outside writes.
function Style:Plan(catalog, values, attributes, selection)
    local plan = { groups = {}, rejected = {}, count = 0 }
    local byGroup = {}
    for _, target in ipairs(catalog.entries) do
        if selection[target.key] then
            local valid, reason = self.Validate(target, values, attributes)
            if not target.group.current() then valid, reason = false, "stale" end
            if valid then
                local batch = byGroup[target.group]
                if not batch then
                    batch = { context = target.group, changes = {}, before = {} }
                    byGroup[target.group] = batch
                    plan.groups[#plan.groups + 1] = batch
                end
                local patch = {}
                for key in pairs(attributes) do if attributes[key] then patch[key] = self.Copy(values[key]) end end
                batch.changes[target.id] = { values = patch }
                batch.before[target.id] = target.group.snapshot(target.id)
                plan.count = plan.count + 1
            else plan.rejected[#plan.rejected + 1] = { target = target, reason = reason } end
        end
    end
    return plan
end
local function RestoreApplied(applied)
    local succeeded = true
    for index = #applied, 1, -1 do
        local batch = applied[index]
        local ok, result = pcall(batch.context.restore, batch.before)
        if not ok or result == false then succeeded = false end
    end
    return succeeded
end
function Style:Execute(plan)
    if plan.count == 0 then return false, "empty" end
    for _, batch in ipairs(plan.groups) do
        if not batch.context.current() then return false, "stale" end
        for id, before in pairs(batch.before) do
            if not self.Equal(before, batch.context.snapshot(id)) then return false, "stale" end
        end
    end
    local applied = {}
    for _, batch in ipairs(plan.groups) do
        local ok, result, reason = pcall(batch.context.apply, batch.changes)
        if not ok or result == false then
            local restored, result = pcall(batch.context.restore, batch.before)
            local previous = RestoreApplied(applied)
            return false, restored and result ~= false and previous and (reason or "failed") or "rollback_failed"
        end
        applied[#applied + 1] = batch
        batch.after = {}
        for id in pairs(batch.before) do batch.after[id] = batch.context.snapshot(id) end
    end
    self.undo = plan
    return true
end
function Style:CanUndo()
    local plan = self.undo
    if not plan then return false, "empty" end
    for _, batch in ipairs(plan.groups) do
        if not batch.context.current() then return false, "stale" end
        for id, after in pairs(batch.after) do
            if not self.Equal(after, batch.context.snapshot(id)) then return false, "stale" end
        end
    end
    return true
end
function Style:Undo()
    local valid, reason = self:CanUndo()
    if not valid then return false, reason end
    local plan = self.undo
    if not RestoreApplied(plan.groups) then return false, "rollback_failed" end
    self.undo = nil
    return true
end
return Style

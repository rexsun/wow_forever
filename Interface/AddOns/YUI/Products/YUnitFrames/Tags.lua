local YUI = _G.YUI
local UF = YUI and YUI.YUnitFrames
if not UF then return end
local Security = YUI.API.Security
local secret = Security.IsSecretValue
local unpack = unpack or table.unpack
local Tags = { registry = {}, order = {} }
UF.Tags = Tags

local function Display(value)
    if secret(value) then return value end
    if value == nil then return "" end
    return value
end
local function NumberText(value, short)
    if short and AbbreviateLargeNumbers then return AbbreviateLargeNumbers(value) end
    return Display(value)
end
local function Name(unit, length)
    local name = UnitName(unit)
    if secret(name) then return name end
    if not name then return "" end
    if length and string.utf8sub then return string.utf8sub(name, 1, length) end
    return name
end
local function Status(unit)
    local dead, ghost, connected = UnitIsDead(unit), UnitIsGhost(unit), UnitIsConnected(unit)
    if not secret(connected) and connected == false then return UF:T("status.offline") end
    if not secret(ghost) and ghost then return UF:T("status.ghost") end
    if not secret(dead) and dead then return UF:T("status.dead") end
    return ""
end
local function ClassColor(unit)
    local _, class = UnitClass(unit)
    if secret(class) then return "|cffffffff" end
    return UF:ColorCode("class", class)
end
function Tags:Register(id, category, events, getter, preview)
    if type(id) ~= "string" or not id:match("^[%w:_-]+$") or type(getter) ~= "function" or type(events) ~= "string" then return false end
    if self.registry[id] then return false end
    self.registry[id] = { id = id, category = category, events = events, get = getter, preview = preview or "" }
    self.order[#self.order + 1] = id
    return true
end

Tags:Register("name", "name", "identity", function(unit) return Name(unit) end, "Astra")
Tags:Register("name:short", "name", "identity", function(unit) return Name(unit, 10) end, "Astra")
Tags:Register("name:medium", "name", "identity", function(unit) return Name(unit, 15) end, "Astra")
Tags:Register("target", "name", "identity target", function(unit) return Name(unit .. "target") end, "Nova")
Tags:Register("realm", "name", "identity", function(unit) local _, realm = UnitName(unit); return Display(realm) end, "Azeroth")
Tags:Register("level", "name", "identity", function(unit)
    local value = UnitLevel(unit)
    if secret(value) then return value end
    return value and value > 0 and value or "??"
end, "90")
Tags:Register("classification", "name", "identity", function(unit)
    local value = UnitClassification(unit)
    if secret(value) then return "" end
    if value == "elite" or value == "rareelite" then return "+" end
    if value == "rare" then return UF:T("status.rare") end
    if value == "worldboss" then return UF:T("unit.boss") end
    return ""
end, "+")
Tags:Register("class", "name", "identity", function(unit) local name = UnitClass(unit); return Display(name) end, "Mage")
Tags:Register("curhp", "health", "health", function(unit) return Display(UF.Backend.Values.health(unit)) end, function() return math.floor(UF.PreviewData.health * 10000) end)
Tags:Register("maxhp", "health", "health", function(unit) return Display(UF.Backend.Values.maxHealth(unit)) end, "1000000")
Tags:Register("perhp", "health", "health", function(unit) return UF.Backend:Percent(unit, false) end, function() return string.format("%.0f", UF.PreviewData.health) end)
Tags:Register("missinghp", "health", "health", function(unit) return Display(UF.Backend.Values.missingHealth(unit)) end, function() return math.floor((100 - UF.PreviewData.health) * 10000) end)
Tags:Register("absorbs", "health", "absorb", function(unit) return Display(UF.Backend.Values.absorbs(unit)) end, function() return UF.PreviewData.absorbs and math.floor(UF.PreviewData.absorbAmount * 10000) or 0 end)
Tags:Register("healabsorbs", "health", "absorb", function(unit) return Display(UF.Backend.Values.healAbsorbs(unit)) end, function() return UF.PreviewData.healabsorbs and math.floor(UF.PreviewData.healAbsorbAmount * 10000) or 0 end)
Tags:Register("curpp", "power", "power", function(unit) return Display(UF.Backend.Values.power(unit)) end, "70")
Tags:Register("maxpp", "power", "power", function(unit) return Display(UF.Backend.Values.maxPower(unit)) end, "100")
Tags:Register("perpp", "power", "power", function(unit) return UF.Backend:Percent(unit, true) end, "70")
Tags:Register("missingpp", "power", "power", function(unit) return Display(UF.Backend.Values.missingPower(unit)) end, "30")
Tags:Register("status", "status", "identity health", Status, "")
Tags:Register("dead", "status", "health", function(unit)
    local value = UnitIsDead(unit)
    return not secret(value) and value and UF:T("status.dead") or ""
end, "")
Tags:Register("offline", "status", "identity", function(unit)
    local value = UnitIsConnected(unit)
    return not secret(value) and value == false and UF:T("status.offline") or ""
end, "")
Tags:Register("afk", "status", "identity", function(unit)
    local value = UnitIsAFK(unit)
    return not secret(value) and value and "AFK" or ""
end, "")
local function PreviewClassColor() return UF:ColorCode("class", "MAGE") end
Tags:Register("classcolor", "color", "identity", ClassColor, PreviewClassColor)
Tags:Register("namecolor", "color", "identity", ClassColor, PreviewClassColor)
Tags:Register("powercolor", "color", "power", function(unit)
    local _, token = UnitPowerType(unit)
    if secret(token) then return "|cffffffff" end
    return UF:ColorCode("power", token)
end, function() return UF:ColorCode("power", "MANA") end)

local aliases = {
    ["health:current"] = "curhp", ["health:max"] = "maxhp", ["health:percent"] = "perhp",
    ["power:current"] = "curpp", ["power:max"] = "maxpp", ["power:percent"] = "perpp",
}
for id, source in pairs(aliases) do
    local descriptor = Tags.registry[source]
    Tags:Register(id, descriptor.category, descriptor.events, descriptor.get, descriptor.preview)
end
local numeric = {
    { "health:current:shortvalue", UF.Backend.Values.health, "health", function() return NumberText(UF.PreviewData.health * 10000, true) end },
    { "health:max:shortvalue", UF.Backend.Values.maxHealth, "health", "1M" },
    { "power:current:shortvalue", UF.Backend.Values.power, "power", "70" },
    { "power:max:shortvalue", UF.Backend.Values.maxPower, "power", "100" },
    { "absorbs:shortvalue", UF.Backend.Values.absorbs, "absorb", function() return NumberText(UF.PreviewData.absorbs and UF.PreviewData.absorbAmount * 10000 or 0, true) end },
    { "healabsorbs:shortvalue", UF.Backend.Values.healAbsorbs, "absorb", function() return NumberText(UF.PreviewData.healabsorbs and UF.PreviewData.healAbsorbAmount * 10000 or 0, true) end },
}
for _, item in ipairs(numeric) do
    local getter = item[2]
    Tags:Register(item[1], item[3], item[3], function(unit) return NumberText(getter(unit), true) end, item[4])
end

function Tags:Compile(text)
    text = type(text) == "string" and text:sub(1, 512) or ""
    local compiled = { entries = {}, values = {}, events = {}, errors = {}, format = "", count = 0 }
    local chunks, position = {}, 1
    while position <= #text do
        local first, last, id = text:find("%[([^%[%]]+)%]", position)
        if not first then chunks[#chunks + 1] = text:sub(position):gsub("%%", "%%%%"); break end
        chunks[#chunks + 1] = text:sub(position, first - 1):gsub("%%", "%%%%")
        local descriptor = self.registry[id]
        if descriptor and compiled.count < 24 then
            compiled.count = compiled.count + 1
            compiled.entries[compiled.count] = descriptor
            chunks[#chunks + 1] = "%s"
            for event in descriptor.events:gmatch("%S+") do compiled.events[event] = true end
        else
            compiled.errors[#compiled.errors + 1] = id
            chunks[#chunks + 1] = text:sub(first, last):gsub("%%", "%%%%")
        end
        position = last + 1
    end
    compiled.format = table.concat(chunks)
    return compiled
end

function Tags:Paint(fontString, compiled, unit, preview, domain)
    if domain and not compiled.events[domain] then return end
    for i = 1, compiled.count do
        local descriptor = compiled.entries[i]
        if preview then compiled.values[i] = type(descriptor.preview) == "function" and descriptor.preview() or descriptor.preview
        else compiled.values[i] = Display(descriptor.get(unit)) end
    end
    -- Secret results go directly to the display sink, never through Lua concatenation or equality.
    fontString:SetFormattedText(compiled.format, unpack(compiled.values, 1, compiled.count))
    UF.Stats.textWrites = UF.Stats.textWrites + 1
end

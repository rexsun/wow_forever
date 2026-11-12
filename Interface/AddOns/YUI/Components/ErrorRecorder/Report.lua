local addonName = ...
local YUI = _G.YUI
if addonName ~= "YUI" or not YUI then return end
local Report = {}
YUI.ErrorReport = Report
local L = YUI.Locale:Get("ErrorRecorder")
local titles, icons = {}, {}
local sources = setmetatable({}, { __mode = "k" })
local function Plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")) end
local function Escape(text) return (text:gsub("|", "||")) end
function Report:Literal(text) return Escape(text) end
local function Native(id) return id:match("^Blizzard_") ~= nil end
local function ShortPath(text)
    return (text:gsub("[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]", ""))
end
function Report:Title(id)
    if not titles[id] then
        local ok, _, title = pcall(C_AddOns.GetAddOnInfo, id)
        if ok and type(title) == "string" then
            local text = Plain(title):match("^%s*(.-)%s*$")
            if text ~= "" then titles[id] = text end
        end
    end
    return titles[id] or id
end
function Report:Icon(id)
    if icons[id] ~= nil then return icons[id] or "" end
    local known = titles[id] ~= nil
    local function Metadata(key)
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, id, key)
        return ok and type(value) == "string" and value or nil
    end
    local texture, atlas = Metadata("IconTexture"), nil
    if not texture or texture == "" then atlas = Metadata("IconAtlas") end
    if (not texture or texture == "") and (not atlas or atlas == "") then
        local ok, _, title = pcall(C_AddOns.GetAddOnInfo, id)
        if ok and type(title) == "string" then
            known = true
            texture = title:match("|T([^:|]+)")
            if not texture then atlas = title:match("|A:?([^:|]+)") end
        end
    end
    local value = texture and texture ~= "" and texture or atlas
    local markup
    if value and value ~= "" and not value:find("[|:%c]") then
        markup = texture and texture ~= "" and ("|T" .. value .. ":16:16:0:0|t ") or ("|A:" .. value .. ":16:16|a ")
    end
    -- Missing inventory entries must not accumulate cache keys from arbitrary error paths.
    if markup or known then icons[id] = markup or false end
    return markup or ""
end
function Report:AddonLabel(id, text)
    return self:Icon(id) .. Escape(text or self:ShortTitle(id))
end
function Report:ShortTitle(id)
    if id == "YUI" then return "YUI" end
    return (self:Title(id):gsub("%s+·%s+.*$", ""))
end
function Report:Source(record)
    local cached = sources[record]
    if cached and cached.message == record.message and cached.stack == record.stack then return cached end
    local message = record.message:gsub('^%[string .-%]:%d+:%s*', "")
    local ids = _G.YUI_ErrorCollector:RelatedAddons(message, record.stack)
    local result = { message = record.message, stack = record.stack, ids = {}, related = {} }
    for _, id in ipairs(ids) do
        if not Native(id) then
            result.ids[#result.ids + 1] = id
            local title = self:ShortTitle(id)
            result.related[#result.related + 1] = title == id and id or title .. " (" .. id .. ")"
        end
    end
    if #result.ids > 0 then
        result.kind, result.title = "addon", self:ShortTitle(result.ids[1])
    elseif record.message:find('[string ', 1, true)
        and (record.stack:find("SlashCommands.lua", 1, true) or record.stack:find("ChatFrameEditBox.lua", 1, true)) then
        result.kind, result.title = "chat", L["source.chat"]
    elseif ids[1] and Native(ids[1]) and record.message:find(ids[1], 1, true) then
        result.kind, result.title = "native", L["source.native"]
    else result.kind, result.title = "unknown", L["unknown"] end
    sources[record] = result
    return result
end
function Report:Related(record)
    local result = {}
    -- Paths identify involvement, never assign blame to the first addon in a stack.
    for _, id in ipairs(_G.YUI_ErrorCollector:RelatedAddons(record.message, record.stack)) do
        local title = self:Title(id)
        result[#result + 1] = title == id and id or title .. " (" .. id .. ")"
    end
    return result
end
function Report:ListLabel(record)
    local source = self:Source(record)
    return source.ids[1] and self:AddonLabel(source.ids[1], source.title) or Escape(source.title)
end
function Report:Heading(record)
    local source, labels = self:Source(record), {}
    for i, id in ipairs(source.ids) do labels[i] = self:AddonLabel(id, source.related[i]) end
    return #labels > 0 and L["related"]:format(table.concat(labels, ", ")) or Escape(L["source.label"]:format(source.title))
end
function Report:Summary(record)
    local message = Plain(record.message:match("^[^\r\n]+") or "")
    -- Strip only a leading location. Quoted code inside the actual message stays intact.
    message = message:gsub('^%[string .-%]:%d+:%s*', "")
    message = message:gsub("^[^:%s]+%.lua%]?:%d+:%s*", "")
    return (message:gsub("%s+", " "))
end
local function Newer(a, b)
    local aSequence, bSequence = a.sequence or 0, b.sequence or 0
    if aSequence ~= bSequence then return aSequence > bSequence end
    return (a.last or 0) >= (b.last or 0)
end
function Report:LatestIndex(records)
    local latest = 1
    for i = 2, #records do
        if Newer(records[i], records[latest]) then latest = i end
    end
    return latest
end
function Report:Ordered(records)
    local ordered = {}
    for i, record in ipairs(records) do ordered[i] = { record = record, index = i } end
    table.sort(ordered, function(a, b)
        if (a.record.sequence or 0) == (b.record.sequence or 0) and (a.record.last or 0) == (b.record.last or 0) then
            return a.index > b.index
        end
        return Newer(a.record, b.record)
    end)
    for i, item in ipairs(ordered) do ordered[i] = item.record end
    return ordered
end
function Report:Recent(records, limit)
    local recent = {}
    for index, record in ipairs(records) do
        local position = #recent + 1
        for i, item in ipairs(recent) do
            if Newer(record, item.record) then position = i; break end
        end
        if position <= limit then
            table.insert(recent, position, { record = record, index = index })
            if #recent > limit then table.remove(recent) end
        end
    end
    return recent
end
function Report:Count(record)
    return (record.approximate and "≥" or "") .. tostring(record.count)
end
function Report:Meta(record, session)
    return L["meta"]:format(session.build or "", self:Count(record), date("%H:%M:%S", record.last or 0))
end
local function Color(key, text)
    local r, g, b = YUI.GUI:GetColor(key)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5), text)
end
function Report:Tint(key, text) return Color(key, Escape(text)) end
function Report:Code(text)
    text = Escape(ShortPath(text))
    text = text:gsub("([^%s%[%]\"':<>]+%.lua)(%]?):(%d+)", function(file, bracket, line)
        return Color("color.text.heading", file) .. bracket .. ":" .. Color("color.state.success", line)
    end)
    return (text:gsub("(in function )'([^']+)'", function(prefix, name)
        return prefix .. "'" .. Color("color.accent.primary", name) .. "'"
    end))
end
function Report:TooltipLine(record, number)
    local collector, source = _G.YUI_ErrorCollector, self:Source(record)
    local location = not record.message:match('^%[string ') and record.message:match("^([^%s]+%.lua%]?:%d+):%s*")
    if location and #location > 160 then location = nil end
    local heading = location and self:Code(location) or self:Tint("color.tooltip.heading", collector:SafeText(source.title, 96))
    local summary = collector:SafeText(self:Summary(record), 240)
    return self:Tint("color.tooltip.secondary", number .. ". ") .. heading .. ": "
        .. self:Tint("color.tooltip.body", summary) .. self:Tint("color.tooltip.secondary", " (×" .. self:Count(record) .. ")")
end
function Report:Readable(record)
    local message = record.message:gsub('^%[string .-%]:%d+:%s*', "")
    local parts = { self:Code(message) }
    if record.stack ~= "" then parts[#parts + 1] = Color("color.text.secondary", L["stack"]) .. "\n" .. self:Code(record.stack) end
    if record.locals ~= "" then parts[#parts + 1] = Color("color.text.secondary", L["locals"]) .. "\n" .. Escape(record.locals) end
    return table.concat(parts, "\n\n")
end
function Report:ReadableSession(session, records)
    local parts = {}
    for i, record in ipairs(records or session.records) do
        parts[i] = Color("color.text.secondary", tostring(i) .. ". " .. self:Meta(record, session)) .. "\n" .. self:Readable(record)
    end
    return table.concat(parts, "\n\n────────────────────\n\n")
end
function Report:Format(collector, record, session)
    local source = self:Source(record)
    local versions, labels = {}, {}
    for line in (record.metadata or ""):gmatch("[^\r\n]+") do
        local id, version = line:match("^([^:]+):%s*(.-)%s*$")
        if id and version ~= "" then versions[id] = Plain(version) end
    end
    for i, id in ipairs(source.ids) do
        labels[i] = source.related[i] .. (versions[id] and " " .. versions[id] or "")
    end
    local heading = #labels > 0 and table.concat(labels, ", ") or source.title
    local header = heading .. " · ×" .. self:Count(record) .. "\nWoW " .. (session.build or "")
        .. " · " .. date("%m-%d %H:%M:%S", record.last or 0)
    return collector:FormatRecord(record, session, header)
end

local Format = {}
local aliases = {location="location", zone="zone", subzone="subzone", shard="shard",
    ["位置"]="location", ["区域"]="zone", ["區域"]="zone",
    ["小区域"]="subzone", ["小區域"]="subzone", ["位面"]="shard"}
local closing = {["["]="]", ["("]=")"}
Format.templates = {location="{location}", full_location="{zone} / {subzone}",
    location_shard="{location} [{shard}]", full_location_shard="{zone} / {subzone} [{shard}]"}

-- Compile only when the format changes. Bracket groups containing an empty field
-- disappear as a unit; separators immediately before empty fields disappear too.
function Format.Compile(template)
    if type(template) ~= "string" or #template > 512 or not template:find("%S") or template:find("[%c]") then return nil, "invalid" end
    local pos, length = 1, #template
    local function parse(stop, depth)
        if depth > 8 then return nil, "invalid" end
        local nodes, literal = {}, ""
        local function flush()
            if literal ~= "" then nodes[#nodes+1] = {literal=literal:gsub("|", "||")}; literal="" end
        end
        while pos <= length do
            local char = template:sub(pos, pos)
            if char == stop then flush(); pos=pos+1; return nodes end
            if char == "]" or char == ")" or char == "}" then return nil, "brackets" end
            if char == "{" then
                flush()
                local finish = template:find("}", pos+1, true)
                if not finish then return nil, "brackets" end
                local token = template:sub(pos+1, finish-1)
                local key = aliases[token]
                if not key then return nil, "field", token end
                nodes[#nodes+1] = {key=key}
                pos=finish+1
            elseif closing[char] then
                flush(); pos=pos+1
                local children, reason, field = parse(closing[char], depth+1)
                if not children then return nil, reason, field end
                nodes[#nodes+1] = {children=children, open=char, close=closing[char]}
            else literal=literal..char; pos=pos+1 end
        end
        if stop then return nil, "brackets" end
        flush()
        return nodes
    end
    return parse(nil, 0)
end

local function TrimLeadingSeparator(text)
    text = text:gsub("^%s*[/|%-:,]+%s*", "")
    text = text:gsub("^%s*·%s*", "")
    return text
end

local function Render(nodes, values, grouped)
    local out, pending, hasValue, lastPresent = {}, "", false, true
    for _, node in ipairs(nodes) do
        if node.literal then pending=pending..node.literal
        else
            local value
            if node.key then value=values[node.key] or ""
            else
                local body = Render(node.children, values, true)
                value=body and body ~= "" and (node.open..body..node.close) or ""
            end
            if value == "" then
                if grouped then return nil end
                pending, lastPresent = "", false
            else
                out[#out+1]=(hasValue and pending or TrimLeadingSeparator(pending))..value
                pending, hasValue, lastPresent = "", true, true
            end
        end
    end
    if lastPresent then out[#out+1]=pending end
    return table.concat(out):match("^%s*(.-)%s*$")
end

function Format.Render(nodes, values) return Render(nodes, values, false) end

-- The measurement callback owns its FontString. UTF-8 boundaries keep a clipped
-- location readable while reserving the complete shard suffix in combined presets.
function Format.FitLocation(location, suffix, budget, measure, fontString)
    local text = location..suffix
    if measure(fontString, text) <= budget then return text end
    if measure(fontString, "…"..suffix) > budget then return suffix:match("^%s*(.-)%s*$") end
    local ends, offset = {}, 0
    for char in location:gmatch("[\1-\127\194-\244][\128-\191]*") do
        offset=offset+#char; ends[#ends+1]=offset
    end
    local low, high = 0, #ends
    while low < high do
        local middle = math.ceil((low+high)/2)
        if measure(fontString, location:sub(1, ends[middle]).."…"..suffix) <= budget then low=middle
        else high=middle-1 end
    end
    return location:sub(1, ends[low] or 0).."…"..suffix
end

local YBar = _G.YUI and _G.YUI.YBar
if YBar then YBar.LocationFormat=Format end
return Format

local YUI = _G.YUI
if not (YUI.IsRetail or YUI.IsForever) then return end
local Unit = YUI.API.Unit

-- Product-loaded scalar adapters also work when another addon provided Core first.
local function ReadName(fn)
    if type(fn) ~= "function" then return "" end
    local value = fn()
    if issecretvalue and issecretvalue(value) then return "" end
    return type(value) == "string" and value or ""
end

function Unit.GetLocationNames()
    local zone, subzone = ReadName(GetZoneText), ReadName(GetSubZoneText)
    local location = subzone ~= "" and subzone or zone
    if location == "" then location = ReadName(GetMinimapZoneText) end
    if subzone == zone then subzone = "" end
    return zone, subzone, location
end

function Unit.GetShardReference(guid)
    if issecretvalue and issecretvalue(guid) then return nil, "restricted" end
    if type(guid) ~= "string" then return nil end
    local kind, server, instance, zone = guid:match("^(%a+)%-%d+%-(%d+)%-(%d+)%-(%d+)%-%d+%-%x+$")
    if kind ~= "Creature" then return nil end
    return zone, server, instance
end

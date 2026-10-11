local _
---@type string, private
local addonName, private = ...

--[[
    TrinketData registry / in-game version gate.

    Multiple trinket datasets ship at once (currently Live and PTR), each in
    Core/TrinketData/<channel>.lua calling private.RegisterTrinketData(...).
    We expose, as private.TrinketData, the dataset whose TOC interface is the
    highest that does not exceed the running client -- so a Live client gets
    Live data and a PTR client gets PTR data.  The generator supports further
    channels (classic/era/wrath/tbc); their datasets are generated and added to
    the .toc if this addon ever ships a flavor .toc for them.

    The client interface is select(4, GetBuildInfo()) -- the same source
    ProfileManager uses for toc_version (e.g. 120007 for 12.0.7).

    Consumers (Components/TrinketTracker.lua) read private.TrinketData.onUse /
    .proc / .stacks at runtime, so swapping the table reference here at load is safe.
    Load order (.toc): this file, then the per-channel datasets, then the
    components -- RegisterTrinketData exists before any dataset registers.
--]]

---@class trinket_dataset : table
---@field onUse table<number, number>
---@field proc table<number, table>
---@field interface number
---@field build string
---@field channel string

-- Preview channels (PTR) are prepared ahead of a patch. At cutover the client's
-- interface jumps to the PTR build's, so the PTR dataset is auto-selected. Once
-- the matching release dataset is regenerated at that same interface, it should
-- win the tie -- hence release beats preview at equal interface, independent of
-- .toc load order.
local PREVIEW_CHANNELS = { ptr = true }

---@type trinket_dataset
private.TrinketData = { onUse = {}, proc = {}, stacks = {} }

local clientInterface = tonumber((select(4, GetBuildInfo()))) or 0
local bestInterface = -1
local bestIsPreview = true

---True when a dataset with this interface/channel would replace the currently
---selected one. Each generated dataset file calls this BEFORE building its
---table and returns early when it is false, so a channel that cannot win never
---pays for its own construction -- the PTR set in particular ships alongside a
---release set at the same interface and always loses the tie, and its table is
---several hundred entries. Same comparison as RegisterTrinketData below, so the
---two cannot drift; the guard is an optimisation, never the selection rule.
---@param interface number  TOC interface of the dataset's build (e.g. 120007)
---@param channel string    "live" | "ptr" | ...
---@return boolean
function private.TrinketDataWouldWin(interface, channel)
    if interface > clientInterface then return false end
    local isPreview = PREVIEW_CHANNELS[channel] or false
    return interface > bestInterface
        or (interface == bestInterface and bestIsPreview and not isPreview)
end

---Register a per-channel trinket dataset. It becomes the active dataset if it
---best matches the running client: highest interface that does not exceed the
---client's, and on an interface tie a release channel beats a preview (PTR) one.
---@param interface number  TOC interface of the dataset's build (e.g. 120007)
---@param build string      full build string (e.g. "12.0.7.68256")
---@param channel string    "live" | "ptr" | "classic" | "era" | "wrath" | "tbc"
---@param data trinket_dataset
function private.RegisterTrinketData(interface, build, channel, data)
    data.interface = interface
    data.build = build
    data.channel = channel
    if not private.TrinketDataWouldWin(interface, channel) then return end
    bestInterface = interface
    bestIsPreview = PREVIEW_CHANNELS[channel] or false
    private.TrinketData = data
end

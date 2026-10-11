--[[
    ClientScope — one profile, one set of user-entered IDs per game client (#27).

    A spell or item ID the user typed on retail means nothing on MoP Classic or
    WoW Forever, and the reverse.  The collections holding such IDs therefore
    keep one copy per client inside the same profile.  Additional Frames are
    shared by every client; only the spell lists inside them are split, so a
    frame keeps its id, layout and anchors everywhere.  The running client's copy
    always sits at the ordinary key, so no reader knows this file exists; the
    other clients' copies are parked in `profile.by_client[client]`, and
    `profile.client_scope` names whose copy is at the ordinary keys.

    `Swap` runs whenever a profile becomes active (login, switch, copy, reset,
    full import).  A profile with no `client_scope` (every profile from before
    this file) is claimed as-is by the first client to load it.  A client with
    no parked copy starts empty: no cross-client merge.

    Exports carry the ordinary keys only, so an export holds the exporting
    client's copy and an import lands in the importing client's.

    Pull-style ID maps (icon_overrides, spell_alerts, cdm_category_overrides,
    and the per-spell maps on a component or frame) are not split: an entry for an ID the client lacks is simply never applied.
--]]

local _
---@type string, private
local addonName, private = ...

local interface = select(4, GetBuildInfo())
local major = math.floor(interface / 10000)
-- ponytail: by interface major; an unsupported family gets its own key.  Forever
-- (1.60) and Classic Era (1.15) share major 1 and are told apart by the minor.
local FAMILY = { [1] = "era", [2] = "tbc", [3] = "wrath", [5] = "mists" }
local CLIENT = interface >= 100000 and "retail" or (interface >= 16000 and interface < 20000) and "forever"
    or FAMILY[major] or tostring(major)

---@class client_scope
---@field CLIENT string  "retail" | "forever" | "mists" | "tbc" | "wrath" | "era"
---@field Swap fun(profile: table)  put the running client's copy at the ordinary keys
local ClientScope = {
    CLIENT = CLIENT,
}

-- Keys holding user-entered IDs, per entry of each map.  An Additional Frame
-- itself (type, layout, anchors) is shared by every client; only the spells
-- it holds are not.
local SCOPED = {
    components = { "custom_spells", "tracked_spells" },
    additional_frames = { "assigned_spells", "custom_spells" },
}

---Take the scoped collections out of a profile.
---@param p table
---@return table slice
local function extract(p)
    local slice = { aura_name_cache = p.aura_name_cache }
    for map, keys in pairs(SCOPED) do
        slice[map] = {}
        for name, entry in pairs(p[map] or {}) do
            local own = {}
            for _, key in ipairs(keys) do own[key] = entry[key] end
            if next(own) then slice[map][name] = own end
        end
    end
    return slice
end

---Put a slice in place; anything it lacks starts empty.  A key is only
---written where the entry has it, so no component or frame gains a key.
---@param p table
---@param slice table?
local function apply(p, slice)
    slice = slice or {}
    p.aura_name_cache = slice.aura_name_cache or {}
    for map, keys in pairs(SCOPED) do
        local saved = slice[map] or {}
        for name, entry in pairs(p[map] or {}) do
            local own = saved[name] or {}
            for _, key in ipairs(keys) do
                if entry[key] ~= nil or own[key] ~= nil then entry[key] = own[key] or {} end
            end
        end
    end
end

function ClientScope.Swap(p)
    local owner = p.client_scope
    local client = ClientScope.CLIENT
    if owner == client then return end
    if owner then
        p.by_client = p.by_client or {}
        local mine = p.by_client[client]
        p.by_client[client] = nil
        p.by_client[owner] = extract(p)
        apply(p, mine)
    end
    p.client_scope = client
end

private.ClientScope = ClientScope

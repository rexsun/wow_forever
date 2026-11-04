local YUI = _G.YUI
if not YUI or not YUI.API then return end

local API = YUI.API.AssistedCombat or {}
YUI.API.AssistedCombat = API
local Security = YUI.API.Security

local function IsSecret(value)
    if Security and Security.IsSecretValue then return Security.IsSecretValue(value) == true end
    if type(issecretvalue) == "function" then return issecretvalue(value) == true end
    return false
end

local function Public(value)
    if IsSecret(value) then return nil end
    return value
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return Public(value) end
end

local function SpellID(value)
    value = Public(value)
    if type(value) ~= "number" or value <= 0 or value >= math.huge
        or value ~= math.floor(value) then return nil end
    return value
end

-- Public scalar IDs only; no allocation or rotation calculation.
function API.GetSpellIdentities(value)
    if YUI.IsRetail ~= true then return nil end
    local id = SpellID(value)
    if not id then return nil end
    local spells = _G.C_Spell
    local base = spells and SpellID(Call(spells.GetBaseSpell, id)) or id
    local override = spells and SpellID(Call(spells.GetOverrideSpell, id)) or id
    return id, base or id, override or id
end

-- nil,true means an available provider currently has no recommendation.
-- Unavailable, restricted or failed calls return nil,false.
function API.GetHighlightSpell()
    if YUI.IsRetail ~= true then return nil, false end
    local assisted = _G.C_AssistedCombat
    local cvars = _G.C_CVar
    local getBool = cvars and cvars.GetCVarBool or _G.GetCVarBool
    if Call(getBool, "assistedCombatHighlight") ~= true
        or not assisted or Call(assisted.IsAvailable) ~= true then return nil, false end
    if type(assisted.GetNextCastSpell) ~= "function" then return nil, false end
    local ok, id = pcall(assisted.GetNextCastSpell, false)
    if not ok or IsSecret(id) then return nil, false end
    if id == nil then return nil, true end
    id = SpellID(id)
    return id, id ~= nil
end

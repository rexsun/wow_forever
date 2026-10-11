local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Recipes = {}
YAB.Recipes = Recipes

Recipes.DEFAULT = "default"
Recipes.DEFAULT_BUILTIN_ID = "classic-three-row"

local function GetConfigSets()
    return YAB.ConfigSets
end

local function ResolveId(id)
    if id == nil or id == "" or id == Recipes.DEFAULT then
        return Recipes.DEFAULT_BUILTIN_ID
    end
    return id
end

function Recipes:Get(id)
    local configSets = GetConfigSets()
    return configSets and configSets:GetBuiltin(ResolveId(id)) or nil
end

function Recipes:GetOptions()
    local configSets = GetConfigSets()
    local options = {}
    for _, builtin in ipairs(configSets and configSets:GetBuiltins() or {}) do
        options[#options + 1] = {
            text = builtin.title,
            value = builtin.id,
        }
    end
    return options
end

function Recipes:Snapshot()
    local configSets = GetConfigSets()
    if not configSets then return nil, "config-sets-unavailable" end
    return configSets:Capture(configSets.ScopeOrder, { source = "legacy-recipe" })
end

function Recipes:Apply(id, preview)
    if preview == true then
        return false, "live-preview-not-supported"
    end
    id = ResolveId(id)
    local configSets = GetConfigSets()
    local builtin = configSets and configSets:GetBuiltin(id)
    if not builtin then return false, "recipe-not-found" end

    local service = configSets:GetService()
    if service and type(service.Apply) == "function" then
        local applied, code, detail = service:Apply(
            configSets.PROVIDER_ID,
            { kind = "builtin", id = builtin.id },
            self,
            { source = "legacy-recipe" }
        )
        if not applied then return false, code, detail end
        return true, applied
    end
    return configSets:ApplyBuiltinDirect(builtin.id, { source = "legacy-recipe" })
end

function Recipes:RevertPreview()
    local configSets = GetConfigSets()
    if not configSets then return false, "config-sets-unavailable" end
    local service = configSets:GetService()
    if service and type(service.CanUndo) == "function" and type(service.Undo) == "function" then
        if not service:CanUndo(configSets.PROVIDER_ID, self) then
            return false, "nothing-to-undo"
        end
        local undone, code, detail = service:Undo(configSets.PROVIDER_ID, self)
        if not undone then return false, code, detail end
        return true, undone
    end
    return configSets:UndoDirect({ source = "legacy-recipe" })
end

Recipes.list = {}
for _, builtin in ipairs(GetConfigSets() and GetConfigSets():GetBuiltins() or {}) do
    Recipes.list[builtin.id] = builtin
end
Recipes.list[Recipes.DEFAULT] = Recipes:Get(Recipes.DEFAULT)
setmetatable(Recipes.list, {
    __index = function(_, id)
        return Recipes:Get(id)
    end,
})

local YUI = _G.YUI
if not (YUI and YUI.Settings) then return end
local A = {}
YUI.Settings.ConfigSetAssignments = A

local function Ref(id) return { kind = 'user', id = id } end
local function Valid(catalog, reference)
    return type(reference) == 'table' and reference.kind == 'user'
        and type(reference.id) == 'string' and type(catalog.items[reference.id]) == 'table'
end

function A:Snapshot(catalog)
    if type(catalog) ~= 'table' or type(catalog.items) ~= 'table'
        or type(catalog.assignments) ~= 'table' then return nil, 'invalid_storage' end
    local stored = catalog.assignments
    if not Valid(catalog, stored.default) or type(stored.bySpec) ~= 'table' then return nil, 'invalid_storage' end
    local result = { enabled = stored.enabled == true, default = Ref(stored.default.id),
        bySpec = {}, byReference = {}, enabledSets = {} }
    for id in pairs(catalog.items) do
        result.byReference['user:' .. id] = { mode = id == stored.default.id and 'default' or 'none',
            specKeys = {}, enabled = id == stored.default.id }
    end
    result.enabledSets[stored.default.id] = true
    for key, reference in pairs(stored.bySpec) do
        if type(key) ~= 'string' or not Valid(catalog, reference) then return nil, 'invalid_storage' end
        local talent = YUI.API and YUI.API.Talent
        local keys = talent and talent.GetConfigurationSpecializationKeys
            and talent.GetConfigurationSpecializationKeys(key) or { key }
        for _, target in ipairs(keys) do
            local assigned = stored.bySpec[target] or reference
            if not Valid(catalog, assigned) then return nil, 'invalid_storage' end
            result.bySpec[target] = Ref(assigned.id)
        end
    end
    for key, reference in pairs(result.bySpec) do
        result.enabledSets[reference.id] = true
        local assignment = result.byReference['user:' .. reference.id]
        assignment.enabled = true
        if assignment.mode ~= 'default' then assignment.mode = 'specs' end
        assignment.specKeys[#assignment.specKeys + 1] = key
    end
    for _, assignment in pairs(result.byReference) do table.sort(assignment.specKeys) end
    return result
end

function A:Prepare(catalog, reference, mode, specKeys, supportedKeys, currentKey)
    if type(catalog) ~= 'table' or type(catalog.items) ~= 'table' or not Valid(catalog, reference) then
        return nil, 'set_not_found'
    end
    if mode ~= 'default' and mode ~= 'specs' and mode ~= 'none' and mode ~= 'all' then
        return nil, 'invalid_assignment_mode'
    end
    local before, code = self:Snapshot(catalog)
    if not before then return nil, code end
    local selected = {}
    if mode == 'specs' then
        if type(specKeys) ~= 'table' then return nil, 'invalid_specialization' end
        for index, key in pairs(specKeys) do
            if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > #specKeys
                or type(key) ~= 'string' or not supportedKeys or not supportedKeys[key] then
                return nil, 'invalid_specialization'
            end
            selected[key] = true
        end
    end
    if mode == 'none' and reference.id == before.default.id then return nil, 'default_required' end
    local nextState = { enabled = true, default = Ref(before.default.id), bySpec = {} }
    for key, assigned in pairs(before.bySpec) do
        if mode ~= 'all' and not ((mode == 'none' or mode == 'specs') and assigned.id == reference.id) then
            nextState.bySpec[key] = Ref(assigned.id)
        end
    end
    if mode == 'default' or mode == 'all' then nextState.default = Ref(reference.id) end
    for key in pairs(selected) do nextState.bySpec[key] = Ref(reference.id) end
    local changed = not before.enabled or before.default.id ~= nextState.default.id
    for key, assigned in pairs(before.bySpec) do
        if not nextState.bySpec[key] or nextState.bySpec[key].id ~= assigned.id then changed = true end
    end
    for key, assigned in pairs(nextState.bySpec) do
        if not before.bySpec[key] or before.bySpec[key].id ~= assigned.id then changed = true end
    end
    local previousRoute = (currentKey and before.bySpec[currentKey] or before.default).id
    local nextRoute = (currentKey and nextState.bySpec[currentKey] or nextState.default).id
    local snapshot = assert(self:Snapshot({ items = catalog.items, assignments = nextState }))
    return nextState, { changed = changed, runtimeChanged = not before.enabled or previousRoute ~= nextRoute,
        assignmentSnapshot = snapshot, currentReference = Ref(nextRoute) }
end

return A

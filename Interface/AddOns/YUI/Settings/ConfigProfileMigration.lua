local _, YUI = ...
YUI = _G.YUI or YUI
if not (YUI and YUI.Settings) then return end

-- Pure staging: no database writes, provider calls or runtime activation.
local M = {}
YUI.Settings.ConfigProfileMigration = M
M.VERSION = 1
M.BASELINE = "v323.1"
M.STORAGE_KEY = "SettingsConfigSetsV2"
M.MARKER_KEY = "SettingsConfigSetsOwnershipMigration"
M.RECOVERY_KEY = "SettingsConfigSetsRecovery"
local preparedDatabases = setmetatable({}, { __mode = "k" })

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("cyclic-storage") end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do out[k] = Copy(v, seen) end
    seen[value] = nil
    return out
end

local function Id(ref)
    if type(ref) == "string" then return ref end
    if type(ref) == "table" and ref.kind == "user" then return ref.id end
end

local function Ordered(catalog)
    local result, seen, extra = {}, {}, {}
    for _, id in ipairs(catalog.order or {}) do
        if type(id) ~= "string" or not catalog.items[id] then error("invalid-order") end
        if not seen[id] then result[#result + 1], seen[id] = id, true end
    end
    for id in pairs(catalog.items) do
        if type(id) ~= "string" then error("invalid-set-id") end
        if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do result[#result + 1] = id end
    return result
end

local function Prepare(legacy, profileNames, owned)
    if type(legacy) ~= "table" or legacy.schemaVersion ~= 1
        or type(legacy.providers) ~= "table" then error("unsupported-storage") end
    if type(profileNames) ~= "table" then error("profiles-required") end
    local result = { version = M.VERSION, baseline = M.BASELINE, profiles = {}, recovery = {}, resolutions = {} }
    local seenProfiles = {}
    for _, name in ipairs(profileNames) do
        if type(name) ~= "string" or name == "" or seenProfiles[name] then
            error("invalid-profile")
        end
        seenProfiles[name] = true
        result.profiles[name] = owned and owned[name] and Copy(owned[name])
            or { schemaVersion = 2, providers = {} }
    end
    for providerId, catalog in pairs(legacy.providers) do
        if type(catalog) ~= "table" or type(catalog.items) ~= "table" then error("invalid-catalog") end
        local order, claimed, shadowed = Ordered(catalog), {}, false
        for _, name in ipairs(profileNames) do
            if result.profiles[name].providers[providerId] ~= nil then
                -- An imported/edited owned library is authoritative. Do not
                -- infer its routing from an older account-wide copy.
                shadowed = true
            else
                local byMode = (catalog.activeByConfigurationMode or {})[name] or {}
                local mode = (catalog.configurationModeByProfile or {})[name]
                local state = (catalog.specializationByProfile or {})[name]
                local active = Id((catalog.activeByProfile or {})[name])
                local refs, assignments = {}, {}
                local function Add(ref)
                    if ref == nil then return end
                    local id = Id(ref)
                    if not id or not catalog.items[id] then error("dangling-reference:" .. providerId) end
                    refs[id], claimed[id] = true, true
                    return id
                end
                Add(active)
                for _, ref in pairs(byMode) do Add(ref) end
                if state then
                    if type(state) ~= "table" then error("invalid-profile-state") end
                    Add((state.assignments or {}).default)
                    for _, ref in pairs((state.assignments or {}).bySpec or {}) do Add(ref) end
                    for id in pairs(state.enabledUserSets or {}) do Add(id) end
                    for id in pairs(state.disabledAssignments or {}) do Add(id) end
                end
                if mode ~= nil and mode ~= "unified" and mode ~= "specialization" then
                    error("unknown-mode")
                end
                if mode == nil and next(refs) and active == nil and next(byMode) == nil
                    and (providerId == "yhud" or providerId == "yactionbar") then
                    local stored = state and state.assignments
                    local default = stored and Id(stored.default)
                    local item = default and catalog.items[default]
                    -- v323.1 initializes these providers in specialization mode.
                    -- A complete persisted specialization state already supplies
                    -- its backing set; it cannot trigger YHUD's two-set bootstrap
                    -- switch to unified. Do not infer this for unknown providers or
                    -- incomplete states.
                    -- Routing may be disabled without changing the initialization
                    -- mode. Preserve that boolean below; never enable it here.
                    if stored and type(stored.enabled) == "boolean" and item
                        and item.configurationMode == "specialization"
                        and state.enabledUserSets and state.enabledUserSets[default] == true then
                        mode = "specialization"
                        result.resolutions[#result.resolutions + 1] = {
                            providerId = providerId, profileName = name,
                            code = "v323-specialization-bootstrap", defaultId = default,
                        }
                    end
                end
                local defaultId, routingEnabled = nil, true
                if mode == "unified" then
                    defaultId = Add(byMode.unified or active)
                    if not defaultId then error("missing-default") end
                elseif mode == "specialization" then
                    if not state or not state.assignments or type(state.assignments.enabled) ~= "boolean" then
                        error("unresolved-specialization-state")
                    end
                    local storedDefault = Id(state.assignments.default)
                    if storedDefault and catalog.items[storedDefault].configurationMode ~= "specialization" then
                        error("invalid-specialization-default")
                    end
                    routingEnabled = state.assignments.enabled
                    if routingEnabled then
                        for spec, ref in pairs(state.assignments.bySpec or {}) do
                            assignments[spec] = { kind = "user", id = Add(ref) }
                        end
                    end
                    if routingEnabled then defaultId = Add(state.assignments.default or active or byMode.specialization)
                    else defaultId = Add(active or byMode.specialization or state.assignments.default) end
                    if not defaultId then
                        for _, id in ipairs(order) do
                            for _, ref in pairs(assignments) do
                                if ref.id == id then defaultId = id; break end
                            end
                            if defaultId then break end
                        end
                    end
                    if not defaultId then error("missing-default") end
                elseif next(refs) then
                    -- An absent mode is not permission to activate an arbitrary library item.
                    error(string.format("unresolved-profile-mode [provider=%s, profile=%q]", providerId, name))
                end
                if next(refs) then
                    local target = {
                        schemaVersion = 2, nextId = catalog.nextId, items = {}, order = {},
                        userSetScopePolicyVersion = catalog.userSetScopePolicyVersion,
                        activeByProfile = { [name] = active or Id(byMode[mode]) or defaultId },
                        assignments = { enabled = routingEnabled, bySpec = assignments,
                            default = { kind = "user", id = defaultId } },
                    }
                    local names = {}
                    for _, id in ipairs(order) do
                        if refs[id] then
                            local item = Copy(catalog.items[id])
                            item.configurationMode = nil
                            local base = type(item.name) == "string" and item.name or id
                            local unique, suffix = base, 2
                            while names[unique] do unique = base .. " (" .. suffix .. ")"; suffix = suffix + 1 end
                            names[unique], item.name = true, unique
                            target.items[id], target.order[#target.order + 1] = item, id
                        end
                    end
                    result.profiles[name].providers[providerId] = target
                end
            end
        end
        local recovery = { items = {}, order = {} }
        for _, id in ipairs(order) do
            if shadowed or not claimed[id] then
                recovery.items[id] = Copy(catalog.items[id])
                recovery.order[#recovery.order + 1] = id
            end
        end
        if #recovery.order > 0 then result.recovery[providerId] = recovery end
    end
    return result
end

function M:Prepare(legacy, profileNames, owned)
    local ok, result = pcall(Prepare, legacy, profileNames, owned)
    if not ok then return nil, "migration-rejected", result end
    return result
end

function M:CopyProfileStore(store)
    if type(store) ~= "table" or store.schemaVersion ~= 2 or type(store.providers) ~= "table" then
        return nil, "invalid_storage"
    end
    local ok, result = pcall(Copy, store)
    if not ok then return nil, "invalid_storage" end
    return result
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function ValidCatalog(catalog)
    if type(catalog) ~= "table" or catalog.schemaVersion ~= 2
        or type(catalog.items) ~= "table" or type(catalog.order) ~= "table" then return false end
    local seen, count = {}, 0
    for index, id in pairs(catalog.order) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #catalog.order
            or type(id) ~= "string" or seen[id] or type(catalog.items[id]) ~= "table" then return false end
        seen[id], count = true, count + 1
    end
    if count ~= #catalog.order then return false end
    for id in pairs(catalog.items) do if not seen[id] then return false end end
    local function ValidReference(ref)
        return type(ref) == "table" and type(ref.id) == "string"
            and (ref.kind == "builtin" or (ref.kind == "user" and catalog.items[ref.id] ~= nil))
    end
    if catalog.assignments ~= nil then
        local assignments = catalog.assignments
        if type(assignments) ~= "table" or type(assignments.bySpec) ~= "table"
            or (assignments.enabled ~= nil and type(assignments.enabled) ~= "boolean")
            or not ValidReference(assignments.default) then return false end
        for key, ref in pairs(assignments.bySpec) do
            if type(key) ~= "string" or not ValidReference(ref) then return false end
        end
    end
    if catalog.activeByProfile ~= nil then
        if type(catalog.activeByProfile) ~= "table" then return false end
        for name, id in pairs(catalog.activeByProfile) do
            if type(name) ~= "string" or type(id) ~= "string" or not catalog.items[id] then return false end
        end
    end
    return true
end

local function MergeRecovery(previous, incoming)
    local merged = Copy(previous or {})
    for providerId, catalog in pairs(merged) do
        if type(providerId) ~= "string" or type(catalog) ~= "table"
            or type(catalog.items) ~= "table" then error("invalid-recovery") end
        Ordered(catalog)
    end
    for providerId, catalog in pairs(incoming) do
        local target = merged[providerId]
        if not target then
            merged[providerId] = catalog
        else
            local order = Ordered(target)
            for _, id in ipairs(catalog.order) do
                if target.items[id] == nil then
                    target.items[id] = catalog.items[id]
                    order[#order + 1] = id
                elseif not Same(target.items[id], catalog.items[id]) then
                    error("recovery-conflict:" .. providerId .. ":" .. id)
                end
            end
            target.order = order
        end
    end
    return merged
end

-- The Settings storage owner supplies AceDB's global and named profile tables.
-- Preparation never modifies those tables or the original v323 store.
function M:PrepareDatabase(global, profiles)
    if type(global) ~= "table" or type(profiles) ~= "table" then return nil, "invalid-database" end
    if global[self.MARKER_KEY] ~= nil then return nil, "migration-already-marked" end
    local previousRecovery = global[self.RECOVERY_KEY]
    if previousRecovery ~= nil and type(previousRecovery) ~= "table" then return nil, "invalid-recovery" end
    local names, identities, stores, owned = {}, {}, {}, {}
    for name, profile in pairs(profiles) do
        if type(name) ~= "string" or name == "" or type(profile) ~= "table" then return nil, "invalid-profile" end
        local original = profile[self.STORAGE_KEY]
        if original ~= nil then
            local copied, code = self:CopyProfileStore(original)
            if not copied then return nil, code, name end
            for providerId, catalog in pairs(copied.providers) do
                if type(providerId) ~= "string" or not ValidCatalog(catalog) then
                    return nil, "invalid_storage", { profileName = name, providerId = providerId }
                end
            end
            stores[name], owned[name] = { original = original, before = copied }, copied
        end
        names[#names + 1], identities[name] = name, profile
    end
    table.sort(names)
    local legacy = global.SettingsConfigSets
    -- Prepare clones owned stores again so provider validation cannot mutate
    -- these stale-check snapshots or the original catalogs retained on commit.
    local result, code, detail = self:Prepare(legacy, names, owned)
    if not result then return nil, code, detail end
    local merged, recovery = pcall(MergeRecovery, previousRecovery, result.recovery)
    if not merged then return nil, "migration-rejected", recovery end
    result.recovery = recovery
    local token = {}
    preparedDatabases[token] = {
        global = global, profiles = profiles, identities = identities, names = names,
        original = legacy, before = Copy(legacy), result = result,
        stores = stores, recovery = previousRecovery, recoveryBefore = Copy(previousRecovery),
    }
    return token, { profiles = #names, resolutions = Copy(result.resolutions), recovery = Copy(result.recovery) }
end

function M:DiscardDatabase(token)
    preparedDatabases[token] = nil
end

function M:ValidateDatabase(token, validator)
    local staged = preparedDatabases[token]
    if not staged or type(validator) ~= "function" then return nil, "invalid-migration-token" end
    for _, name in ipairs(staged.names) do
        for providerId, catalog in pairs(staged.result.profiles[name].providers) do
            if not ValidCatalog(catalog) then return nil, "invalid_storage" end
            local called, valid, code = pcall(validator, providerId, catalog)
            if not called or not valid then return nil, called and code or "migration-validation-failed" end
        end
    end
    return true
end

function M:CommitDatabase(token, hooks)
    local staged = preparedDatabases[token]
    if not staged then return nil, "invalid-migration-token" end
    hooks = hooks or {}
    local combat = YUI.API and YUI.API.Combat and YUI.API.Combat.InCombatLockdown or InCombatLockdown
    if type(combat) == "function" and combat() then return nil, "combat-lockdown" end
    local global, profiles = staged.global, staged.profiles
    if global.SettingsConfigSets ~= staged.original or not Same(staged.before, staged.original)
        or global[self.MARKER_KEY] ~= nil or global[self.RECOVERY_KEY] ~= staged.recovery
        or not Same(staged.recoveryBefore, staged.recovery) then return nil, "stale-migration" end
    local count = 0
    for name, profile in pairs(profiles) do
        count = count + 1
        local stored = staged.stores[name]
        if staged.identities[name] ~= profile or profile[self.STORAGE_KEY] ~= (stored and stored.original)
            or (stored and not Same(stored.before, stored.original)) then return nil, "stale-migration" end
    end
    if count ~= #staged.names then return nil, "stale-migration" end
    if hooks.apply and (type(hooks.apply) ~= "function" or type(hooks.restore) ~= "function") then
        return nil, "restore-hook-required"
    end
    local marker = { version = self.VERSION, baseline = self.BASELINE }
    for _, name in ipairs(staged.names) do
        local stored = staged.stores[name]
        if stored then
            local installed, providers, changed = {}, {}, false
            for key, value in pairs(stored.original) do installed[key] = value end
            for id, catalog in pairs(stored.original.providers) do providers[id] = catalog end
            for id, catalog in pairs(staged.result.profiles[name].providers) do
                if providers[id] == nil then providers[id], changed = catalog, true end
            end
            installed.providers = providers
            staged.identities[name][self.STORAGE_KEY] = changed and installed or stored.original
        else
            staged.identities[name][self.STORAGE_KEY] = staged.result.profiles[name]
        end
    end
    global[self.RECOVERY_KEY] = staged.result.recovery
    global[self.MARKER_KEY] = marker
    local applied, value = true, true
    if hooks.apply then applied, value = pcall(hooks.apply) end
    if not applied or value ~= true then
        for _, name in ipairs(staged.names) do
            local stored = staged.stores[name]
            staged.identities[name][self.STORAGE_KEY] = stored and stored.original or nil
        end
        global[self.RECOVERY_KEY], global[self.MARKER_KEY] = staged.recovery, nil
        local restored, restoredValue = pcall(hooks.restore)
        preparedDatabases[token] = nil
        return nil, "migration-apply-failed", { restored = restored and restoredValue == true }
    end
    preparedDatabases[token] = nil
    return true
end

return M

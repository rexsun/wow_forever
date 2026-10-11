local _, YUI = ...
YUI = YUI or _G.YUI
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

local function Prepare(legacy, profileNames)
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
        result.profiles[name] = { providers = {} }
    end
    for providerId, catalog in pairs(legacy.providers) do
        if type(catalog) ~= "table" or type(catalog.items) ~= "table" then error("invalid-catalog") end
        local order, claimed = Ordered(catalog), {}
        for _, name in ipairs(profileNames) do
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
        local recovery = { items = {}, order = {} }
        for _, id in ipairs(order) do
            if not claimed[id] then
                recovery.items[id] = Copy(catalog.items[id])
                recovery.order[#recovery.order + 1] = id
            end
        end
        if #recovery.order > 0 then result.recovery[providerId] = recovery end
    end
    return result
end

function M:Prepare(legacy, profileNames)
    local ok, result = pcall(Prepare, legacy, profileNames)
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

-- The Settings storage owner supplies AceDB's global and named profile tables.
-- Preparation never modifies those tables or the original v323 store.
function M:PrepareDatabase(global, profiles)
    if type(global) ~= "table" or type(profiles) ~= "table" then return nil, "invalid-database" end
    if global[self.MARKER_KEY] ~= nil then return nil, "migration-already-marked" end
    if global[self.RECOVERY_KEY] ~= nil then return nil, "recovery-already-exists" end
    local names, identities = {}, {}
    for name, profile in pairs(profiles) do
        if type(name) ~= "string" or name == "" or type(profile) ~= "table" then return nil, "invalid-profile" end
        if profile[self.STORAGE_KEY] ~= nil then return nil, "profile-storage-already-exists" end
        names[#names + 1], identities[name] = name, profile
    end
    table.sort(names)
    local legacy = global.SettingsConfigSets
    local result, code, detail = self:Prepare(legacy, names)
    if not result then return nil, code, detail end
    local token = {}
    preparedDatabases[token] = {
        global = global, profiles = profiles, identities = identities, names = names,
        original = legacy, before = Copy(legacy), result = result,
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
        or global[self.MARKER_KEY] ~= nil or global[self.RECOVERY_KEY] ~= nil then return nil, "stale-migration" end
    local count = 0
    for name, profile in pairs(profiles) do
        count = count + 1
        if staged.identities[name] ~= profile or profile[self.STORAGE_KEY] ~= nil then return nil, "stale-migration" end
    end
    if count ~= #staged.names then return nil, "stale-migration" end
    if hooks.apply and (type(hooks.apply) ~= "function" or type(hooks.restore) ~= "function") then
        return nil, "restore-hook-required"
    end
    local marker = { version = self.VERSION, baseline = self.BASELINE }
    for _, name in ipairs(staged.names) do
        staged.identities[name][self.STORAGE_KEY] = {
            schemaVersion = 2, providers = staged.result.profiles[name].providers,
        }
    end
    global[self.RECOVERY_KEY] = staged.result.recovery
    global[self.MARKER_KEY] = marker
    local applied, value = true, true
    if hooks.apply then applied, value = pcall(hooks.apply) end
    if not applied or value ~= true then
        for _, name in ipairs(staged.names) do staged.identities[name][self.STORAGE_KEY] = nil end
        global[self.RECOVERY_KEY], global[self.MARKER_KEY] = nil, nil
        local restored, restoredValue = pcall(hooks.restore)
        preparedDatabases[token] = nil
        return nil, "migration-apply-failed", { restored = restored and restoredValue == true }
    end
    preparedDatabases[token] = nil
    return true
end

return M

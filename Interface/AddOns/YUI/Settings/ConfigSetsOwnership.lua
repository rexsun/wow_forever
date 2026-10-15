local YUI = _G.YUI
local S = YUI and YUI.Settings
local Service = S and S.ConfigSets
local Migration = S and S.ConfigProfileMigration
if not (Service and Migration and S.ConfigSetAssignments and Service._ProfileOwnershipContext) then return end
local Context = Service._ProfileOwnershipContext
local Ownership = {}
local imports = setmetatable({}, { __mode = 'k' })
local additions = setmetatable({}, { __mode = 'k' })

local function Reference(id)
    return { kind = 'user', id = id }
end

local function Same(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end
    for key, value in pairs(left) do
        if not Same(value, right[key]) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function ConvertLegacyProfile(payload)
    local result = { kind = payload.kind, schema = 2, providers = {} }
    if type(payload.providers) ~= 'table' then return nil, 'invalid_payload' end
    for id, old in pairs(payload.providers) do
        if type(old) ~= 'table' or not Context.denseArray(old.sets)
            or (old.mode ~= 'unified' and old.mode ~= 'specialization')
            or type(old.specialization) ~= 'table' then return nil, 'invalid_payload', id end
        local spec = old.specialization
        local assignments = spec.assignments
        if type(assignments) ~= 'table' or type(assignments.enabled) ~= 'boolean'
            or type(assignments.bySpec) ~= 'table' or not Context.denseArray(spec.enabled) then
            return nil, 'invalid_payload', id
        end
        local modes, enabled = {}, {}
        for _, item in ipairs(old.sets) do
            if type(item) ~= 'table' or type(item.key) ~= 'string' or modes[item.key]
                or (item.configurationMode ~= 'unified' and item.configurationMode ~= 'specialization') then
                return nil, 'invalid_payload', id
            end
            modes[item.key] = item.configurationMode
        end
        if modes[old.unified] ~= 'unified' or modes[spec.active] ~= 'specialization'
            or modes[assignments.default] ~= 'specialization' then return nil, 'invalid_payload', id end
        for _, key in ipairs(spec.enabled) do
            if modes[key] ~= 'specialization' or enabled[key] then return nil, 'invalid_payload', id end
            enabled[key] = true
        end
        if not enabled[assignments.default] then return nil, 'invalid_payload', id end
        for _, key in pairs(assignments.bySpec) do
            if not enabled[key] then return nil, 'invalid_payload', id end
        end
        local active = old.mode == 'unified' and old.unified or spec.active
        local auto = old.mode == 'specialization' and assignments.enabled
        result.providers[id] = {
            sets = old.sets, active = active,
            assignments = { enabled = auto, default = auto and assignments.default or active,
                bySpec = auto and assignments.bySpec or {} },
        }
    end
    return result
end

-- Input has already passed the service's bounded portable-data clone.
function Ownership:PrepareProfileStateImport(productId, name, payload, providerIds, work)
    if payload.kind == 'YUI_CONFIG_SETS_PROFILE' and payload.schema == 1 then
        local converted, why, detail = ConvertLegacyProfile(payload)
        if not converted then return nil, why, detail end
        payload = converted
    end
    if payload.kind ~= 'YUI_CONFIG_SETS_PROFILE' or payload.schema ~= 2
        or type(payload.providers) ~= 'table' then return nil, 'invalid_payload' end
    local db, providers, code = Context.profileProviders(productId, providerIds)
    if not db then return nil, code end
    if not (db.sv and type(db.sv.profiles) == 'table') then return nil, 'profile_unavailable' end
    local allowed = {}
    for _, provider in ipairs(providers) do allowed[provider.id] = provider end
    local store = { schemaVersion = 2, providers = {} }
    local supported = Context.specKeys()
    for id, portable in pairs(payload.providers) do
        local provider = allowed[id]
        if not provider then return nil, 'provider_not_found', id end
        if type(portable) ~= 'table' or not Context.denseArray(portable.sets)
            or #portable.sets == 0 or type(portable.assignments) ~= 'table'
            or type(portable.assignments.enabled) ~= 'boolean'
            or type(portable.assignments.bySpec) ~= 'table' then return nil, 'invalid_payload', id end
        -- A profile import restores its complete library, including readable
        -- over-limit legacy libraries. New-set creation still enforces the cap.
        local catalog = { schemaVersion = 2, nextId = 1, items = {}, order = {}, activeByProfile = {} }
        local keys = {}
        for _, raw in ipairs(portable.sets) do
            local item, why, detail = Context.normalizeImportItem(provider, raw, nil, work)
            if not item then return nil, why, detail end
            if keys[item.key] then return nil, 'invalid_payload', 'duplicate_profile_set' end
            local unique
            unique, why = Context.uniqueName(provider, catalog, item.name)
            if not unique then return nil, why end
            local setId = Context.nextId(catalog)
            keys[item.key] = setId
            item.key, item.id, item.name = nil, setId, unique
            item.createdAt, item.updatedAt = Context.now(), Context.now()
            catalog.items[setId] = item
            catalog.order[#catalog.order + 1] = setId
        end
        local assignment = portable.assignments
        local default = type(assignment.default) == 'string' and keys[assignment.default]
        local active = type(portable.active) == 'string' and keys[portable.active]
        if not default or not active then return nil, 'invalid_payload', id end
        catalog.assignments = { enabled = assignment.enabled, default = Reference(default), bySpec = {} }
        for spec, key in pairs(assignment.bySpec) do
            if not supported[spec] or type(key) ~= 'string' or not keys[key] then
                return nil, 'invalid_specialization', id
            end
            catalog.assignments.bySpec[spec] = Reference(keys[key])
        end
        catalog.activeByProfile[name] = active
        if provider.userSetScopePolicy == 'all' then catalog.userSetScopePolicyVersion = 1 end
        store.providers[id] = catalog
    end
    local original = db.sv.profiles[name]
    local originalStore = original and original[Migration.STORAGE_KEY]
    local before
    if originalStore then
        before, code = Migration:CopyProfileStore(originalStore)
        if not before then return nil, code end
    end
    local token = {}
    imports[token] = { database = db, profiles = db.sv.profiles, name = name, store = store,
        original = original, originalStore = originalStore, before = before,
        sourceName = db.GetCurrentProfile and db:GetCurrentProfile() }
    return token
end

function Ownership:ValidateProfileStateImport(token)
    local staged = imports[token]
    if not staged or staged.committed or staged.restored then return nil, 'invalid_payload' end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil, 'in_combat' end
    local db = staged.database
    if db.sv.profiles ~= staged.profiles then return nil, 'stale_import' end
    local current = db.GetCurrentProfile and db:GetCurrentProfile()
    if current ~= staged.sourceName and current ~= staged.name then return nil, 'profile_changed' end
    local originalStore = staged.original and staged.original[Migration.STORAGE_KEY]
    local copy
    if originalStore then
        copy = Migration:CopyProfileStore(originalStore)
        if not copy then return nil, 'stale_import' end
    end
    for id in pairs(staged.store.providers) do
        local before = staged.before and staged.before.providers[id]
        local now = copy and copy.providers[id]
        if not Same(before, now) then return nil, 'stale_import' end
    end
    return true
end

function Ownership:CommitProfileStateImport(token)
    local valid, code = self:ValidateProfileStateImport(token)
    if not valid then return nil, code end
    local staged = imports[token]
    local db = staged.database
    local profile = staged.profiles[staged.name]
    if type(profile) ~= 'table' then return nil, 'profile_unavailable' end
    staged.profile, staged.previous = profile, profile[Migration.STORAGE_KEY]
    local previous = staged.previous
    if previous ~= nil and (type(previous) ~= 'table' or previous.schemaVersion ~= 2
        or type(previous.providers) ~= 'table') then return nil, 'invalid_storage' end
    local merged = { schemaVersion = 2, providers = {} }
    for id, catalog in pairs(previous and previous.providers or {}) do merged.providers[id] = catalog end
    for id, catalog in pairs(staged.store.providers) do
        merged.providers[id] = catalog
        Service.activeReferences[id], Service.transactions[id] = nil, nil
    end
    staged.installed = merged
    profile[Migration.STORAGE_KEY] = merged
    staged.committed, token.committed = true, true
    return true
end

function Ownership:RestoreProfileStateImport(token)
    local staged = imports[token]
    if not staged or not staged.committed or staged.restored then return nil, 'invalid_payload' end
    if staged.profiles[staged.name] ~= staged.profile
        or staged.profile[Migration.STORAGE_KEY] ~= staged.installed then return nil, 'stale_import' end
    staged.profile[Migration.STORAGE_KEY] = staged.previous
    staged.restored, token.restored = true, true
    for id in pairs(staged.store.providers) do
        Service.activeReferences[id], Service.transactions[id] = nil, nil
    end
    return true
end

function Ownership:GetStore(provider, create)
    local DB = YUI.DB
    if not (DB and DB.IsReady and DB:IsReady() and DB.GetAceDB and DB.GetProfile) then return nil, 'db_not_ready' end
    local db, profile = DB:GetAceDB(provider.productId), DB:GetProfile(provider.productId)
    if not db or type(profile) ~= 'table' or type(db.global) ~= 'table' then return nil, 'db_not_ready' end
    local global = db.global
    local marker = global[Migration.MARKER_KEY]
    if marker ~= nil and (type(marker) ~= 'table' or marker.version ~= Migration.VERSION) then return nil, 'invalid_storage' end
    if not marker and global.SettingsConfigSets ~= nil then
        if not (db.sv and type(db.sv.profiles) == 'table') then return nil, 'profile_unavailable' end
        local token, code, detail = Migration:PrepareDatabase(global, db.sv.profiles)
        if not token then return nil, code, detail end
        local valid, why = Migration:ValidateDatabase(token, function(id, catalog)
            local registered = Service.providers[id]
            -- A disabled product may register later. Preserve its structurally
            -- validated catalog; its own first read performs schema validation.
            if not registered then return true end
            return Context.validateCatalog(registered, catalog)
        end)
        if not valid then Migration:DiscardDatabase(token); return nil, why end
        local committed
        committed, code, detail = Migration:CommitDatabase(token)
        if not committed then Migration:DiscardDatabase(token); return nil, code, detail end
    end
    local store = profile[Migration.STORAGE_KEY]
    if store == nil and create then
        store = { schemaVersion = 2, providers = {} }
        profile[Migration.STORAGE_KEY] = store
    end
    if store == nil then return nil end
    if type(store) ~= 'table' or store.schemaVersion ~= 2 or type(store.providers) ~= 'table' then return nil, 'invalid_storage' end
    return store
end

function Ownership:IsReady(provider, catalog)
    local assignments = catalog.assignments
    if type(assignments) ~= 'table' or type(assignments.default) ~= 'table'
        or assignments.default.kind ~= 'user' or not catalog.items[assignments.default.id]
        or type(assignments.bySpec) ~= 'table' then return false end
    for key, reference in pairs(assignments.bySpec) do
        local talent = YUI.API and YUI.API.Talent
        if talent and talent.GetConfigurationSpecializationKeys then
            local keys = talent.GetConfigurationSpecializationKeys(key)
            if #keys ~= 1 or keys[1] ~= key then return false end
        end
        if type(key) ~= 'string' or type(reference) ~= 'table' or reference.kind ~= 'user'
            or not catalog.items[reference.id] then return false end
    end
    for _, id in ipairs(catalog.order) do
        local item = catalog.items[id]
        if not item or item.providerSchemaVersion ~= provider.schemaVersion then return false end
    end
    if provider.userSetScopePolicy == 'all' and catalog.userSetScopePolicyVersion ~= 1 then return false end
    return true
end

function Ownership:EnsureCatalog(provider, catalog)
    local created = {}
    if #catalog.order == 0 then
        local builtinId = provider.defaultAssignment and provider.defaultAssignment.id or provider.builtinOrder[1]
        local reference, item, detail = Context.createFromBuiltin(provider, catalog, builtinId)
        if not reference then return nil, item, detail end
        catalog.assignments = { enabled = true, default = reference, bySpec = {} }
        created[1] = item
    end
    local snapshot = S.ConfigSetAssignments:Snapshot(catalog)
    if not snapshot then return nil, 'invalid_storage' end
    catalog.assignments.bySpec = snapshot.bySpec
    local db, name, code = Context.profileIdentity(provider)
    if not db then return nil, code end
    local active = Service.activeReferences[provider.id]
    local reference = active and active.database == db and active.profileName == name and active.reference
    if not reference or not catalog.items[reference.id] then
        local persisted = catalog.activeByProfile and catalog.activeByProfile[name]
        reference = persisted and catalog.items[persisted] and { kind = 'user', id = persisted }
            or catalog.assignments.bySpec[Service:GetCurrentSpecializationKey()] or catalog.assignments.default
    end
    local copied = { kind = 'user', id = reference.id }
    Service.activeReferences[provider.id] = { database = db, profileName = name, reference = copied }
    Context.persistActive(provider, catalog, name, copied)
    return { reference = { kind = 'user', id = reference.id }, created = #created, createdItems = created }
end

function Ownership:CopyProfileState(productId, sourceName, targetName)
    if type(sourceName) ~= 'string' or type(targetName) ~= 'string' or sourceName == '' or targetName == '' then
        return nil, 'profile_unavailable'
    end
    local db = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(productId)
    local profiles = db and db.sv and db.sv.profiles
    local source = profiles and profiles[sourceName]
    if type(source) ~= 'table' then return nil, 'profile_unavailable' end
    if sourceName == targetName then return true end
    local store = source[Migration.STORAGE_KEY]
    if not store then
        -- An untouched profile has no owned library to copy. Its normal
        -- provider bootstrap will create the first set when selected.
        if db.global.SettingsConfigSets and not db.global[Migration.MARKER_KEY] then return nil, 'migration_required' end
        return true
    end
    local copied, code = Migration:CopyProfileStore(store)
    if not copied then return nil, code end
    for _, catalog in pairs(copied.providers) do
        local active = catalog.activeByProfile and catalog.activeByProfile[sourceName]
        catalog.activeByProfile = active and { [targetName] = active } or {}
    end
    local target = profiles[targetName]
    if target ~= nil and type(target) ~= 'table' then return nil, 'invalid_storage' end
    target = target or {}; profiles[targetName] = target
    target[Migration.STORAGE_KEY] = copied
    return true
end

function Ownership:ExportProfileState(productId, profileName, providerIds)
    local database, providers, code = Context.profileProviders(productId, providerIds)
    if not database then return nil, code end
    local current = database.GetCurrentProfile and database:GetCurrentProfile()
    profileName = profileName or current
    if not current or profileName ~= current then return nil, 'profile_not_active' end
    local result = { kind = 'YUI_CONFIG_SETS_PROFILE', schema = 2, providers = {} }
    for _, provider in ipairs(providers) do
        local ready, why, detail = Context.ensureExportCatalog(provider)
        if not ready then return nil, why, detail end
        local catalog
        catalog, why, detail = Context.getCatalog(provider, false)
        if not catalog then return nil, why, detail end
        local snapshot
        snapshot, why = S.ConfigSetAssignments:Snapshot(catalog)
        if not snapshot then return nil, why end
        local sets, keys = {}, {}
        -- Reserve sets belong to this profile just as assigned sets do.
        for _, id in ipairs(catalog.order) do
            local item
            item, why, detail = Context.exportItem(provider, catalog.items[id], id,
                'export_profile_state', { profileName = profileName, setId = id })
            if not item then return nil, why, detail end
            local key = 's' .. tostring(#sets + 1)
            keys[id] = key
            sets[#sets + 1] = {
                key = key, name = item.name, description = item.description,
                providerSchemaVersion = item.providerSchemaVersion,
                scopeIds = item.scopeIds, data = item.data,
            }
        end
        local default = keys[snapshot.default.id]
        if not default then return nil, 'invalid_storage' end
        local bySpec = {}
        for spec, reference in pairs(snapshot.bySpec) do
            if not keys[reference.id] then return nil, 'invalid_storage' end
            bySpec[spec] = keys[reference.id]
        end
        local active = catalog.activeByProfile and catalog.activeByProfile[profileName]
        if active and not keys[active] then return nil, 'invalid_storage' end
        result.providers[provider.id] = {
            sets = sets, active = keys[active] or default,
            assignments = { enabled = snapshot.enabled, default = default, bySpec = bySpec },
        }
    end
    return result
end

function Ownership:DeleteProfileState(productId, name)
    if type(name) ~= 'string' or name == '' then return nil, 'profile_unavailable' end
    local db = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(productId)
    if not (db and db.sv and db.sv.profiles) then return nil, 'db_not_ready' end
    local profile = db.sv.profiles[name]
    if type(profile) == 'table' then profile[Migration.STORAGE_KEY] = nil end
    return true
end

-- A local share adds one independent set. It must not restore a whole profile
-- library, renumber existing sets, or overwrite a same-named set.
function Service:PrepareIndependentSetImport(providerId, portable, mode, specKeys)
    local provider = self.providers[providerId]
    if not provider or not provider.editableUserSets then return nil, 'provider_not_found' end
    if mode ~= 'none' and mode ~= 'specs' and mode ~= 'default' then return nil, 'invalid_assignment_mode' end
    local ready, code, detail = Context.ensureExportCatalog(provider)
    if not ready then return nil, code, detail end
    local catalog
    catalog, code, detail = Context.getCatalog(provider, false)
    if not catalog then return nil, code, detail end
    if #catalog.order >= provider.maxUserSets then return nil, 'set_limit_reached' end
    local db, name = Context.profileIdentity(provider)
    local profile = db and db.sv and db.sv.profiles[name]
    if not profile then return nil, 'profile_unavailable' end
    local copied
    copied, code = Migration:CopyProfileStore({ schemaVersion = 2, providers = { [providerId] = catalog } })
    if not copied then return nil, code end
    local nextCatalog = copied.providers[providerId]
    local item
    item, code, detail = Context.normalizeImportItem(provider, portable, nil)
    if not item then return nil, code, detail end
    local unique
    unique, code = Context.uniqueName(provider, nextCatalog, item.name)
    if not unique then return nil, code end
    local id = Context.nextId(nextCatalog)
    item.key, item.id, item.name = nil, id, unique
    item.createdAt, item.updatedAt = Context.now(), Context.now()
    nextCatalog.items[id] = item
    nextCatalog.order[#nextCatalog.order + 1] = id
    local assignments, report = S.ConfigSetAssignments:Prepare(nextCatalog, Reference(id), mode,
        specKeys, Context.specKeys(), self:GetCurrentSpecializationKey())
    if not assignments then return nil, report end
    if mode == 'none' then
        report.changed, report.runtimeChanged = false, false
    else
        nextCatalog.assignments = assignments
    end
    local context = Context.buildContext(provider, 'local-share-snapshot', { database = db, profileName = name })
    local runtimeBefore
    runtimeBefore, code, detail = Context.capture(provider, provider.scopeOrder, context)
    if not runtimeBefore then return nil, code, detail end
    local before = assert(Migration:CopyProfileStore({ schemaVersion = 2, providers = { [providerId] = catalog } }))
    local token = { name = unique, reference = Reference(id), mode = mode }
    additions[token] = { provider = provider, database = db, profile = profile, name = name,
        original = catalog, before = before.providers[providerId], nextCatalog = nextCatalog,
        report = report, snapshot = runtimeBefore, context = context,
        currentSpec = self:GetCurrentSpecializationKey(),
        active = self.activeReferences[providerId], transaction = self.transactions[providerId] }
    return token, { changed = report.changed, runtimeChanged = report.runtimeChanged,
        currentReference = Reference(report.currentReference.id), name = unique, mode = mode }
end

function Service:ValidateIndependentSetImport(token)
    local staged = additions[token]
    if not staged or staged.committed or staged.restored then return nil, 'invalid_payload' end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil, 'in_combat' end
    if self.busy[staged.provider.id] then return nil, 'busy' end
    local db, name = Context.profileIdentity(staged.provider)
    if db ~= staged.database or name ~= staged.name or db.sv.profiles[name] ~= staged.profile then
        return nil, 'profile_changed'
    end
    local store = staged.profile[Migration.STORAGE_KEY]
    local catalog = store and store.providers[staged.provider.id]
    if catalog ~= staged.original then return nil, 'stale_import' end
    local copied = Migration:CopyProfileStore({ schemaVersion = 2, providers = { [staged.provider.id] = catalog } })
    if not copied or not Same(copied.providers[staged.provider.id], staged.before) then return nil, 'stale_import' end
    local snapshot = Context.capture(staged.provider, staged.provider.scopeOrder, staged.context)
    if not snapshot or not Same(snapshot, staged.snapshot) then return nil, 'stale_import' end
    if self.activeReferences[staged.provider.id] ~= staged.active
        or self:GetCurrentSpecializationKey() ~= staged.currentSpec then return nil, 'stale_import' end
    return true
end

function Service:RestoreIndependentSetImport(token)
    local staged = additions[token]
    if not staged or not staged.committed or staged.restored then return nil, 'invalid_payload' end
    local db, name = Context.profileIdentity(staged.provider)
    local store = staged.profile[Migration.STORAGE_KEY]
    if db ~= staged.database or name ~= staged.name or db.sv.profiles[name] ~= staged.profile
        or not store or store.providers[staged.provider.id] ~= staged.nextCatalog then return nil, 'stale_import' end
    store.providers[staged.provider.id] = staged.original
    self.activeReferences[staged.provider.id] = staged.active
    self.transactions[staged.provider.id] = staged.transaction
    staged.restored = true
    if staged.runtimeTouched then
        local rollbackContext = Context.buildContext(staged.provider, 'rollback', {
            database = staged.database, profileName = staged.name,
        })
        local ok, code, detail = Context.restoreSnapshot(staged.provider, staged.snapshot,
            staged.provider.scopeOrder, rollbackContext)
        if not ok then return nil, 'rollback_failed', detail or code end
    end
    Context.emit('YUI_CONFIG_SETS_CHANGED', staged.provider.id, 'local-share-rollback')
    Context.emit('YUI_CONFIG_SET_ACTIVE_CHANGED', staged.provider.id,
        staged.active and staged.active.reference, 'local-share-rollback')
    Context.emit('YUI_CONFIG_SET_ASSIGNMENTS_CHANGED', staged.provider.id)
    return true
end

function Service:CommitIndependentSetImport(token)
    local valid, code = self:ValidateIndependentSetImport(token)
    if not valid then return nil, code end
    local staged = additions[token]
    staged.profile[Migration.STORAGE_KEY].providers[staged.provider.id] = staged.nextCatalog
    staged.committed = true
    local application
    if staged.report.runtimeChanged then
        staged.runtimeTouched = true
        local called, applied, why, detail = pcall(self.Apply, self, staged.provider.id,
            staged.report.currentReference, token, {
                reason = 'local-share', deferNativeCategoryReloadPrompt = true,
            })
        if not called or not applied then
            local reason = not called and applied or detail or why
            local restored, restoreCode = self:RestoreIndependentSetImport(token)
            return nil, restored and 'apply_failed' or 'rollback_failed', reason or restoreCode
        end
        application = applied
    end
    Context.emit('YUI_CONFIG_SETS_CHANGED', staged.provider.id, 'local-share')
    Context.emit('YUI_CONFIG_SET_ASSIGNMENTS_CHANGED', staged.provider.id)
    return true, application
end

Service.ProfileOwnership = Ownership
Service.SCHEMA_VERSION = 2
for _, provider in pairs(Service.providers) do provider.configurationModes = nil end
return Ownership

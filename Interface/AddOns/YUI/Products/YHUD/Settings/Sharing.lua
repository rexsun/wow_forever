local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local Settings = YUI and YUI.Settings
local Transfer = Settings and Settings.ConfigTransfer
local Sets = Settings and Settings.ConfigSets
if not (YHUD and YHUD.ConfigSets and Transfer and Sets and Sets.PrepareIndependentSetImport) then return end
local Sharing = {}
YHUD.Sharing = Sharing
local MODULE_ID = 'product.yhud.selection'
local roots = { 'contentBySpec', 'officialOverridesBySpec', 'defaultPresetTombstonesBySpec', 'defaultPresetOverridesBySpec' }
local known = {}
for _, key in ipairs(YHUD:GetSupportedSpecKeys()) do known[key] = true end
local function AttachedSounds(value, reject)
    if type(value) ~= 'table' then return true end
    for key, child in pairs(value) do
        if key == 'sound' and type(child) == 'table' and type(child.rules) == 'table' then
            if reject then return false end
            value[key] = nil
        elseif type(child) == 'table' and not AttachedSounds(child, reject) then return false end
    end
    return true
end

local function Specs(raw, allowEmpty)
    if type(raw) ~= 'table' or #raw > 64 or (not allowEmpty and #raw == 0) then return nil, 'invalid_specialization' end
    local result, seen = {}, {}
    local rawSeen = {}
    for index, key in pairs(raw) do
        if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > #raw
            or type(key) ~= 'string' or rawSeen[key] then return nil, 'invalid_specialization' end
        rawSeen[key] = true
        local keys = YHUD.Client.legacySpecKeyMap and YHUD.Client.legacySpecKeyMap[key] or { key }
        for _, target in ipairs(keys) do
            if not known[target] then return nil, 'invalid_specialization' end
            if not seen[target] then seen[target] = true; result[#result + 1] = target end
        end
    end
    table.sort(result)
    return result, seen
end

function Sharing:ResponsibleSpecs(setId)
    local result = {}
    for _, key in ipairs(YHUD:GetSupportedSpecKeys()) do
        local reference, code = Sets:ResolveAssignment(YHUD.CONFIG_SET_PROVIDER_ID, key)
        if not reference then return nil, code end
        if reference.kind == 'user' and reference.id == setId then result[#result + 1] = key end
    end
    table.sort(result)
    return result
end

function Sharing:Capture(setId, selectedSpecs)
    local source, code = Sets:GetSetData(YHUD.CONFIG_SET_PROVIDER_ID, 'user', setId)
    if not source then return nil, code end
    local profile
    profile, code = YHUD.ConfigSets:PrepareProfileForTransfer(source.data.profile)
    if not profile then return nil, code end
    AttachedSounds(profile, false)
    local scope = { kind = selectedSpecs ~= nil and 'specs' or 'full' }
    local recommended
    if selectedSpecs ~= nil then
        local selected
        scope.specs, selected = Specs(selectedSpecs, false)
        if not scope.specs then return nil, selected end
        -- Keep the complete shared group/layout/appearance graph. Only the
        -- specialization documents are clipped; global references stay intact.
        for _, root in ipairs(roots) do
            for key in pairs(profile[root] or {}) do
                if not selected[key] then profile[root][key] = nil end
            end
        end
        recommended = YHUD:CopyValue(scope.specs)
    else
        recommended, code = self:ResponsibleSpecs(setId)
        if not recommended then return nil, code end
    end
    return { scope = scope, recommendedSpecs = recommended,
        item = { key = 'shared', name = source.set.name, description = source.set.description,
            providerSchemaVersion = source.providerSchemaVersion, scopeIds = source.scopeIds,
            data = { profile = profile } } }
end

local function Normalize(payload)
    if type(payload) ~= 'table' or type(payload.scope) ~= 'table' or type(payload.item) ~= 'table'
        or type(payload.item.data) ~= 'table' or type(payload.item.data.profile) ~= 'table' then return nil, 'invalid_payload' end
    if not AttachedSounds(payload.item.data.profile, true) then return nil, 'attached-sound-in-graphical-share' end
    for key in pairs(payload) do
        if key ~= 'scope' and key ~= 'item' and key ~= 'recommendedSpecs' then return nil, 'invalid_payload' end
    end
    for key in pairs(payload.scope) do if key ~= 'kind' and key ~= 'specs' then return nil, 'invalid_payload' end end
    local recommended, code = Specs(payload.recommendedSpecs, true)
    if not recommended then return nil, code end
    if payload.scope.kind == 'specs' then
        local specs, selected = Specs(payload.scope.specs, false)
        if not specs then return nil, selected end
        local profile = payload.item.data.profile
        YHUD:MigrateClientSpecializationKeys(profile)
        if profile.specDocuments ~= nil or profile.contentBySpecPack ~= nil then return nil, 'invalid_payload' end
        for _, root in ipairs(roots) do
            if profile[root] ~= nil and type(profile[root]) ~= 'table' then return nil, 'invalid_payload' end
            for key in pairs(profile[root] or {}) do if not selected[key] then return nil, 'content_outside_scope' end end
        end
        for _, key in ipairs(recommended) do if not selected[key] then return nil, 'assignment_outside_scope' end end
        payload.scope.specs = specs
    elseif payload.scope.kind ~= 'full' or payload.scope.specs ~= nil then return nil, 'invalid_payload' end
    payload.recommendedSpecs = recommended
    return payload
end

function Sharing:BuildExport(setId, specs, includeSounds, includeGeneral)
    local payload, code = self:Capture(setId, specs)
    if not payload then return nil, code end
    local modules = { MODULE_ID }
    if includeSounds == true then modules[#modules + 1] = 'core.sound' end
    return Transfer:BuildExport(modules, { yhudShare = payload,
        soundSpecs = specs or payload.recommendedSpecs, includeGeneralSounds = includeGeneral == true })
end

function Sharing:ShowExport(setId, specs, layoutOwner)
    local payload, code = self:Capture(setId, specs)
    if not payload then return false, code end
    if not Settings.ShowConfigTransferExport then return false, 'dialog_unavailable' end
    Settings:ShowConfigTransferExport({ profileName = payload.item.name, soundScopeOption = true,
        layoutOwner = layoutOwner,
        exportHeaderHeight = 58,
        configureExport = self.ConfigureExport and function(frame) self:ConfigureExport(frame, setId, specs) end,
        context = { moduleIds = { MODULE_ID, 'core.sound' }, yhudShare = payload,
            soundSpecs = specs or payload.recommendedSpecs, includeGeneralSounds = false } })
    return true
end

function Sharing:ConvertLegacyString(value)
    if InCombatLockdown and InCombatLockdown() then return nil, 'in_combat' end
    local legacy, code = Sets:DecodeUserSet(YHUD.CONFIG_SET_PROVIDER_ID, value)
    if not legacy then return nil, code end
    local item = legacy.set
    if type(item.data) ~= 'table' or type(item.data.profile) ~= 'table' then return nil, 'invalid_payload' end
    local profile
    profile, code = YHUD.ConfigSets:PrepareProfileForTransfer(item.data.profile)
    if not profile then return nil, code end
    local records = {}
    if not AttachedSounds(profile, true) then
        local migration = YHUD.LegacySoundMigration
        if not migration then return nil, 'legacy-migration-unavailable' end
        local specs = {}; for key in pairs(known) do specs[key] = true end
        local native, reader = {}, YUI.API and YUI.API.CooldownViewer
        for _, entry in ipairs(reader and reader.ReadEntries and reader:ReadEntries({includeHidden=true,allowUnlearned=true}) or {}) do native[entry.cooldownID] = entry end
        records = migration:Collect(profile, 'incoming', specs, native)
    end
    AttachedSounds(profile, false)
    local payload = { scope = {kind='full'}, recommendedSpecs = {}, item = {
        key='shared',name=item.name,description=item.description,providerSchemaVersion=legacy.providerSchemaVersion,
        scopeIds=item.scopeIds,data={profile=profile} } }
    local payloads = {[MODULE_ID]=payload}
    if #records > 0 then payloads['core.sound.legacy'] = {records=records} end
    return Transfer:BuildImportString(payloads)
end

function Sharing:SplitProfileImport(payload)
    local result = YHUD:CopyValue(payload)
    local migration = YHUD.LegacySoundMigration
    local records, native = {}, nil
    local function Native()
        if native then return native end
        native={}
        local reader=YUI.API and YUI.API.CooldownViewer
        if not (InCombatLockdown and InCombatLockdown()) then
            for _,entry in ipairs(reader and reader.ReadEntries and reader:ReadEntries({includeHidden=true,allowUnlearned=true}) or {}) do native[entry.cooldownID]=entry end
        end
        return native
    end
    local function Expand(container, key, assigned, collect)
        if type(container)~='table' or type(container.profile)~='table' then return false end
        if container.profile.specDocuments==nil and container.profile.contentBySpecPack==nil
            and AttachedSounds(container.profile,true) then return true end
        local profile=YHUD.ConfigSets:PrepareProfileForTransfer(container.profile)
        if not profile then return false end
        if not AttachedSounds(profile, true) and not migration then return false end
        if collect and migration then
            for _,record in ipairs(migration:Collect(profile,key,assigned,Native())) do
                records[#records+1]=record
                if #records>4096 then return false end
            end
        end
        AttachedSounds(profile,false); container.profile=profile
        return true
    end
    local state=type(result.configSets)=='table' and result.configSets
    local provider=state and type(state.providers)=='table' and state.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    if provider then
        if type(provider)~='table' or type(provider.sets)~='table' then return nil end
        local active,assignments
        if state.schema==2 then active,assignments=provider.active,provider.assignments
        elseif state.schema==1 and type(provider.specialization)=='table' then
            active=provider.mode=='unified' and provider.unified or provider.specialization.active
            assignments=provider.mode=='specialization' and provider.specialization.assignments
        else return nil end
        for _,item in ipairs(provider.sets) do
            if type(item)~='table' or type(item.key)~='string' then return nil end
            local assigned={}
            for spec in pairs(known) do
                local owner=active
                if type(assignments)=='table' and assignments.enabled==true then
                    if type(assignments.bySpec)~='table' then return nil end
                    owner=assignments.bySpec[spec] or assignments.default
                end
                assigned[spec]=owner==item.key
            end
            if not Expand(item.data,item.key,assigned,true) then return nil end
        end
    end
    local data=type(result.data)=='table' and result.data[YHUD.STORAGE_KEY]
    if data and not Expand(data,'profile',{},not provider) then return nil end
    if #records==0 then return result end
    return result,{['core.sound.legacy']={records=records}}
end

Transfer:RegisterModule({ id = MODULE_ID, kind = 'product', schemaVersion = 1,
    labelKey = 'sound.center.graphical_share', hiddenFromProfile = true,
    exclusiveWith = { 'product.yhud' }, clients = { retail = true, forever = true }, maxPayloadNodes = 131072,
    payloadDepthOverhead = 2,
    productId = function()
        local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
        return provider and provider.productId or 'yhud'
    end,
    capture = function(_, context)
        if not (context and context.yhudShare) then return nil, 'share_selection_required' end
        return Normalize(YHUD:CopyValue(context.yhudShare))
    end,
    normalize = Normalize,
    snapshot = function(_, context, payload)
        local specs = context and context.yhudAssignmentSpecs or payload.recommendedSpecs
        local selected, code = Specs(specs, true)
        if not selected then return nil, code end
        if payload.scope.kind == 'specs' then
            local _, included = Specs(payload.scope.specs, false)
            for _, key in ipairs(selected) do if not included[key] then return nil, 'assignment_outside_scope' end end
        end
        local mode = context and context.yhudReserve == true and 'none' or (#selected > 0 and 'specs' or 'none')
        local item = payload.item
        local name = context and context.yhudImportName
        if type(name) == 'string' and name:find('%S') then
            item = {}
            for key, value in pairs(payload.item) do item[key] = value end
            item.name = name:match('^%s*(.-)%s*$')
        end
        local token, report = Sets:PrepareIndependentSetImport(YHUD.CONFIG_SET_PROVIDER_ID, item, mode, selected)
        if not token then return nil, report end
        local routes = {}
        local defaultSpecCount
        if mode ~= 'none' then
            local assignments, why = Sets:GetAssignments(YHUD.CONFIG_SET_PROVIDER_ID)
            if not assignments then return nil, why end
            local assigned = {}
            for _, spec in ipairs(selected) do
                assigned[spec] = true
                local reference
                if not (context and context.previewNewProfile) then
                    reference, why = Sets:ResolveAssignment(YHUD.CONFIG_SET_PROVIDER_ID, spec)
                    if not reference then return nil, why end
                end
                routes[#routes + 1] = { spec = spec, before = YHUD:CopyValue(reference) }
            end
            defaultSpecCount = 0
            for _, spec in ipairs(YHUD:GetSupportedSpecKeys()) do
                local reference = assignments.bySpec[spec] or assignments.default
                if not assigned[spec] and (context and context.previewNewProfile
                    or reference.kind == assignments.default.kind and reference.id == assignments.default.id) then
                    defaultSpecCount = defaultSpecCount + 1
                end
            end
        end
        local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
        local db = YUI.DB:GetAceDB(provider.productId)
        return { database = db, profileName = db:GetCurrentProfile(), token = token,
            report = report, specs = selected, routes = routes, defaultSpecCount = defaultSpecCount,
            scope = YHUD:CopyValue(payload.scope) }
    end,
    validateSnapshot = function(snapshot) return Sets:ValidateIndependentSetImport(snapshot.token) end,
    apply = function(_, entry)
        local ok, code, detail = Sets:CommitIndependentSetImport(entry.snapshot.token)
        entry.snapshot.applied = ok == true
        local result = ok and type(code) == 'table' and code.result
        if type(result) == 'table' and result.nativeCategoryReloadDeferred == true then
            entry.snapshot.nativeCategoryReload = {
                automatic = true, plan = result.nativeCategoryPlan, report = result.nativeCategoryReport,
                reference = YHUD:CopyValue(entry.snapshot.report.currentReference),
                database = entry.snapshot.database, profileName = entry.snapshot.profileName,
                specKey = YHUD:GetCurrentSpecKey(),
            }
        end
        return ok, not ok and code or nil, detail
    end,
    showCompletion = function(entry)
        local request = entry.snapshot.nativeCategoryReload
        if not request then return false end
        entry.snapshot.nativeCategoryReload = nil
        return YHUD.ConfigSets:RequestNativeCategoryReloadPrompt(request)
    end,
    restore = function(snapshot)
        if not snapshot.applied then return true end
        return Sets:RestoreIndependentSetImport(snapshot.token)
    end,
})
Sharing.Normalize = Normalize
Sharing.MODULE_ID = MODULE_ID

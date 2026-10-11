local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local S = YUI and YUI.Sound
local Sets = YUI and YUI.Settings and YUI.Settings.ConfigSets
if not (YHUD and S and S.LegacyMigration and Sets) then return end
local Migration = {}
YHUD.LegacySoundMigration = Migration
local MARKER = 'SoundLegacyMigration'
local SLICE_MS = 4
local function NowMS()
    return debugprofilestop and debugprofilestop() or (GetTime and GetTime() * 1000 or 0)
end
local function Complete(marker)
    return type(marker) == 'table' and marker.version == S.LegacyMigration.VERSION
        and marker.cleanupComplete == true and marker.cleanupRevision == 2
        and type(marker.seen) == 'table' and type(marker.suppressed) == 'table'
        and type(marker.archive) == 'table' and next(marker.archive) == nil
        and type(marker.recovery) == 'table' and next(marker.recovery) == nil
end
local function Same(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end
    for key, value in pairs(left) do if not Same(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function ValidMarker(marker)
    return type(marker) == 'table' and marker.version == S.LegacyMigration.VERSION
        and type(marker.seen) == 'table' and type(marker.archive) == 'table'
        and type(marker.suppressed) == 'table' and type(marker.recovery) == 'table'
end
local function Keys(value)
    local keys = {}; for key in pairs(value or {}) do keys[#keys + 1] = key end
    table.sort(keys); return keys
end
local function Object(entry, native)
    if native then
        if native.sourceCategory == 'essential' or native.sourceCategory == 'utility' then
            if native.equipSlot then return { kind = 'slot', id = native.equipSlot }, false end
            return { kind = 'spell', id = native.overrideSpellID or native.spellID }, native.charges
        end
        if native.spellID == 365350 and type(native.linkedSpellIDs) == 'table'
            and #native.linkedSpellIDs == 1 and native.linkedSpellIDs[1] == 365362 then
            return { kind = 'aura', id = 365362 }, nil, true
        end
        return nil
    end
    if not entry then return nil end
    if entry.sourceType == 'spell-cooldown' then return { kind = 'spell', id = entry.spellId }, entry.charges end
    if entry.sourceType == 'item-cooldown' then
        if entry.equipSlot or entry.slotId then return { kind = 'slot', id = entry.equipSlot or entry.slotId }, false end
        if entry.itemIds and #entry.itemIds > 1 then return nil end
        return { kind = 'item', id = entry.itemId or entry.itemID }, false
    end
    return nil
end

-- Read stored documents directly after the established storage decoder. Do not
-- reconcile graph catalogs: that could fill defaults or hide an unresolved row.
function Migration:Collect(expanded, setId, assigned, nativeById)
    local records = {}
    local specs = {}
    for key in pairs(expanded.contentBySpec or {}) do specs[key] = true end
    for key in pairs(expanded.officialOverridesBySpec or {}) do specs[key] = true end
    for _, spec in ipairs(Keys(specs)) do
        local content = (expanded.contentBySpec or {})[spec] or {}
        local overrides = (expanded.officialOverridesBySpec or {})[spec] or {}
        local monitors = {}
        for key in pairs(content.monitors or {}) do monitors[key] = true end
        for key in pairs(overrides.monitors or {}) do monitors[key] = true end
        for _, monitorId in ipairs(Keys(monitors)) do
            local monitor = (content.monitors or {})[monitorId] or {}
            local override = (overrides.monitors or {})[monitorId] or {}
            local sound = override.sound ~= nil and override.sound or monitor.sound
            if type(sound) == 'table' and type(sound.rules) == 'table' then
                local entry = (content.entries or {})[monitor.entryKey or monitorId]
                local cooldownID = tonumber(monitorId:match('^cdm:(%d+)$'))
                local native = cooldownID and nativeById[cooldownID]
                local object, charges, independentAura = Object(entry, native)
                for index, raw in ipairs(sound.rules) do
                    local enabled = override.enabled
                    if enabled == nil then enabled = monitor.enabled end
                    local groupId = override.groupId or monitor.groupId
                    local group = groupId and expanded.groups and expanded.groups.items and expanded.groups.items[groupId]
                    if group and group.enabled == false then enabled = false end
                    records[#records + 1] = { key = setId .. '/' .. spec .. '/' .. monitorId .. '/' .. index,
                        setId = setId, spec = spec, monitorId = monitorId, ruleIndex = index,
                        assigned = assigned[spec] == true, enabled = enabled ~= false,
                        object = object, hasCharges = charges, independentAura = independentAura,
                        raw = YHUD:CopyValue(raw) }
                end
            end
        end
    end
    return records
end

function Migration:BuildPlan(checkpoint)
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    if not provider then return nil, 'provider-unavailable' end
    local database = YUI.DB:GetAceDB(provider.productId)
    if database ~= YUI.DB:GetAceDB(S.storageProductId) then return nil, 'legacy-storage-owner-mismatch' end
    local nativeById = {}
    local reader = YUI.API and YUI.API.CooldownViewer
    local native = reader and reader.ReadEntries and reader:ReadEntries({ includeHidden = true, allowUnlearned = true })
    if not native then return nil, 'native-catalog-unavailable' end
    local library, code = Sets:ListUserSets(YHUD.CONFIG_SET_PROVIDER_ID)
    if not library then return nil, code end
    for _, entry in ipairs(native or {}) do nativeById[entry.cooldownID] = entry end
    local assignments = {}
    local assignmentState, assignmentCode = Sets:GetAssignments(YHUD.CONFIG_SET_PROVIDER_ID)
    if not assignmentState then return nil, assignmentCode end
    for _, spec in ipairs(YHUD:GetSupportedSpecKeys()) do
        local reference = assignmentState.bySpec[spec] or assignmentState.default
        if not reference then return nil, 'assignment_not_found' end
        if reference.kind == 'user' then
            assignments[reference.id] = assignments[reference.id] or {}; assignments[reference.id][spec] = true
        end
    end
    local records, collected, cleanup = {}, {}, {}
    local marker = database.profile[MARKER]
    local characters = database.global and database.global.consolePreferences
    characters = type(characters) == 'table' and characters.characters
    local preference = type(characters) == 'table' and database.keys and characters[database.keys.char]
    local characterMuted = type(preference) == 'table' and preference.soundEnabled == false
    if marker ~= nil and not ValidMarker(marker) then return nil, 'invalid-legacy-migration-state' end
    for _, item in ipairs(library) do
        local data, why = Sets:GetSetData(YHUD.CONFIG_SET_PROVIDER_ID, 'user', item.id)
        if not data then return nil, why end
        if checkpoint then checkpoint('read-set') end
        local expanded, detail = YHUD.ConfigSets:PrepareLegacySoundProfile(data.data.profile, checkpoint)
        if not expanded then return nil, detail end
        for _, record in ipairs(self:Collect(expanded, item.id, assignments[item.id] or {}, nativeById)) do
            if not (marker and marker.seen[record.key]) then
                local previous = marker and marker.archive[record.key]
                if previous then
                    record.assigned, record.enabled, record.raw = previous.assigned, previous.enabled, YHUD:CopyValue(previous.raw)
                    record.characterMuted = previous.characterMuted
                else
                    record.characterMuted = characterMuted
                end
                records[#records + 1] = record
                collected[record.key] = true
            end
            if #records > 4096 then return nil, 'legacy-record-budget' end
        end
        local changed=false
        local function Strip(value)
            for key,child in pairs(value) do
                if key=='sound' and type(child)=='table' and type(child.rules)=='table' then
                    value[key]=nil; changed=true
                elseif type(child)=='table' then Strip(child) end
            end
        end
        Strip(expanded)
        if changed then
            -- Clean the isolated stored copy directly: do not normalize/re-encode
            -- all specializations just because one document contained a sound.
            if type(data.data.profile.contentBySpecPack) == 'table' then
                -- Older monolithic packs cannot be patched by document; retire
                -- them through the established encoder after stripping the copy.
                local stored, cleanupCode = YHUD.ConfigSets:PrepareProfileForStorage(expanded, true)
                if not stored then return nil, cleanupCode end
                data.data.profile = stored
            else
                local edits, cleanupCode = self:PrepareResidualCleanup(nil, checkpoint, { data.data.profile })
                if not edits then return nil, cleanupCode end
                for _, edit in ipairs(edits) do edit.target[edit.key] = edit.value end
            end
            cleanup[#cleanup+1]={id=item.id,data=data.data,scopeIds=data.scopeIds}
        end
        if checkpoint then checkpoint('prepare-set') end
    end
    -- Include pending archives even when their graphical library no longer exists.
    for _, key in ipairs(Keys(marker and marker.archive)) do
        if not marker.seen[key] and not collected[key] then
            records[#records + 1] = YHUD:CopyValue(marker.archive[key])
            if #records > 4096 then return nil, 'legacy-record-budget' end
        end
    end
    local current, why = S.RuleStore:Read()
    if not current then return nil, why end
    -- Assigned reminders take precedence over dormant graphical copies.
    local activeKeys = {}
    for _, record in ipairs(records) do
        if record.assigned == true then
            if record.characterMuted == true then record.enabled = false end
            record.characterMuted = false
            local rule = S.LegacyMigration:Convert(record, 'mainline')
            if rule then activeKeys[S.RuleModel:Key(rule) .. '|' .. record.spec] = true end
        end
    end
    for _, record in ipairs(records) do
        if record.assigned ~= true then
            record.assigned, record.characterMuted, record.enabled = true, false, false
            local rule = S.LegacyMigration:Convert(record, 'mainline')
            if rule and activeKeys[S.RuleModel:Key(rule) .. '|' .. record.spec] then
                record.assigned = false
            end
        end
    end
    local plan, why = S.LegacyMigration:Prepare(records, current, 'mainline')
    if plan then plan.nativeAvailable = native ~= nil; plan.cleanup=cleanup end
    return plan, why
end

-- One-time retirement of obsolete graphical copies, including serialized documents.
-- Prepare every edit before changing live tables so a bad block cannot partially clean them.
function Migration:PrepareResidualCleanup(database, checkpoint, roots)
    local edits, visited = {}, {}
    local blocks = self.job and self.job.blocks or {}
    local visitedCount = 0
    local function Visit(value, pending)
        if type(value) ~= 'table' or visited[value] then return true end
        visited[value] = true
        visitedCount = visitedCount + 1
        if checkpoint and visitedCount % 64 == 0 then checkpoint('scan-residual') end
        for key, child in pairs(value) do
            if key == 'sound' and type(child) == 'table' and type(child.rules) == 'table' then
                pending[#pending + 1] = { target = value, key = key, before = child }
            elseif key == 'specDocuments' and type(child) == 'table' and type(child.blocks) == 'table' then
                local stub = _G.LibStub
                local codec = stub and stub.GetLibrary and stub:GetLibrary('AceSerializer-3.0', true)
                if not codec then return nil, 'storage-codec-unavailable' end
                for spec, block in pairs(child.blocks) do
                    if type(block) ~= 'string' then return nil, 'invalid-content-pack' end
                    local text = blocks[block]
                    if not text then
                        local called, ok, document = pcall(codec.Deserialize, codec, block)
                        if not called or not ok or type(document) ~= 'table' then return nil, 'invalid-content-pack' end
                        local changes = {}
                        local valid, code = Visit(document, changes)
                        if not valid then return nil, code end
                        text = block
                        if #changes > 0 then
                            for _, edit in ipairs(changes) do edit.target[edit.key] = edit.value end
                            local encoded
                            encoded, text = pcall(codec.Serialize, codec, document)
                            if not encoded or type(text) ~= 'string' then return nil, 'invalid-content-pack' end
                            local decoded, success, check = pcall(codec.Deserialize, codec, text)
                            if not decoded or not success or not Same(document, check) then return nil, 'invalid-content-pack' end
                        end
                        blocks[block] = text
                    end
                    if text ~= block then
                        pending[#pending + 1] = { target = child.blocks, key = spec, before = block, value = text }
                    end
                    if checkpoint then checkpoint('decode-residual') end
                end
            elseif type(child) == 'table' then
                local ok, code = Visit(child, pending)
                if not ok then return nil, code end
            end
        end
        return true
    end
    if not roots then
        local profile = database.profile
        local global = database.global
        local legacy = global and global.SettingsConfigSets
        local current = profile.SettingsConfigSetsV2
        roots = {
            current and current.providers and current.providers[YHUD.CONFIG_SET_PROVIDER_ID] or {},
            profile.YHUD and profile.YHUD.profile or {},
            legacy and legacy.providers and legacy.providers[YHUD.CONFIG_SET_PROVIDER_ID] or {},
            YHUD._runtimeProfile or {},
            YHUD._runtimeProfileCanonical or {},
        }
    end
    for _, root in ipairs(roots) do
        local ok, code = Visit(root, edits)
        if not ok then return nil, code end
    end
    return edits
end

function Migration:RunMigration(runtime, force, checkpoint)
    if InCombatLockdown and InCombatLockdown() then return false, 'combat-lockdown' end
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local database = provider and YUI.DB:GetAceDB(provider.productId)
    if not database or not database.profile then return false, 'profile-unavailable' end
    local profile, name = database.profile, database:GetCurrentProfile()
    local marker = profile[MARKER]
    -- Completion belongs to the stored profile, not to the current Lua session.
    -- Library mutations invalidate it; pending imports and failed cleanup still retry.
    if not force and Complete(marker) then return true end
    local plan, code = self:BuildPlan(checkpoint)
    if not plan then return false, code end
    if not plan.nativeAvailable then return false,'native-catalog-unavailable' end
    if #plan.cleanup>0 and not YHUD.ConfigSets.UpdateLegacySoundCleanup then return false,'cleanup-unavailable' end
    -- All decoding and validation finish before reminders or graphical copies change.
    local edits, why = self:PrepareResidualCleanup(database, checkpoint)
    if not edits then return false, why end
    if checkpoint then checkpoint('commit', true) end
    if database.profile ~= profile or database:GetCurrentProfile() ~= name then return false, 'stale-preview' end
    for _, edit in ipairs(edits) do
        if edit.target[edit.key] ~= edit.before then return false, 'stale-preview' end
    end
    if #plan.records > 0 then
        local old = profile[MARKER]
        local marker = old and YHUD:CopyValue(old) or { version = S.LegacyMigration.VERSION, seen = {}, archive = {}, suppressed = {} }
        marker.recovery = {}
        for _, record in ipairs(plan.records) do
            if not marker.archive[record.key] then marker.archive[record.key] = YHUD:CopyValue(record) end
        end
        for _, record in ipairs(plan.records) do
            marker.seen[record.key] = true
            local sets = marker.suppressed
            sets[record.setId] = sets[record.setId] or {}
            local specs = sets[record.setId]; specs[record.spec] = specs[record.spec] or {}
            local monitors = specs[record.spec]; monitors[record.monitorId] = monitors[record.monitorId] or {}
            local rawCondition = type(record.raw) == 'table' and record.raw.condition
            local condition = type(rawCondition) == 'table' and rawCondition.type or rawCondition
            if type(condition) == 'string' then monitors[record.monitorId][condition] = true end
        end
        local prepared, why = S.RuleStore:PrepareImport(plan.rules, 'replace')
        if not prepared then return false, why end
        profile[MARKER] = marker
        local called, ok, detail = pcall(S.RuleStore.Commit, S.RuleStore, prepared, runtime)
        if not called or not ok then profile[MARKER] = old; return false, called and detail or ok end
    end
    -- Commit independent reminders first. Failed cleanup is retried without duplicating them.
    for _,item in ipairs(plan.cleanup) do
        if database.profile~=profile or database:GetCurrentProfile()~=name then return false,'stale-preview' end
        self.committing = true
        local called,ok,why=pcall(YHUD.ConfigSets.UpdateLegacySoundCleanup,YHUD.ConfigSets,item.id,item.data,item.scopeIds)
        self.committing = nil
        if not called or not ok then return false,called and why or ok end
    end
    if database.profile ~= profile or database:GetCurrentProfile() ~= name then return false, 'stale-preview' end
    for _, edit in ipairs(edits) do edit.target[edit.key] = edit.value end
    local marker = profile[MARKER]
    if not marker then
        marker = { version = S.LegacyMigration.VERSION, seen = {}, suppressed = {} }
        profile[MARKER] = marker
    end
    marker.archive, marker.recovery = {}, {}
    marker.cleanupComplete, marker.cleanupRevision = true, 2
    self.lastReport = { converted = #plan.converted, deleted = #plan.recovery, recovery = 0 }
    return true, nil, #plan.records > 0
end

function Migration:IsComplete()
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    return db and db.profile and Complete(db.profile[MARKER]) or false
end

-- Only called for owned runtime-save copies, never imported graphical payloads.
function Migration:StripCompletedRuntime(value)
    if not self:IsComplete() then return end
    local visited = {}
    local function Strip(node)
        if type(node) ~= 'table' or visited[node] then return end
        visited[node] = true
        for key, child in pairs(node) do
            if key == 'sound' and type(child) == 'table' and type(child.rules) == 'table' then
                node[key] = nil
            elseif type(child) == 'table' then Strip(child) end
        end
    end
    Strip(value)
end

function Migration:Cancel(runtime)
    local job = self.job
    if not job or runtime and job.runtime ~= runtime then return end
    if job.timer then job.timer:Cancel() end
    job.timer, job.thread, job.blocks = nil, nil, nil
    self.job = nil
end

local function CurrentJob(job)
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    return db == job.database and db.profile == job.profile
        and db:GetCurrentProfile() == job.name and YHUD:GetCurrentSpecKey() == job.spec
        and job.profile[MARKER] == job.marker and job.profile.SoundRules == job.rules
        and (not job.rules or job.rules.revision == job.ruleRevision)
end

function Migration:ScheduleJob()
    local job = self.job
    if not job or job.timer then return end
    job.timer = C_Timer.NewTimer(0, function()
        job.timer = nil
        if Migration.job ~= job then return end
        if not CurrentJob(job) then Migration:Cancel(); return end
        if InCombatLockdown and InCombatLockdown() then job.paused = true; return end
        job.paused = nil
        local started = NowMS()
        job.deadline = started + SLICE_MS
        local called, ok, code = coroutine.resume(job.thread)
        if Migration.job ~= job then return end
        local elapsed = math.max(0, NowMS() - started)
        job.stats.slices = job.stats.slices + 1
        job.stats.elapsedMS = job.stats.elapsedMS + elapsed
        if elapsed > job.stats.maxSliceMS then
            job.stats.maxSliceMS, job.stats.maxSlicePhase = elapsed, job.phase
        end
        if not called or coroutine.status(job.thread) == 'dead' then
            job.stats.ok = called and ok == true
            if not called then job.stats.code = ok else job.stats.code = code end
            Migration.lastJobStats = job.stats
            Migration:Cancel()
            if called and ok == true then
                S.LegacyMigration.lastIssue = nil
                if job.runtime and job.runtime.OnContextChanged then
                    job.runtime:OnContextChanged('legacy-migration-complete')
                end
            else
                S.LegacyMigration.lastIssue = { provider = 'yhud', reason = job.stats.code }
                -- A corrupt/unchanged payload must not restart an expensive job on every combat exit.
                if job.stats.code == 'invalid-content-pack' or job.stats.code == 'capacity-exceeded'
                    or job.stats.code == 'invalid-legacy-migration-state' then
                    Migration.failure = { profile = job.profile, marker = job.profile[MARKER],
                        rules = job.profile.SoundRules, code = job.stats.code }
                end
            end
            return
        end
        Migration:ScheduleJob()
    end)
end

function Migration:Migrate(runtime, force)
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    if not db or not db.profile then return false, 'profile-unavailable' end
    if not force and Complete(db.profile[MARKER]) then return true end
    local failed = self.failure
    if not force and failed and failed.profile == db.profile
        and failed.marker == db.profile[MARKER] and failed.rules == db.profile.SoundRules then
        return false, failed.code
    end
    if force and ValidMarker(db.profile[MARKER]) then db.profile[MARKER].cleanupComplete = nil end
    if self.job and (force or not CurrentJob(self.job)) then self:Cancel() end
    if InCombatLockdown and InCombatLockdown() then return false, 'combat-lockdown' end
    -- Synchronous entry remains usable by offline validation without a frame scheduler.
    if not (C_Timer and C_Timer.NewTimer) then return self:RunMigration(runtime, force) end
    if not self.job then
        local job = { database = db, profile = db.profile, name = db:GetCurrentProfile(),
            spec = YHUD:GetCurrentSpecKey(), marker = db.profile[MARKER], runtime = runtime,
            rules = db.profile.SoundRules, ruleRevision = db.profile.SoundRules and db.profile.SoundRules.revision,
            blocks = {}, stats = { slices = 0, elapsedMS = 0, maxSliceMS = 0 } }
        local function Checkpoint(phase, forceYield)
            job.phase = phase
            if forceYield or NowMS() >= job.deadline then coroutine.yield() end
        end
        job.thread = coroutine.create(function() return Migration:RunMigration(runtime, force, Checkpoint) end)
        self.job = job
    end
    self:ScheduleJob()
    return true
end

function Migration:CaptureIdentity(profile, monitor, compiled)
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local database = provider and YUI.DB:GetAceDB(provider.productId)
    local reference = Sets:GetActiveReference(YHUD.CONFIG_SET_PROVIDER_ID)
    if not database or not reference or reference.kind ~= 'user' then return end
    compiled.migrationProfile = database.profile
    compiled.migrationSetId, compiled.migrationSpec, compiled.migrationMonitorId = reference.id,
        rawget(profile, '_yhudSpecKey') or YHUD:GetCurrentSpecKey(), monitor.id
end
function Migration:IsSuppressed(compiled, condition)
    local marker = compiled.migrationProfile and compiled.migrationProfile[MARKER]
    local sets = type(marker) == 'table' and marker.suppressed
    local specs = sets and sets[compiled.migrationSetId]
    local monitors = specs and specs[compiled.migrationSpec]
    local conditions = monitors and monitors[compiled.migrationMonitorId]
    return conditions and conditions[condition] == true or false
end
function Migration:GetRecoveryItems()
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    local marker = db and db.profile and db.profile[MARKER]
    local result = {}
    if not ValidMarker(marker) then return result end
    for _, problem in ipairs(marker.recovery) do
        local record = type(problem) == 'table' and marker.archive[problem.key]
        if type(record) == 'table' and type(record.raw) == 'table'
            and type(record.spec) == 'string' and not marker.seen[problem.key] then result[#result + 1] = {
            provider = self, key = problem.key, record = YHUD:CopyValue(record), reason = problem.reason } end
    end
    return result
end
function Migration:GetRecoveryCount()
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    local marker = db and db.profile and db.profile[MARKER]
    return ValidMarker(marker) and #marker.recovery or 0
end
function Migration:CheckExport(scope)
    local plan, code = self:BuildPlan()
    if not plan then return nil, code end
    local selected = {}
    for _, spec in ipairs(scope or {}) do selected[spec] = true end
    for _, record in ipairs(plan.records) do
        if scope == nil or selected[record.spec] then return nil, 'legacy-sounds-pending' end
    end
    return true
end
function Migration:PrepareRecovery(key)
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    local profile = db and db.profile
    local marker = profile and profile[MARKER]
    if not ValidMarker(marker) then return nil, 'invalid-legacy-migration-state' end
    local original = marker.archive[key]
    if type(original) ~= 'table' or type(original.raw) ~= 'table'
        or type(original.spec) ~= 'string' or marker.seen[key] then return nil, 'stale-preview' end
    local record = YHUD:CopyValue(original); record.assigned = true; record.characterMuted = false
    local rule = S.LegacyMigration:Convert(record, 'mainline')
    if not rule then
        rule = { object = YHUD:CopyValue(record.object or { kind = 'spell', id = 0, unit = 'player' }),
            trigger = { event = '' }, specs = { record.spec }, enabled = record.enabled ~= false,
            talents = {}, category = 'class',
            sound = S.LegacyMigration:ResolveSound(record.raw.sound, record.spec, 'mainline') or { kind = 'voice', value = '' } }
    end
    -- Reserved reminders remain disabled until the player explicitly enables
    -- the independent rule after reviewing its object, condition and sound.
    if original.assigned ~= true or original.characterMuted == true then rule.enabled = false end
    return { profile = profile, marker = marker, key = key, rule = rule }
end
function Migration:CommitRecovery(recovery, editToken, rules, runtime)
    local provider = Sets.providers[YHUD.CONFIG_SET_PROVIDER_ID]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    if not recovery or not db or db.profile ~= recovery.profile or db.profile[MARKER] ~= recovery.marker then return nil, 'stale-editor' end
    local marker = YHUD:CopyValue(recovery.marker)
    local record = marker.archive[recovery.key]
    if not record or marker.seen[recovery.key] then return nil, 'stale-editor' end
    marker.seen[recovery.key] = true
    local sets = marker.suppressed
    sets[record.setId] = sets[record.setId] or {}
    sets[record.setId][record.spec] = sets[record.setId][record.spec] or {}
    local monitors = sets[record.setId][record.spec]
    monitors[record.monitorId] = monitors[record.monitorId] or {}
    local condition = type(record.raw.condition) == 'table' and record.raw.condition.type or record.raw.condition
    if type(condition) == 'string' then monitors[record.monitorId][condition] = true end
    for i = #marker.recovery, 1, -1 do if marker.recovery[i].key == recovery.key then table.remove(marker.recovery, i) end end
    db.profile[MARKER] = marker
    local called, ok, code = pcall(S.RuleStore.CommitEdit, S.RuleStore, editToken, rules, runtime)
    if not called or not ok then recovery.profile[MARKER] = recovery.marker; return nil, called and code or 'legacy-recovery-failed' end
    return true
end
function Migration:DisableLegacy(key, runtime)
    local recovery, code = self:PrepareRecovery(key)
    if not recovery then return nil, code end
    local token, why = S.RuleStore:BeginEdit()
    if not token then return nil, why end
    return self:CommitRecovery(recovery, token, token.rules, runtime)
end
function Migration:OnLibraryChanged(_, providerId, reason)
    if providerId ~= YHUD.CONFIG_SET_PROVIDER_ID or self.committing then return end
    if reason == 'register-builtin' or reason == 'picker-preferences' then return end
    self:Cancel()
    self.failure = nil
    if reason == 'autosave' or reason == 'data-patch' or reason == 'assignment'
        or reason == 'assignment-draft' or reason == 'delete' then return end
    local provider = Sets.providers[providerId]
    local db = provider and YUI.DB:GetAceDB(provider.productId)
    local profile = db and db.profile
    if not profile then return end
    local marker = profile[MARKER]
    if ValidMarker(marker) then marker.cleanupComplete = nil end
end

-- This owner follows the registered storage provider, including while sound is muted.
if YUI.Event and YUI.Event.On then
    YUI.Event:On('YUI_CONFIG_SETS_CHANGED', 'OnLibraryChanged', Migration,
        { moduleId = 'sound.legacy-migration' })
end
S.LegacyMigration:RegisterProvider('yhud', Migration)
local Transfer = YUI.Settings.ConfigTransfer
if Transfer and Transfer.RegisterModule then
    local imports = setmetatable({}, {__mode='k'})
    local function NormalizeImported(payload)
        if type(payload) ~= 'table' or type(payload.records) ~= 'table' or #payload.records > 4096 then return nil, 'invalid-legacy-record' end
        for key in pairs(payload) do if key ~= 'records' then return nil, 'invalid-legacy-record' end end
        local known = {}; for _, spec in ipairs(YHUD:GetSupportedSpecKeys()) do known[spec] = true end
        local records = {}
        for index, record in pairs(payload.records) do
            if type(index) ~= 'number' or index%1 ~= 0 or index<1 or index>#payload.records
                or type(record) ~= 'table' or not known[record.spec] or type(record.monitorId) ~= 'string'
                or type(record.raw) ~= 'table' or type(record.raw.sound) ~= 'string' then return nil, 'invalid-legacy-record' end
            local condition = type(record.raw.condition) == 'table' and record.raw.condition.type or record.raw.condition
            if type(condition) ~= 'string' then return nil, 'invalid-legacy-record' end
            for _, field in ipairs({'assigned','enabled','hasCharges','independentAura','fixedTimer'}) do
                if record[field] ~= nil and type(record[field]) ~= 'boolean' then return nil,'invalid-legacy-record' end
            end
            if record.duration ~= nil and (type(record.duration) ~= 'number' or record.duration ~= record.duration
                or record.duration <= 0 or record.duration == math.huge) then return nil,'invalid-legacy-record' end
            if record.object ~= nil then
                local object = record.object
                if type(object) ~= 'table' or type(object.kind) ~= 'string' or type(object.id) ~= 'number'
                    or object.id < 1 or object.id == math.huge or object.id % 1 ~= 0
                    or object.unit ~= nil and type(object.unit) ~= 'string' then return nil,'invalid-legacy-record' end
            end
            if record.talents ~= nil and type(record.talents) ~= 'table' then return nil,'invalid-legacy-record' end
            local talentIds = {}
            for id, selected in pairs(record.talents or {}) do
                if type(id) ~= 'number' or id < 1 or id == math.huge or id % 1 ~= 0 or type(selected) ~= 'boolean'
                    or #talentIds >= 32 then return nil,'invalid-legacy-record' end
                talentIds[#talentIds+1] = id
            end
            table.sort(talentIds)
            local copy = YHUD:CopyValue(record)
            copy.assigned, copy.characterMuted, copy.setId = record.assigned == true, nil, 'imported'
            local object = type(copy.object) == 'table' and copy.object or {}
            local identity = {}
            for _, value in ipairs({copy.spec,copy.monitorId,condition,copy.raw.sound,
                tostring(object.kind),tostring(object.id),tostring(object.unit),tostring(copy.hasCharges),tostring(copy.independentAura),
                tostring(copy.fixedTimer),tostring(copy.duration),tostring(copy.enabled),tostring(copy.assigned)}) do
                identity[#identity+1] = #value .. ':' .. value
            end
            for _, id in ipairs(talentIds) do identity[#identity+1] = ':' .. id .. '=' .. tostring(copy.talents[id]) end
            copy.key = 'import:' .. table.concat(identity)
            records[index] = copy
        end
        return {records=records}
    end
    Transfer:RegisterModule({id='core.sound.legacy',kind='core',schemaVersion=1,
        labelKey='sound.center.legacyTitle',hiddenFromProfile=true,selectedByDefault=false,
        exclusiveWith={'core.sound'},clients={retail=true},maxPayloadNodes=65536,
        productId=function() return S.storageProductId end,
        capture=function() return nil,'legacy-import-only' end,normalize=NormalizeImported,
        snapshot=function(_, context, payload)
            if context and context.previewNewProfile then
                local unique, seen = {}, {}
                for _, record in ipairs(payload.records) do
                    if not seen[record.key] then unique[#unique+1]=record; seen[record.key]=true end
                end
                local plan, code=S.LegacyMigration:Prepare(unique,{},'mainline')
                if not plan then return nil,code end
                return {profileName=context.previewNewProfile,converted=#plan.converted,pending=#plan.recovery,
                    unchanged=#payload.records-#unique}
            end
            local db = YUI.DB:GetAceDB(S.storageProductId)
            local before = db.profile[MARKER]
            if before ~= nil and not ValidMarker(before) then return nil,'invalid-legacy-migration-state' end
            local marker = before and YHUD:CopyValue(before) or {
                version=S.LegacyMigration.VERSION,archive={},seen={},suppressed={},recovery={}}
            local records, seen = {}, {}
            for _, record in ipairs(payload.records) do
                if not marker.archive[record.key] and not seen[record.key] then
                    records[#records+1]=record; seen[record.key]=true
                end
            end
            local current, code = S.RuleStore:Read(); if not current then return nil,code end
            local plan; plan, code = S.LegacyMigration:Prepare(records,current,'mainline')
            if not plan then return nil,code end
            for _, record in ipairs(records) do marker.archive[record.key]=YHUD:CopyValue(record) end
            for _, index in ipairs(plan.converted) do marker.seen[records[index].key]=true end
            for _, problem in ipairs(plan.recovery) do marker.recovery[#marker.recovery+1]={key=records[problem.index].key,reason=problem.reason} end
            local staged; staged,code=S.RuleStore:PrepareImport(plan.rules,'replace'); if not staged then return nil,code end
            local token = {}
            local count=0; for _ in pairs(marker.archive) do count=count+1 end
            if count>4096 then return nil,'legacy-record-budget' end
            imports[token]={profile=db.profile,before=before,beforeCopy=YHUD:CopyValue(before),marker=marker,plan=staged}
            return {database=db,profileName=db:GetCurrentProfile(),token=token,
                converted=#plan.converted,pending=#plan.recovery,unchanged=#payload.records-#records}
        end,
        validateSnapshot=function(snapshot)
            local staged=imports[snapshot.token]
            if not staged or staged.profile[MARKER]~=staged.before
                or not Same(staged.profile[MARKER],staged.beforeCopy) then return nil,'stale-preview' end
            return S.RuleStore:CheckPrepared(staged.plan)
        end,
        apply=function(_, entry)
            local staged=imports[entry.snapshot.token]
            if not staged then return nil,'stale-preview' end
            staged.profile[MARKER]=staged.marker
            local called,ok,code=pcall(S.RuleStore.Commit,S.RuleStore,staged.plan,S.Runtime)
            if not called or not ok then staged.profile[MARKER]=staged.before; return nil,called and code or 'legacy-import-failed' end
            staged.applied=true
            return true
        end,
        restore=function(snapshot)
            local staged=imports[snapshot.token]
            if not staged or not staged.applied then return true end
            staged.profile[MARKER]=staged.before
            local ok,code=S.RuleStore:Restore(staged.plan,S.Runtime)
            if not ok then return nil,code end
            staged.applied=nil
            return true
        end})
end
return Migration

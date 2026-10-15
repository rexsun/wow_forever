local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API
local LC = YUI.Locale:Get("Core")

local function BeginImportTrace(name)
    local Trace = YUI.Trace
    if Trace and Trace.Begin then
        return Trace:Begin("Settings", "ConfigTransfer:" .. name, nil, {
            moduleId = "core.profiles",
            durationKind = "sync",
            blocking = true,
        })
    end
end

local function FinishImportTrace(record, status, err)
    local Trace = YUI.Trace
    if record and Trace and Trace.Finish then
        Trace:Finish(record, status or "ok", err)
    end
end

-- ============================================================================
-- 序列化与编码工具 (Serialization & Encoding Tools)
-- ============================================================================
-- Use Standard Libraries
local Serializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

local function SettingsIcon(name)
    local gui = GUI2 or YUI.GUI2
    if gui and gui.GetSettingsIcon then
        return gui:GetSettingsIcon(name)
    end
    return nil
end

-- ============================================================================
-- 逻辑处理 (Logic)
-- ============================================================================

local function GetActiveProductId()
    local productId = S.ActiveProductId
    if type(productId) ~= "string" or productId == "" then
        productId = (YUI.DB and YUI.DB.activeProductId) or YUI.ProductId or "suite"
    end
    local product = YUI.Products and YUI.Products[productId]
    if (not product or not (product.settings and product.settings.enabled == true)) and S.GetDefaultProductId then
        productId = S:GetDefaultProductId()
    end
    return productId
end

local function GetActiveDB()
    if YUI.DB and YUI.DB.GetAceDB then
        return YUI.DB:GetAceDB(GetActiveProductId())
    end
    return YUI.db
end

local function GetConfigSets()
    return YUI.Settings and YUI.Settings.ConfigSets or nil
end

local function PrintConfigSetsError(code)
    local key = "settings.config_sets.error." .. tostring(code or "provider_error")
    YUI:Print(
        LC[key]
            or LC["settings.config_sets.error.provider_error"]
            or "Configuration set operation failed."
    )
end

local function DeleteConfigSetsProfileState(profileName)
    local ConfigSets = GetConfigSets()
    if not (ConfigSets and ConfigSets.DeleteProfileState) then return true end
    local ok, code = ConfigSets:DeleteProfileState(
        GetActiveProductId(),
        profileName
    )
    if not ok then PrintConfigSetsError(code) end
    return ok == true
end

local function GetActiveProductTitle()
    local productId = GetActiveProductId()
    local product = YUI.Products and YUI.Products[productId]
    if YUI.GetProductShortTitle then
        return YUI:GetProductShortTitle(product or productId)
    end
    if YUI.GetProductTitle then
        return YUI:GetProductTitle(product or productId)
    end
    return product and (product.title or product.id) or "YUI"
end

local function GetActiveProduct()
    if YUI.DB and YUI.DB.GetProduct then
        return YUI.DB:GetProduct(GetActiveProductId())
    end
    return YUI.Products and YUI.Products[GetActiveProductId()]
end

local function GetActiveSavedVariableName()
    local product = GetActiveProduct()
    return product and product.db and product.db.savedVariable or nil
end

local ResolveSavedVariablesTable

local function GetNamedSavedVariables(savedVariableName)
    if savedVariableName and _G and type(_G[savedVariableName]) == "table" then
        return _G[savedVariableName]
    end
    return nil
end

local function AddProfileName(list, seen, name)
    if not name or name == "" or seen[name] then
        return
    end

    seen[name] = true
    table.insert(list, { text = name, value = name })
end

local function GetProfileList(db, savedVariableName)
    local list = {}
    local seen = {}

    local sv = ResolveSavedVariablesTable and ResolveSavedVariablesTable(db, savedVariableName) or (db and db.sv)
    if sv and type(sv.profiles) == "table" then
        for name in pairs(sv.profiles) do
            AddProfileName(list, seen, name)
        end
    end

    if db and type(db.GetProfiles) == "function" then
        for _, name in ipairs(db:GetProfiles()) do
            AddProfileName(list, seen, name)
        end
    end

    table.sort(list, function(a, b)
        return tostring(a.text or "") < tostring(b.text or "")
    end)
    return list
end

local function ProfileExists(db, savedVariableName, profileName)
    if not profileName or profileName == "" then
        return false
    end

    local sv = ResolveSavedVariablesTable and ResolveSavedVariablesTable(db, savedVariableName) or nil
    if sv and type(sv.profiles) == "table" and type(sv.profiles[profileName]) == "table" then
        return true
    end

    if db and type(db.GetProfiles) == "function" then
        for _, name in ipairs(db:GetProfiles()) do
            if name == profileName then
                return true
            end
        end
    end

    return false
end

local function CountProfiles(db, savedVariableName)
    local count = 0
    local profiles = GetProfileList(db, savedVariableName)
    for _ in ipairs(profiles) do
        count = count + 1
    end
    return count
end

local function FindFallbackProfile(db, savedVariableName, excludeProfile)
    local profiles = GetProfileList(db, savedVariableName)
    for _, option in ipairs(profiles) do
        if option.value and option.value ~= excludeProfile then
            return option.value
        end
    end
    return "Default"
end

local selectedProfile = nil
local newProfileName = ""
local PROFILE_PREFIX_LEGACY = "!YUI:"
local PROFILE_PREFIX_V2 = "!YUI-v2:"

local function AddProfileStringPrefix(prefixes, seen, prefix)
    if type(prefix) ~= "string" or prefix == "" or seen[prefix] then
        return
    end
    seen[prefix] = true
    prefixes[#prefixes + 1] = prefix
end

local function GetKnownProfileStringPrefixes()
    local prefixes = {}
    local seen = {}
    if YUI.Products then
        for _, product in pairs(YUI.Products) do
            AddProfileStringPrefix(prefixes, seen, product.profileExportPrefix)
        end
    end
    AddProfileStringPrefix(prefixes, seen, PROFILE_PREFIX_V2)
    AddProfileStringPrefix(prefixes, seen, PROFILE_PREFIX_LEGACY)
    return prefixes
end

local function GetProfileStringPrefix(value)
    value = tostring(value or "")
    for _, prefix in ipairs(GetKnownProfileStringPrefixes()) do
        if value:sub(1, #prefix) == prefix then
            return prefix
        end
    end
    return nil
end

local function IsModernProfilePrefix(prefix)
    return prefix and prefix ~= PROFILE_PREFIX_LEGACY
end

local function DeepCopy(source, dest)
    if type(source) ~= "table" or type(dest) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            dest[key] = {}
            DeepCopy(value, dest[key])
        else
            dest[key] = value
        end
    end
end

local function GetCharacterProfileKey(db)
    return YUI.Player:GetCharacterKey(db and db.keys and db.keys.char or nil)
end

local function EnsureProfileKeys(sv)
    if type(sv) ~= "table" then
        return nil
    end
    if type(sv.profileKeys) ~= "table" then
        sv.profileKeys = {}
    end
    return sv.profileKeys
end

local function ResolveSavedProfileName(sv, charKey)
    if not charKey or charKey == "" or type(sv) ~= "table" or type(sv.profiles) ~= "table" then
        return nil
    end

    local profileKeys = EnsureProfileKeys(sv)
    local profileName = profileKeys and profileKeys[charKey] or nil
    if profileName and type(sv.profiles[profileName]) == "table" then
        return profileName
    end

    local legacyProfileName = type(sv.yuiProfileKeys) == "table" and sv.yuiProfileKeys[charKey] or nil
    if legacyProfileName and type(sv.profiles[legacyProfileName]) == "table" and profileKeys then
        profileKeys[charKey] = legacyProfileName
        return legacyProfileName
    end

    return nil
end

function ResolveSavedVariablesTable(db, savedVariableName)
    local namedSV = GetNamedSavedVariables(savedVariableName)
    if namedSV and type(db) == "table" and type(db.sv) == "table" and db.sv ~= namedSV then
        return namedSV
    end

    if type(db) == "table" and type(db.sv) == "table" then
        return db.sv
    end

    return namedSV
end

local function GetSavedProfileName(db, savedVariableName)
    local sv = ResolveSavedVariablesTable(db, savedVariableName)
    local charKey = GetCharacterProfileKey(db)
    return ResolveSavedProfileName(sv, charKey)
end

local function GetCurrentProfileName(db, savedVariableName)
    return GetSavedProfileName(db, savedVariableName)
        or (db and type(db.GetCurrentProfile) == "function" and db:GetCurrentProfile())
        or LC["settings.profiles.unknown"]
end

local function WriteProfileToSavedVariables(sv, profileName, source, copySource)
    if type(sv) ~= "table" or not profileName or profileName == "" then
        return nil
    end

    if type(sv.profiles) ~= "table" then
        sv.profiles = {}
    end

    if copySource then
        sv.profiles[profileName] = {}
        DeepCopy(source or {}, sv.profiles[profileName])
    elseif type(source) == "table" then
        sv.profiles[profileName] = source
    elseif type(sv.profiles[profileName]) ~= "table" then
        sv.profiles[profileName] = {}
    end

    return sv.profiles[profileName]
end

local function RepairActiveProfileFromSavedVariables(db, savedVariableName)
    if type(db) ~= "table" or type(db.GetCurrentProfile) ~= "function" or type(db.SetProfile) ~= "function" then
        return false
    end

    local charKey = GetCharacterProfileKey(db)
    local sv = ResolveSavedVariablesTable(db, savedVariableName)
    if not charKey or charKey == "" or type(sv) ~= "table" or type(sv.profiles) ~= "table" then
        return false
    end

    local storedProfile = ResolveSavedProfileName(sv, charKey)
    if not storedProfile then
        return false
    end

    db.profiles = sv.profiles
    if db:GetCurrentProfile() ~= storedProfile then
        db:SetProfile(storedProfile)
    end
    return true
end

local function SwitchToProfile(db, profileName, savedVariableName)
    if type(db) ~= "table" or not profileName or profileName == "" or type(db.SetProfile) ~= "function" then
        return false
    end

    local sv = ResolveSavedVariablesTable(db, savedVariableName)
    if type(sv) == "table" and type(sv.profiles) == "table" and type(sv.profiles[profileName]) == "table" then
        db.profiles = sv.profiles
    end

    if YUI.DB and type(YUI.DB.SwitchProfile) == "function" then
        if type(sv) ~= "table" then return false end
        WriteProfileToSavedVariables(sv, profileName, nil, false)
        return YUI.DB:SwitchProfile(db, profileName) == true
    end

    db:SetProfile(profileName)
    if YUI.DB and YUI.DB.PersistCurrentProfile then
        YUI.DB:PersistCurrentProfile(db, savedVariableName)
    end
    return db:GetCurrentProfile() == profileName
end

local function SaveProfileBeforeSwitch(db, profileName, source, savedVariableName, afterSwitch)
    if not db or not profileName or profileName == "" then
        return false, "missing profile target"
    end

    local sv = ResolveSavedVariablesTable(db, savedVariableName)
    if type(sv) ~= "table" then
        return false, "missing SavedVariables table"
    end
    if type(db.SetProfile) ~= "function" then
        return false, "missing AceDB SetProfile"
    end

    local originalName, originalProfile = db:GetCurrentProfile(), db.profile
    local originalProfiles, originalDBProfiles = sv.profiles, db.profiles
    local originalTarget = originalProfiles and originalProfiles[profileName]
    local function RefreshSameProfile(value)
        db.profile = nil
        -- AceDB lazily binds the new stored table and applies its defaults.
        if db.profile == nil then db.profile = value end
        if db.callbacks and db.callbacks.Fire then db.callbacks:Fire('OnProfileChanged', db, originalName) end
    end
    local mappings = {}
    for _, key in ipairs({ 'profileKeys', 'yuiProfileKeys' }) do
        local value, copy = sv[key], {}
        if type(value) == 'table' then for k, v in pairs(value) do copy[k] = v end end
        mappings[key] = { value = value, copy = copy }
    end
    local ok, result, code = pcall(function()
        -- Finish copying before replacing even the target table reference.
        local copied = {}; DeepCopy(source or {}, copied)
        if profileName == originalName and db.callbacks and db.callbacks.Fire then
            db.callbacks:Fire('OnProfileShutdown', db)
        end
        WriteProfileToSavedVariables(sv, profileName, copied, false)
        db.profiles = sv.profiles
        if profileName == originalName then
            RefreshSameProfile(copied)
        elseif YUI.DB and type(YUI.DB.SwitchProfile) == "function" then
            local switched, switchCode = YUI.DB:SwitchProfile(db, profileName)
            if not switched then return false, switchCode end
        else
            db:SetProfile(profileName)
        end
        if YUI.DB and YUI.DB.PersistCurrentProfile then YUI.DB:PersistCurrentProfile(db, savedVariableName) end
        if db:GetCurrentProfile() ~= profileName then return false, 'AceDB current profile mismatch' end
        if type(sv.profiles[profileName]) ~= 'table' then return false, 'profile table was not saved' end
        if db.profile ~= sv.profiles[profileName] then return false, 'AceDB active profile binding mismatch' end
        if afterSwitch then return afterSwitch() end
        return true
    end)
    if not ok or result ~= true then
        -- Restore through AceDB so consumers also return to the original profile.
        -- Restore the target after shutdown callbacks have finished saving it.
        local restored = pcall(function()
            db.profiles = originalProfiles or originalDBProfiles
            if originalProfiles then originalProfiles[originalName] = originalProfile end
            if db:GetCurrentProfile() ~= originalName then
                if YUI.DB and type(YUI.DB.SwitchProfile) == "function" then
                    local switched, switchCode = YUI.DB:SwitchProfile(db, originalName)
                    if not switched then error(switchCode or 'profile_rollback_failed') end
                else
                    db:SetProfile(originalName)
                end
            elseif db.profile ~= originalProfile then RefreshSameProfile(originalProfile) end
        end)
        if originalProfiles then originalProfiles[profileName] = originalTarget end
        sv.profiles, db.profiles = originalProfiles, originalDBProfiles
        for key, mapping in pairs(mappings) do
            if type(mapping.value) == 'table' then
                for k in pairs(mapping.value) do mapping.value[k] = nil end
                for k, v in pairs(mapping.copy) do mapping.value[k] = v end
            end
            sv[key] = mapping.value
        end
        if not restored or db:GetCurrentProfile() ~= originalName or db.profile ~= originalProfile then
            return false, 'profile_rollback_failed'
        end
        return false, ok and code or result
    end
    return true
end

local function TrimProfileName(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function ImportFailureDetail(phase, moduleId, reason, source)
    local detail = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        detail[key] = value
    end
    detail.phase = detail.phase or phase
    detail.moduleId = detail.moduleId or moduleId
    detail.reason = detail.reason or reason
    return detail
end

local function RestoredImportFailure(phase, moduleId, reason, source)
    local detail = ImportFailureDetail(phase, moduleId, reason, source)
    -- Restoring the profile does not repair a failed account-data participant.
    detail.profileRestored = true
    if detail.rollbackRestored ~= false then detail.rollbackRestored = true end
    return detail
end

local function RollbackImportFailure(originalCode, originalDetail, rollbackReason, moduleId)
    originalDetail = type(originalDetail) == "table" and originalDetail or {}
    return ImportFailureDetail("rollback", moduleId or originalDetail.moduleId, rollbackReason, {
        rollbackRestored = false,
        originalCode = originalCode,
        originalPhase = originalDetail.phase,
        originalModuleId = originalDetail.moduleId,
        originalReason = originalDetail.reason,
    })
end

local function RestoreNewImportProfile(db, savedVariableName, originalProfile, targetProfile)
    if not SwitchToProfile(db, originalProfile, savedVariableName) then
        return nil, "rollback_failed", "profile_switch_failed"
    end
    local ConfigSets = GetConfigSets()
    if ConfigSets and ConfigSets.DeleteProfileState then
        local deleted, deleteCode, deleteDetail = ConfigSets:DeleteProfileState(
            GetActiveProductId(),
            targetProfile
        )
        if not deleted then
            return nil, "rollback_failed", deleteDetail or deleteCode or "profile_state_delete_failed"
        end
    end
    if type(db.DeleteProfile) ~= "function" then
        return nil, "rollback_failed", "profile_delete_unavailable"
    end
    db:DeleteProfile(targetProfile)
    return true
end

local function RollbackNewImportProfile(...)
    local called, restored, code, reason = pcall(RestoreNewImportProfile, ...)
    if not called then return nil, "rollback_failed", restored end
    return restored, code, reason
end

local function ImportModularPackageBody(parsed, moduleIds, target, owner, context)
    local Transfer = S.ConfigTransfer
    local db = GetActiveDB()
    local savedVariableName = GetActiveSavedVariableName()
    if not (Transfer and db) then
        return nil, "profile_unavailable", ImportFailureDetail(
            "profile",
            nil,
            "profile_unavailable"
        )
    end

    target = type(target) == "table" and target or {}
    if target.mode ~= "new" then
        local expectedProfile = TrimProfileName(target.profileName)
        if expectedProfile ~= ""
            and GetCurrentProfileName(db, savedVariableName) ~= expectedProfile then
            return nil, "profile_changed", ImportFailureDetail("profile", nil, "profile_changed")
        end
        local prepared, code, diagnostic = Transfer:PrepareImport(parsed, moduleIds, context)
        if not prepared then
            return nil, code, ImportFailureDetail("prepare", nil, code, diagnostic)
        end
        return Transfer:CommitImport(prepared, owner)
    end

    local targetProfile = TrimProfileName(target.profileName)
    if targetProfile == "" then
        return nil, "profile_name_required", ImportFailureDetail(
            "profile",
            nil,
            "profile_name_required"
        )
    end
    if ProfileExists(db, savedVariableName, targetProfile) then
        return nil, "profile_exists", ImportFailureDetail("profile", nil, "profile_exists")
    end

    local newContext = {}
    for key, value in pairs(context or {}) do newContext[key] = value end
    newContext.importNewProfile = targetProfile
    context = newContext

    local originalProfile = GetCurrentProfileName(db, savedVariableName)
    if not SwitchToProfile(db, targetProfile, savedVariableName) then
        local diagnostic = ImportFailureDetail("profile", nil, "profile_switch_failed")
        local rolledBack, rollbackCode, rollbackReason = RollbackNewImportProfile(
            db, savedVariableName, originalProfile, targetProfile
        )
        if rolledBack then
            return nil, "profile_switch_failed", RestoredImportFailure(
                "profile", nil, "profile_switch_failed", diagnostic
            )
        end
        return nil, rollbackCode, RollbackImportFailure(
            "profile_switch_failed", diagnostic, rollbackReason
        )
    end
    if type(db.ResetProfile) == "function" then db:ResetProfile() end

    local ConfigSets = GetConfigSets()
    if ConfigSets and ConfigSets.ResetProfileState then
        local reset, resetCode, resetDetail = ConfigSets:ResetProfileState(
            GetActiveProductId(),
            targetProfile
        )
        if not reset then
            local originalDetail = ImportFailureDetail(
                "profile",
                nil,
                resetDetail or resetCode
            )
            local rolledBack, rollbackCode, rollbackReason = RollbackNewImportProfile(
                db,
                savedVariableName,
                originalProfile,
                targetProfile
            )
            if rolledBack then
                return nil, resetCode, RestoredImportFailure(
                    "profile",
                    nil,
                    resetDetail or resetCode,
                    originalDetail
                )
            end
            return nil, rollbackCode, RollbackImportFailure(
                resetCode,
                originalDetail,
                rollbackReason
            )
        end
    end

    local prepared, code, diagnostic = Transfer:PrepareImport(parsed, moduleIds, context)
    if not prepared then
        diagnostic = ImportFailureDetail("prepare", nil, code, diagnostic)
        local rolledBack, rollbackCode, rollbackReason = RollbackNewImportProfile(
            db,
            savedVariableName,
            originalProfile,
            targetProfile
        )
        if rolledBack then
            return nil, code, RestoredImportFailure("prepare", nil, code, diagnostic)
        end
        return nil, rollbackCode, RollbackImportFailure(
            code,
            diagnostic,
            rollbackReason
        )
    end

    local committed, detail, diagnostic = Transfer:CommitImport(prepared, owner)
    if not committed then
        diagnostic = ImportFailureDetail("commit", nil, detail, diagnostic)
        local rolledBack, rollbackCode, rollbackReason = RollbackNewImportProfile(
            db,
            savedVariableName,
            originalProfile,
            targetProfile
        )
        if rolledBack then
            return nil, detail, RestoredImportFailure("commit", nil, detail, diagnostic)
        end
        return nil, rollbackCode, RollbackImportFailure(
            detail,
            diagnostic,
            rollbackReason
        )
    end

    selectedProfile = targetProfile
    return true, detail
end

local function ImportModularPackage(parsed, moduleIds, target, owner, context)
    local Transfer, session = S.ConfigTransfer
    local db = GetActiveDB()
    local savedVariableName = GetActiveSavedVariableName()
    local originalProfile = db and GetCurrentProfileName(db, savedVariableName)
    local targetProfile = type(target) == "table" and TrimProfileName(target.profileName) or ""
    local canRestoreNew = db and type(target) == "table" and target.mode == "new"
        and targetProfile ~= "" and not ProfileExists(db, savedVariableName, targetProfile)
    if Transfer and Transfer.BeginImportSession then
        local code
        session, code = Transfer:BeginImportSession(moduleIds)
        if not session then return nil, code, ImportFailureDetail("prepare", nil, code, { writesStarted = false }) end
    end
    local called, ok, detail, diagnostic = pcall(ImportModularPackageBody, parsed, moduleIds, target, owner, context)
    if not called then
        local reason = ok
        if canRestoreNew and ProfileExists(db, savedVariableName, targetProfile) then
            local restored, _, rollbackReason = RollbackNewImportProfile(db, savedVariableName, originalProfile, targetProfile)
            detail = restored and "import_failed" or "rollback_failed"
            diagnostic = ImportFailureDetail(restored and "commit" or "rollback", nil, rollbackReason or reason, {
                rollbackRestored = restored == true,
                originalCode = "import_failed", originalReason = reason,
            })
        else
            detail = "import_failed"
            diagnostic = ImportFailureDetail("commit", nil, reason, { rollbackRestored = false })
        end
        ok = nil
    end
    if session then Transfer:EndImportSession(session) end
    return ok, detail, diagnostic
end

local function StartImportModularPackage(
    parsed,
    moduleIds,
    target,
    owner,
    context,
    callbacks
)
    local Transfer = S.ConfigTransfer
    local db = GetActiveDB()
    local savedVariableName = GetActiveSavedVariableName()
    callbacks = type(callbacks) == "table" and callbacks or {}
    target = type(target) == "table" and target or {}

    local handle = {
        state = "profile",
        finished = false,
        targetCreated = false,
    }
    local Begin
    local originalContext = context

    local function EmitProgress(detail)
        if handle.finished then return end
        if type(detail.progress) == 'number' then
            detail.progress = math.max(handle.progress or 0, detail.progress)
            handle.progress = detail.progress
        end
        local callback = callbacks.onProgress
        if type(callback) == "function" then pcall(callback, detail) end
    end

    local function Cleanup()
        if handle.timer and handle.timer.Cancel then handle.timer:Cancel() end
        handle.timer = nil
        handle.prepareJob = nil
        handle.prepared = nil
        handle.reviewedPrepared = nil
        if handle.importSession then
            Transfer:EndImportSession(handle.importSession)
            handle.importSession = nil
        end
    end

    local function Finish(ok, detail, diagnostic, phase)
        if handle.finished then return false end
        handle.finished = true
        Cleanup()
        local callback = callbacks.onComplete
        callbacks = nil
        if type(callback) == "function" then
            pcall(callback, ok, detail, diagnostic, phase)
        end
        return true
    end

    local function RollbackFailure(code, diagnostic, phase)
        diagnostic = ImportFailureDetail(phase, nil, code, diagnostic)
        if not handle.targetCreated then
            if phase == "prepare" or phase == "review" then diagnostic.writesStarted = false end
            return Finish(nil, code, diagnostic, phase)
        end
        local rolledBack, rollbackCode, rollbackReason = RollbackNewImportProfile(
            db,
            savedVariableName,
            handle.originalProfile,
            handle.targetProfile
        )
        handle.targetCreated = false
        if rolledBack then
            return Finish(
                nil,
                code,
                RestoredImportFailure(phase, nil, code, diagnostic),
                phase
            )
        end
        return Finish(
            nil,
            rollbackCode,
            RollbackImportFailure(code, diagnostic, rollbackReason),
            "rollback"
        )
    end

    local function Schedule(callback)
        if handle.finished then return end
        local function Run()
            if handle.finished then return end
            local called, reason = pcall(callback)
            if not called then
                local phase = handle.state == "committing" and "commit" or "prepare"
                local diagnostic = ImportFailureDetail(phase, nil, reason)
                if phase == "commit" then diagnostic.rollbackRestored = false end
                RollbackFailure("import_failed", diagnostic, phase)
            end
        end
        if C_Timer and C_Timer.NewTimer then
            handle.timer = C_Timer.NewTimer(0, function()
                handle.timer = nil
                Run()
            end)
        else
            Run()
        end
    end

    local function CommitPrepared()
        if handle.finished then return end
        handle.state = "committing"
        EmitProgress({ phase = "commit", progress = 0.92 })
        local committed, detail, diagnostic = Transfer:CommitImport(
            handle.prepared,
            owner
        )
        handle.prepared = nil
        if not committed then
            return RollbackFailure(detail, diagnostic, "commit")
        end
        if handle.targetCreated then selectedProfile = handle.targetProfile end
        handle.targetCreated = false
        EmitProgress({ phase = "import-complete", progress = 1 })
        return Finish(true, detail, nil, "commit")
    end

    local function Prepared(prepared, code, diagnostic)
        handle.prepareJob = nil
        if handle.finished then return end
        if not prepared then
            return RollbackFailure(code, diagnostic, "prepare")
        end
        handle.prepared = prepared
        if handle.reviewAccepted and Transfer.MatchesNewProfilePreview then
            local matches, mismatch = Transfer:MatchesNewProfilePreview(handle.reviewedPrepared, prepared)
            if not matches then return RollbackFailure('stale_preview', mismatch, 'prepare') end
        end
        local function Accept()
            if handle.finished or handle.state=='commit-pending' or handle.state=='committing' then return end
            handle.state = 'commit-pending'
            if handle.previewingNew then
                handle.previewingNew, handle.reviewAccepted = false, true
                handle.reviewedPrepared = handle.prepared
                handle.prepared = nil
                context = originalContext
                return Schedule(Begin)
            end
            EmitProgress({phase='commit',progress=0.90})
            Schedule(CommitPrepared)
        end
        if type(callbacks.onPrepared)=='function' and not handle.reviewAccepted then
            handle.state='review'
            local called=pcall(callbacks.onPrepared,prepared,Accept,function()
                if not handle.finished then RollbackFailure('review_canceled',nil,'review') end
            end)
            if not called then RollbackFailure('review_failed',nil,'review') end
        else Accept() end
    end

    local function StartPrepare()
        if handle.finished then return end
        handle.state = "preparing"
        if type(Transfer.StartPrepareImport) == "function" then
            local job = Transfer:StartPrepareImport(
                parsed,
                moduleIds,
                context,
                {
                    onProgress = function(detail)
                        if handle.finished then return end
                        detail = type(detail) == "table" and detail or {}
                        EmitProgress({
                            phase = detail.phase,
                            progress = 0.08 + (0.80 * math.max(
                                0,
                                math.min(tonumber(detail.progress) or 0, 1)
                            )),
                            processedNodes = detail.processedNodes,
                            moduleIndex = detail.moduleIndex,
                            moduleCount = detail.moduleCount,
                        })
                    end,
                    onComplete = function(...)
                        local called, reason = pcall(Prepared, ...)
                        if not called then
                            RollbackFailure("import_failed", ImportFailureDetail("prepare", nil, reason), "prepare")
                        end
                    end,
                }
            )
            if handle.finished then
                if job and job.Cancel then job:Cancel() end
            else
                handle.prepareJob = job
            end
            return
        end
        Schedule(function()
            Prepared(Transfer:PrepareImport(parsed, moduleIds, context))
        end)
    end

    local function AcquireImportSession()
        if handle.finished then return false end
        if handle.importSession or not Transfer.BeginImportSession then return true end
        local code
        handle.importSession, code = Transfer:BeginImportSession(moduleIds)
        if not handle.importSession then
            Finish(nil, code, ImportFailureDetail("prepare", nil, code, { writesStarted = false }), "prepare")
            return false
        end
        return true
    end

    Begin = function()
        if not (Transfer and db) then
            return Finish(
                nil,
                "profile_unavailable",
                ImportFailureDetail("profile", nil, "profile_unavailable"),
                "profile"
            )
        end
        EmitProgress({ phase = "profile", progress = 0.02 })
        if handle.finished then return end
        if target.mode ~= "new" then
            local expectedProfile = TrimProfileName(target.profileName)
            if expectedProfile ~= ""
                and GetCurrentProfileName(db, savedVariableName) ~= expectedProfile then
                return Finish(
                    nil,
                    "profile_changed",
                    ImportFailureDetail("profile", nil, "profile_changed"),
                    "profile"
                )
            end
            if AcquireImportSession() then return StartPrepare() end
            return
        end

        local targetProfile = TrimProfileName(target.profileName)
        if targetProfile == "" then
            return Finish(
                nil,
                "profile_name_required",
                ImportFailureDetail("profile", nil, "profile_name_required"),
                "profile"
            )
        end
        if ProfileExists(db, savedVariableName, targetProfile) then
            return Finish(
                nil,
                "profile_exists",
                ImportFailureDetail("profile", nil, "profile_exists"),
                "profile"
            )
        end

        local currentProfile = GetCurrentProfileName(db, savedVariableName)
        if handle.reviewAccepted and (currentProfile ~= handle.originalProfile or targetProfile ~= handle.targetProfile) then
            return Finish(nil,'profile_changed',ImportFailureDetail('profile',nil,'profile_changed'),'profile')
        end
        handle.originalProfile = currentProfile
        handle.targetProfile = targetProfile
        context = {}
        for key, value in pairs(originalContext or {}) do context[key] = value end
        context.importNewProfile = targetProfile
        if type(callbacks.onPrepared)=='function' and not handle.reviewAccepted then
            context.previewNewProfile = targetProfile
            handle.previewingNew = true
            return StartPrepare()
        end
        if not AcquireImportSession() then return end
        local sv = ResolveSavedVariablesTable(db, savedVariableName)
        if type(sv) ~= "table" then
            return Finish(
                nil,
                "profile_unavailable",
                ImportFailureDetail("profile", nil, "profile_unavailable"),
                "profile"
            )
        end
        WriteProfileToSavedVariables(sv, targetProfile, {}, false)
        handle.targetCreated = true
        local ConfigSets = GetConfigSets()
        if ConfigSets and ConfigSets.ResetProfileState then
            local resetTrace = BeginImportTrace("profile-config-sets-reset")
            local reset, resetCode, resetDetail = ConfigSets:ResetProfileState(
                GetActiveProductId(),
                targetProfile
            )
            FinishImportTrace(
                resetTrace,
                reset and "ok" or "error",
                reset and nil or (resetDetail or resetCode)
            )
            if not reset then
                return RollbackFailure(
                    resetCode,
                    ImportFailureDetail("profile", nil, resetDetail or resetCode),
                    "profile"
                )
            end
        end
        local switchTrace = BeginImportTrace("profile-switch")
        local switched = SwitchToProfile(db, targetProfile, savedVariableName)
        FinishImportTrace(
            switchTrace,
            switched and "ok" or "error",
            switched and nil or "profile_switch_failed"
        )
        if not switched then
            return RollbackFailure(
                "profile_switch_failed",
                ImportFailureDetail("profile", nil, "profile_switch_failed"),
                "profile"
            )
        end
        EmitProgress({ phase = "profile", progress = 0.08 })
        StartPrepare()
    end

    function handle:Cancel()
        if self.finished or self.state == "committing" then return false end
        if self.timer and self.timer.Cancel then self.timer:Cancel() end
        self.timer = nil
        if self.prepareJob and self.prepareJob.Cancel then self.prepareJob:Cancel() end
        self.prepareJob = nil
        if self.targetCreated then
            local rolledBack, rollbackCode, rollbackReason = RollbackNewImportProfile(
                db,
                savedVariableName,
                self.originalProfile,
                self.targetProfile
            )
            self.targetCreated = false
            if not rolledBack then
                Finish(
                    nil,
                    rollbackCode,
                    RollbackImportFailure("cancelled", nil, rollbackReason),
                    "rollback"
                )
                return nil, rollbackCode
            end
        end
        self.finished = true
        Cleanup()
        callbacks = nil
        return true
    end

    EmitProgress({ phase = "profile", progress = 0 })
    Schedule(Begin)
    return handle
end

local function IsLegacyProfileString(value)
    value = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
    return GetProfileStringPrefix(value) ~= nil
end

local function ImportLegacyProfileString(value, profileName)
    local db = GetActiveDB()
    local savedVariableName = GetActiveSavedVariableName()
    profileName = type(profileName) == "string" and profileName:match("^%s*(.-)%s*$") or ""
    if not db or profileName == "" then
        YUI:Print(LC["settings.profiles.enter_import_profile_name"])
        return false
    end
    if ProfileExists(db, savedVariableName, profileName) then
        YUI:Print(string.format(LC["settings.profiles.profile_exists"], profileName))
        return false
    end
    local cleanStr = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
    local profilePrefix = GetProfileStringPrefix(cleanStr)
    if not profilePrefix then
        YUI:Print(LC["settings.profiles.invalid_profile_string"])
        return false
    end
    local encodedData = string.sub(cleanStr, #profilePrefix + 1)
    local compressed = LibDeflate:DecodeForPrint(encodedData)
    if not compressed then YUI:Print(LC["settings.profiles.decode_failed"]); return false end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then YUI:Print(LC["settings.profiles.decompress_failed"]); return false end
    local success, tableData = Serializer:Deserialize(serialized)
    if not success or type(tableData) ~= "table" then
        YUI:Print(LC["settings.profiles.deserialize_failed"])
        return false
    end
    local profileData, importInfo
    if YUI.DB and YUI.DB.NormalizeImportedProfile then
        profileData, importInfo = YUI.DB:NormalizeImportedProfile(tableData, profilePrefix)
    elseif IsModernProfilePrefix(profilePrefix) and type(tableData.profile) == "table" then
        profileData, importInfo = tableData.profile, { legacy = false }
    elseif profilePrefix == PROFILE_PREFIX_LEGACY then
        profileData, importInfo = tableData, { legacy = true }
    end
    if type(profileData) ~= "table" then
        YUI:Print(LC["settings.profiles.deserialize_failed"])
        return false
    end
    local preparedProfileState
    local importedProfileState = IsModernProfilePrefix(profilePrefix)
        and tableData.schema == 2 and tableData.configSets or nil
    local ConfigSets = GetConfigSets()
    if importedProfileState ~= nil then
        if not (ConfigSets and ConfigSets.PrepareProfileStateImport) then
            PrintConfigSetsError("unavailable")
            return false
        end
        local prepareCode
        preparedProfileState, prepareCode = ConfigSets:PrepareProfileStateImport(
            GetActiveProductId(), profileName, importedProfileState
        )
        if not preparedProfileState then
            PrintConfigSetsError(prepareCode)
            return false
        end
    end
    local confirmKey = importInfo and importInfo.legacy
        and "settings.profiles.confirm_import_legacy" or "settings.profiles.confirm_import"
    local confirmText = string.format(LC[confirmKey] or LC["settings.profiles.confirm_import"], profileName)
    S:ShowConfirmPopup(confirmText, function()
        if preparedProfileState and ConfigSets.ValidateProfileStateImport then
            local valid, code = ConfigSets:ValidateProfileStateImport(preparedProfileState)
            if not valid then PrintConfigSetsError(code); return end
        end
        local ok, err = SaveProfileBeforeSwitch(db, profileName, profileData, savedVariableName, function()
            if preparedProfileState then return ConfigSets:CommitProfileStateImport(preparedProfileState) end
            if ConfigSets and ConfigSets.ResetProfileState then
                return ConfigSets:ResetProfileState(GetActiveProductId(), profileName)
            end
            return true
        end)
        if not ok then
            YUI:Print("配置文件保存失败: " .. tostring(err or profileName))
            return
        end
        FrameAPI.ReloadUI()
    end)
    return true
end

local function Render(parent)
    local db = GetActiveDB()
    local savedVariableName = GetActiveSavedVariableName()
    if db then
        RepairActiveProfileFromSavedVariables(db, savedVariableName)
    end
    local currentProfileName = db and GetCurrentProfileName(db, savedVariableName) or LC["settings.profiles.unknown"]
    
    -- 手动刷新界面的辅助函数
    local function RefreshUI()
        S:ClearConfig(parent)
        Render(parent)
    end
    
    -- Sync selected profile with current if not set
    if db then
        selectedProfile = currentProfileName
    end
    
    local profileNameWidth = 160
    local config = {
        -- 标题
        { type = "header", label = GetActiveProductTitle() .. " " .. LC["settings.profiles.title"] },

        -- 当前配置文件
        { 
            type = "text", 
            label = string.format(LC["settings.profiles.current_profile"], currentProfileName),
            fontSize = 14,
            width = 600 -- Ensure height calculation if text wraps
        },

        { type = "space", height = 10 },

        -- --- 分割线：配置管理 ---
        { type = "divider", label = LC["settings.profiles.management"], alignLeft = true, width = 600 },
        { type = "row", children = {
            { type = "text", label = LC["settings.profiles.select_profile"], width = 100 },
            { 
                type = "dropdown", 
                width = profileNameWidth,
                options = GetProfileList(db, savedVariableName),
                get = function() return selectedProfile end,
                set = function(val) selectedProfile = val end,
            },
            {
                type = "button",
                label = LC["settings.profiles.load_profile"],
                width = 80,
                onClick = function()
                    if not db or not selectedProfile then return end
                    S:ShowConfirmPopup(string.format(LC["settings.profiles.confirm_load"], selectedProfile), function()
                        SwitchToProfile(db, selectedProfile, savedVariableName)
                        FrameAPI.ReloadUI()
                    end)
                end
            },
            {
                type = "button",
                label = LC["settings.profiles.delete_profile"],
                width = 104,
                icon = SettingsIcon("trash-2"),
                iconSize = 14,
                iconCrop = false,
                contentAlign = "center",
                onClick = function()
                    if not db or not selectedProfile then return end
                    
                    local currentProfile = GetCurrentProfileName(db, savedVariableName)
                    
                    -- Pre-check for last profile
                    if selectedProfile == currentProfile then
                        if CountProfiles(db, savedVariableName) <= 1 then
                            YUI:Print(LC["settings.profiles.cannot_delete_last"])
                            return
                        end
                    end
                    
                    S:ShowConfirmPopup(string.format(LC["settings.profiles.confirm_delete"], selectedProfile), function()
                        if selectedProfile == currentProfile then
                             -- Find a fallback profile to switch to
                            local fallback = FindFallbackProfile(db, savedVariableName, selectedProfile)
                            
                            SwitchToProfile(db, fallback, savedVariableName)
                            if not DeleteConfigSetsProfileState(selectedProfile) then return end
                            db:DeleteProfile(selectedProfile)
                            
                            YUI:Print(string.format(LC["settings.profiles.deleted_and_switched"], selectedProfile, fallback))
                            FrameAPI.ReloadUI() -- Reload UI to ensure clean state after profile switch
                        else
                            if not DeleteConfigSetsProfileState(selectedProfile) then return end
                            db:DeleteProfile(selectedProfile)
                            selectedProfile = GetCurrentProfileName(db, savedVariableName)
                            YUI:Print(LC["settings.profiles.deleted"])
                            RefreshUI()
                        end
                    end, {
                        acceptTone = "danger",
                    })
                end
            },
            {
                type = "button",
                label = LC["settings.profiles.reset_current"],
                width = 104,
                icon = SettingsIcon("rotate-ccw"),
                iconSize = 14,
                iconCrop = false,
                contentAlign = "center",
                onClick = function()
                    if not db then return end
                    S:ShowConfirmPopup(LC["settings.profiles.confirm_reset"], function()
                        db:ResetProfile()
                        local ConfigSets = GetConfigSets()
                        if ConfigSets and ConfigSets.ResetProfileState then
                            local resetOk, resetCode, resetDetail =
                                ConfigSets:ResetProfileState(
                                    GetActiveProductId(),
                                    GetCurrentProfileName(db, savedVariableName)
                                )
                            if not resetOk then
                                PrintConfigSetsError(resetCode)
                                return
                            end
                        end
                        YUI:Print(LC["settings.profiles.reset_done"])
                        RefreshUI()
                    end, {
                        acceptTone = "danger",
                    })
                end
            }
        }},
        
        { type = "space", height = 10 },
        
        -- --- 分割线：新建配置 ---
        { type = "divider", label = LC["settings.profiles.new_profile"], alignLeft = true, width = 600 },
        { type = "row", children = {
            { type = "text", label = LC["settings.profiles.profile_name"], width = 100 },
            {
                type = "editbox",
                width = profileNameWidth,
                get = function() return newProfileName end,
                set = function(val) newProfileName = val end,
            },
            {
                type = "button",
                label = LC["settings.profiles.create_profile"],
                width = 100,
                onClick = function()
                    if not db then return end
                    if not newProfileName or newProfileName == "" then
                        YUI:Print(LC["settings.profiles.enter_profile_name"])
                        return
                    end
                    
                    local current = GetCurrentProfileName(db, savedVariableName)
                    
                    -- Check if profile exists
                    if ProfileExists(db, savedVariableName, newProfileName) then
                        YUI:Print(string.format(LC["settings.profiles.profile_exists"], newProfileName))
                        return
                    end
                    
                    local ConfigSets = GetConfigSets()
                    if ConfigSets and ConfigSets.CopyProfileState and not ConfigSets.ProfileOwnership then
                        local copied, copyCode, copyDetail = ConfigSets:CopyProfileState(
                            GetActiveProductId(),
                            current,
                            newProfileName
                        )
                        if not copied then
                            PrintConfigSetsError(copyCode)
                            return
                        end
                    end
                    local ok, err = SaveProfileBeforeSwitch(db, newProfileName, db.profile, savedVariableName, function()
                        if ConfigSets and ConfigSets.ProfileOwnership then
                            local copied, copyCode = ConfigSets:CopyProfileState(GetActiveProductId(), current, newProfileName)
                            if not copied then return false, copyCode end
                            ConfigSets:InvalidateTransactions(db)
                        end
                        return true
                    end)
                    if not ok then
                        if ConfigSets and not ConfigSets.ProfileOwnership and ConfigSets.DeleteProfileState then
                            ConfigSets:DeleteProfileState(
                                GetActiveProductId(),
                                newProfileName
                            )
                        end
                        YUI:Print("配置文件保存失败: " .. tostring(err or newProfileName))
                        return
                    end

                    selectedProfile = newProfileName
                    newProfileName = ""
                    YUI:Print(string.format(LC["settings.profiles.created_profile"], current, selectedProfile))
                    RefreshUI()
                end
            },
        }},

        { type = "space", height = 10 },

        { type = "divider", label = LC["settings.config_transfer.section"], alignLeft = true, width = 600 },
        { type = "row", children = {
            {
                type = "button",
                label = LC["settings.config_transfer.export_action"],
                width = 150,
                icon = SettingsIcon("upload"),
                iconSize = 14,
                iconCrop = false,
                contentAlign = "center",
                onClick = function()
                    if S.ShowConfigTransferExport then
                        S:ShowConfigTransferExport({ profileName = currentProfileName })
                    end
                end,
            },
            {
                type = "button",
                label = LC["settings.config_transfer.import_action"],
                width = 150,
                icon = SettingsIcon("download"),
                iconSize = 14,
                iconCrop = false,
                contentAlign = "center",
                onClick = function()
                    if S.ShowConfigTransferImport then
                        S:ShowConfigTransferImport({
                            profileName = currentProfileName,
                            isLegacyString = IsLegacyProfileString,
                            importLegacy = ImportLegacyProfileString,
                            profileExists = function(name)
                                return ProfileExists(db, savedVariableName, TrimProfileName(name))
                            end,
                            importPackage = ImportModularPackage,
                            startImportPackage = StartImportModularPackage,
                            reviewPrepared = S.SoundCenter and function(prepared, accept, cancel, owner)
                                S.SoundCenter:ReviewTransfer(prepared,accept,cancel,owner,GetActiveDB():GetCurrentProfile())
                            end or nil,
                        })
                    end
                end,
            },
        }},
    }
    
    S:RenderConfig(parent, config)
end

S:RegisterModule("配置文件", "Interface\\Icons\\Inv_Scroll_03", Render, { id = "core.profiles", product = "core", scope = "core", titleKey = "settings.modules.profiles" })

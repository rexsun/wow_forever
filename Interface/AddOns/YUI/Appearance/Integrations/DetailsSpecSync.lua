local _, YUI = ...
if not YUI then return end

local Icons = YUI.API and YUI.API.Icons
local ICON_SCOPE_ID = "details_spec_sync"
if not Icons then return end

local type = type
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local registeredPaths = {}
local failedPaths = {}
local eventFrame
local retryScheduled = false
local retryGeneration = 0
local retryAttemptsLeft = 0
local verifyScheduled = false
local verifyGeneration = 0
local verifyStep = 0
local warningPrinted = false
local detailsStartupHooked = false
local detailsStartupHookFailed = false
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
local MAX_RETRY_ATTEMPTS = 30
local RETRY_DELAY = 0.2
local VERIFY_DELAYS = { 0.2, 1, 3, 6 }
local LOG_PREFIX = "|cff66c6ff<DetailsSync>|r"
local DETAILS_DEFAULT_SPEC_ICON = [[Interface\AddOns\Details\images\spec_icons_normal]]
local DETAILS_DEFAULT_CLASS_ICON = [[Interface\AddOns\Details\images\classes_small]]
local PREVIEW_SPEC_IDS = { 71, 72, 73, 250, 65, 577, 1467 }

local function Log(force, ...)
    if not YUI.Debug then
        return
    end
    YUI:Debug(LOG_PREFIX, ...)
end

local function IsScopeEnabled()
    if Icons.IsIconScopeEnabled then
        return Icons.IsIconScopeEnabled(ICON_SCOPE_ID)
    end
    return true
end

local function IsDetailsLoaded()
    return IsAddOnLoaded and IsAddOnLoaded("Details")
end

local function WarnOnce(message)
    if warningPrinted then
        return
    end
    warningPrinted = true
    Log(true, message)
end

local function GetDetailsNamespace()
    if type(_G.Details222) == "table" then
        return _G.Details222, "global"
    end

    local Details = _G.Details
    if not Details or type(Details.AddCustomIconSet) ~= "function" then
        return nil, "none"
    end

    if type(debug) == "table" and type(debug.getupvalue) == "function" then
        for index = 1, 20 do
            local ok, name, value = pcall(debug.getupvalue, Details.AddCustomIconSet, index)
            if not ok or not name then
                break
            end
            if name == "Details222" and type(value) == "table" then
                return value, "upvalue"
            end
        end
    end

    return nil, "none"
end

local function GetDetailsIconList()
    local d222 = GetDetailsNamespace()
    local list = d222 and d222.BarIconSetList
    if type(list) == "table" then
        return list
    end
    return nil
end

local function GetDetailsIconListState()
    local d222, source = GetDetailsNamespace()
    if not d222 then
        return "namespace:" .. tostring(source)
    end
    local list = d222.BarIconSetList
    if type(list) == "table" then
        return tostring(source) .. ":" .. tostring(#list)
    end
    return tostring(source) .. ":" .. type(list)
end

local function GetDetailsIconListCount()
    local list = GetDetailsIconList()
    return list and #list or 0
end

local function FindIconSet(path)
    local list = GetDetailsIconList()
    if list then
        for i = 1, #list do
            local value = list[i]
            if type(value) == "table" and value.value == path then
                return value
            end
        end
    end
    return nil
end

local function HasIconSet(path)
    local list = GetDetailsIconList()
    if list then
        local entry = FindIconSet(path)
        if entry then
            registeredPaths[path] = true
            return true
        end
        registeredPaths[path] = nil
        return false
    end

    return registeredPaths[path] == true
end

local function CopyCoords(value)
    if type(value) ~= "table" then return nil end
    return { value[1], value[2], value[3], value[4] }
end

local function ParseSpecCoords(value)
    if type(value) == "table" then
        return CopyCoords(value)
    end
    if type(value) ~= "string" then return nil end

    local x1, x2, y1, y2 = value:match("^(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)$")
    if not x1 then return nil end

    return {
        tonumber(x1) / 512,
        tonumber(x2) / 512,
        tonumber(y1) / 512,
        tonumber(y2) / 512,
    }
end

local function GetPreviewTexCoords(set)
    local coords = set and set.specCoords
    if type(coords) ~= "table" then return nil end

    for _, specID in ipairs(PREVIEW_SPEC_IDS) do
        local parsed = ParseSpecCoords(coords[specID])
        if parsed then
            return parsed
        end
    end

    for _, coord in pairs(coords) do
        local parsed = ParseSpecCoords(coord)
        if parsed then
            return parsed
        end
    end

    return nil
end

local function GetSetLabel(set)
    return set and (set.detailsLabel or set.name or set.id) or nil
end

local function UpdateDetailsIconSetEntry(entry, set)
    if type(entry) ~= "table" or type(set) ~= "table" then return end

    local previewCoords = GetPreviewTexCoords(set)
    entry.label = GetSetLabel(set) or entry.label
    entry.isSpec = true
    entry.icon = set.texture
    if previewCoords then
        entry.texcoord = previewCoords
    end
    entry.iconsize = entry.iconsize or { 16, 16 }
end

local function GetCustomSpecIconSets()
    local sets = {}
    if not Icons.GetIconSets then
        return sets, false
    end

    for _, set in ipairs(Icons.GetIconSets()) do
        if set.custom and set.hasSpecIcons and set.texture then
            sets[#sets + 1] = set
        end
    end
    return sets, true
end

local function BuildManagedPathLookup(sets)
    local lookup = {}
    for _, set in ipairs(sets or {}) do
        if type(set) == "table" and type(set.texture) == "string" and set.texture ~= "" then
            lookup[set.texture] = true
        end
    end
    return lookup
end

local function GetActiveSpecIconPath()
    if not Icons.GetActiveIconSetID or not Icons.GetIconSet then
        return nil
    end

    local activeID = Icons.GetActiveIconSetID()
    local set = Icons.GetIconSet(activeID)
    if type(set) == "table" and set.hasSpecIcons and type(set.texture) == "string" and set.texture ~= "" then
        return set.texture, set
    end

    return DETAILS_DEFAULT_SPEC_ICON, nil
end

local function GetDetailsInstances()
    local Details = _G.Details
    local instances = Details and Details.tabela_instancias
    if type(instances) ~= "table" then
        return nil
    end
    return instances
end

local function ApplySpecIconPathToInstance(instance, specPath, managedPaths)
    if type(instance) ~= "table" or type(specPath) ~= "string" or specPath == "" then
        return false
    end

    local rowInfo = instance.row_info
    if type(rowInfo) ~= "table" then
        return false
    end

    local usesManagedSpec = managedPaths[rowInfo.spec_file] == true
    local hasManagedClassFallback = managedPaths[rowInfo.icon_file] == true
    if not usesManagedSpec and not hasManagedClassFallback then
        return false
    end

    local changed = rowInfo.use_spec_icons ~= true or rowInfo.spec_file ~= specPath
    if hasManagedClassFallback then
        rowInfo.icon_file = DETAILS_DEFAULT_CLASS_ICON
        changed = true
    end

    if changed then
        if type(instance.SetBarSpecIconSettings) == "function" then
            local ok = pcall(instance.SetBarSpecIconSettings, instance, true, specPath, true)
            if not ok then
                rowInfo.use_spec_icons = true
                rowInfo.spec_file = specPath
                rowInfo.no_icon = false
            end
        else
            rowInfo.use_spec_icons = true
            rowInfo.spec_file = specPath
            rowInfo.no_icon = false
        end
    end

    return changed
end

local function RefreshDetailsWindows()
    local Details = _G.Details
    if not Details then return end

    if type(Details.RefreshMainWindow) == "function" then
        pcall(Details.RefreshMainWindow, Details, -1, true)
    end
end

local function SyncActiveIconSetToDetailsInstances(sets)
    local specPath = GetActiveSpecIconPath()
    if not specPath then
        return 0
    end

    local managedPaths = BuildManagedPathLookup(sets)
    local instances = GetDetailsInstances()
    if not instances then
        return 0
    end

    local applied = 0
    for _, instance in ipairs(instances) do
        if ApplySpecIconPathToInstance(instance, specPath, managedPaths) then
            applied = applied + 1
        end
    end

    if applied > 0 then
        RefreshDetailsWindows()
    end

    return applied
end

local function RegisterOne(set)
    local path = set and set.texture
    local label = GetSetLabel(set)
    local Details = _G.Details
    if not Details or type(Details.AddCustomIconSet) ~= "function" then return nil end
    if type(path) ~= "string" or path == "" then return "failed" end
    if failedPaths[path] then return "failed" end

    if HasIconSet(path) then
        local existing = FindIconSet(path)
        if existing then
            UpdateDetailsIconSetEntry(existing, set)
        end
        registeredPaths[path] = true
        return "exists"
    end

    local existing = FindIconSet(path)
    if existing then
        UpdateDetailsIconSetEntry(existing, set)
        registeredPaths[path] = true
        return "exists"
    end

    local previewCoords = GetPreviewTexCoords(set)

    local ok, err = pcall(Details.AddCustomIconSet, Details, path, label, true, path, previewCoords, { 16, 16 })
    if not ok then
        failedPaths[path] = true
        WarnOnce("AddCustomIconSet failed: " .. tostring(err))
        return "failed"
    end

    registeredPaths[path] = true
    return "added"
end

local function RegisterAll(reason)
    local stats = {
        reason = reason or "unknown",
        listCount = GetDetailsIconListCount(),
        custom = 0,
        added = 0,
        exists = 0,
        failed = 0,
        pending = 0,
        applied = 0,
    }

    local sets, canReadSets = GetCustomSpecIconSets()
    if not canReadSets then
        stats.pending = stats.pending + 1
        stats.pendingReason = "no-Icons.GetIconSets"
        return stats
    end

    stats.custom = #sets
    if stats.custom == 0 then
        stats.pending = stats.pending + 1
        stats.pendingReason = "no-custom-spec-sets"
        return stats
    end

    for _, set in ipairs(sets) do
        local registered = RegisterOne(set)
        if registered == nil then
            stats.pending = stats.pending + 1
        elseif registered == "added" then
            stats.added = stats.added + 1
        elseif registered == "exists" then
            stats.exists = stats.exists + 1
        else
            stats.failed = stats.failed + 1
        end
    end

    stats.applied = SyncActiveIconSetToDetailsInstances(sets)
    stats.listCountAfter = GetDetailsIconListCount()
    return stats
end

local function LogStats(reason, stats)
    Log(false,
        "sync", tostring(reason),
        "scope=" .. tostring(IsScopeEnabled()),
        "loaded=" .. tostring(IsDetailsLoaded()),
        "api=" .. tostring(_G.Details and type(_G.Details.AddCustomIconSet) == "function"),
        "list=" .. GetDetailsIconListState() .. " " .. tostring(stats.listCount) .. "->" .. tostring(stats.listCountAfter or stats.listCount),
        "custom=" .. tostring(stats.custom),
        "added=" .. tostring(stats.added),
        "exists=" .. tostring(stats.exists),
        "failed=" .. tostring(stats.failed),
        "applied=" .. tostring(stats.applied or 0),
        "pending=" .. tostring(stats.pendingReason or stats.pending)
    )
end

local function StopAddonWaiting()
    if eventFrame then
        YUI.Event:Off(eventFrame)
        eventFrame = nil
    end
end

local function StopWaiting()
    StopAddonWaiting()
    retryGeneration = retryGeneration + 1
    retryScheduled = false
    retryAttemptsLeft = 0
    verifyGeneration = verifyGeneration + 1
    verifyScheduled = false
    verifyStep = 0
end

local TryRegister
local StartVerification

local function QueueRetry(reason)
    if retryScheduled or not IsDetailsLoaded() or not C_Timer or not C_Timer.After then
        return
    end
    if retryAttemptsLeft <= 0 then
        Log(false, "retry exhausted", tostring(reason))
        return
    end

    retryScheduled = true
    retryAttemptsLeft = retryAttemptsLeft - 1
    local generation = retryGeneration
    C_Timer.After(RETRY_DELAY, function()
        if generation ~= retryGeneration then
            return
        end
        retryScheduled = false
        TryRegister("retry:" .. tostring(reason), false)
    end)
end

local function HookDetailsStartup()
    if detailsStartupHooked or detailsStartupHookFailed then
        return detailsStartupHooked
    end

    local Details = _G.Details
    if not Details or type(Details.AnnounceStartup) ~= "function" then
        return false
    end

    if type(hooksecurefunc) == "function" then
        local ok = pcall(hooksecurefunc, Details, "AnnounceStartup", function()
            Log(false, "Details.AnnounceStartup fired")
            retryAttemptsLeft = MAX_RETRY_ATTEMPTS
            TryRegister("details-startup", true)
            StartVerification("details-startup")
        end)
        if ok then
            detailsStartupHooked = true
            Log(false, "hooked Details.AnnounceStartup")
            return true
        end
    end

    detailsStartupHookFailed = true
    Log(false, "Details.AnnounceStartup hook unavailable")
    return false
end

TryRegister = function(reason, resetRetry)
    reason = reason or "manual"
    if not IsScopeEnabled() then
        Log(false, "scope disabled", tostring(reason))
        StopWaiting()
        return nil
    end

    HookDetailsStartup()

    local Details = _G.Details
    if Details and type(Details.AddCustomIconSet) == "function" then
        StopAddonWaiting()
        if resetRetry ~= false and retryAttemptsLeft <= 0 then
            retryAttemptsLeft = MAX_RETRY_ATTEMPTS
        end
        local stats = RegisterAll(reason)
        LogStats(reason, stats)
        if stats.pending > 0 then
            QueueRetry(reason)
        end
        return stats
    end

    if IsDetailsLoaded() then
        if resetRetry ~= false then
            retryAttemptsLeft = MAX_RETRY_ATTEMPTS
        end
        Log(false, "waiting api", tostring(reason), "list=" .. tostring(GetDetailsIconListCount()))
        QueueRetry(reason)
        return nil
    end

    if YUI.Event and not eventFrame then
        Log(false, "waiting ADDON_LOADED Details", tostring(reason))
        eventFrame = YUI.Event:On("ADDON_LOADED", function(_, addon)
            if addon == "Details" then
                Log(false, "ADDON_LOADED Details")
                retryAttemptsLeft = MAX_RETRY_ATTEMPTS
                TryRegister("addon-loaded", true)
                StartVerification("addon-loaded")
            end
        end)
    end
    return nil
end

StartVerification = function(reason)
    if not C_Timer or not C_Timer.After then
        TryRegister("verify-no-timer:" .. tostring(reason), true)
        return
    end
    if verifyScheduled then
        return
    end

    verifyGeneration = verifyGeneration + 1
    verifyStep = 0
    local generation = verifyGeneration

    local function QueueNext()
        if generation ~= verifyGeneration then
            return
        end
        verifyStep = verifyStep + 1
        local delay = VERIFY_DELAYS[verifyStep]
        if not delay then
            verifyScheduled = false
            return
        end

        verifyScheduled = true
        C_Timer.After(delay, function()
            if generation ~= verifyGeneration then
                return
            end
            Log(false, "verify", tostring(reason), "step=" .. tostring(verifyStep), "delay=" .. tostring(delay))
            retryAttemptsLeft = MAX_RETRY_ATTEMPTS
            TryRegister("verify:" .. tostring(reason) .. ":" .. tostring(verifyStep), true)
            QueueNext()
        end)
    end

    Log(false, "verify start", tostring(reason))
    QueueNext()
end

function Icons.DumpDetailsSpecSync()
    local Details = _G.Details
    local list = GetDetailsIconList()
    local sets, canReadSets = GetCustomSpecIconSets()
    Log(true,
        "dump",
        "scope=" .. tostring(IsScopeEnabled()),
        "loaded=" .. tostring(IsDetailsLoaded()),
        "api=" .. tostring(Details and type(Details.AddCustomIconSet) == "function"),
        "list=" .. GetDetailsIconListState() .. "/" .. tostring(list and #list or "nil"),
        "custom=" .. tostring(canReadSets and #sets or "nil"),
        "hooked=" .. tostring(detailsStartupHooked)
    )

    if not canReadSets or #sets == 0 then
        return
    end

    for _, set in ipairs(sets) do
        Log(true, "dump-set", tostring(set.id), HasIconSet(set.texture) and "present" or "missing", tostring(set.texture))
    end

    local instances = GetDetailsInstances()
    if type(instances) ~= "table" then
        return
    end
    for index, instance in ipairs(instances) do
        local rowInfo = type(instance) == "table" and instance.row_info
        if type(rowInfo) == "table" then
            Log(true,
                "dump-window",
                tostring(index),
                "useSpec=" .. tostring(rowInfo.use_spec_icons),
                "spec=" .. tostring(rowInfo.spec_file),
                "class=" .. tostring(rowInfo.icon_file)
            )
        end
    end
end

Log(false, "loaded")

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        retryAttemptsLeft = MAX_RETRY_ATTEMPTS
        TryRegister("db-ready", true)
        StartVerification("db-ready")
    end)

    YUI.Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", function()
        retryAttemptsLeft = MAX_RETRY_ATTEMPTS
        TryRegister("icon-set-changed", true)
        StartVerification("icon-set-changed")
    end)
    YUI.Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", function(_, scopeID)
        if scopeID == ICON_SCOPE_ID then
            if not IsScopeEnabled() then
                StopWaiting()
                return
            end
            retryAttemptsLeft = MAX_RETRY_ATTEMPTS
            TryRegister("scope-changed", true)
            StartVerification("scope-changed")
        end
    end)
    YUI.Event:On("PLAYER_LOGIN", function()
        retryAttemptsLeft = MAX_RETRY_ATTEMPTS
        TryRegister("player-login", true)
        StartVerification("player-login")
    end)
    YUI.Event:On("PLAYER_ENTERING_WORLD", function()
        retryAttemptsLeft = MAX_RETRY_ATTEMPTS
        TryRegister("player-entering-world", true)
        StartVerification("player-entering-world")
    end)
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local CDMCatalog = YHUD.CDMCatalog
if not (CDMCatalog and CDMCatalog.ReconcileContext) then return end

local Cache = YHUD.NativePreviewCache or {}
YHUD.NativePreviewCache = Cache

Cache.SCHEMA_VERSION = 3

local CATEGORY_ORDER = {
    essential = 1,
    utility = 2,
    trackedBuff = 3,
    trackedBar = 4,
}

local function PositiveInteger(value)
    value = tonumber(value)
    if not value or value <= 0 or value >= math.huge then return nil end
    value = math.floor(value)
    return value > 0 and value or nil
end

local function ResolveScopedProfile(profile, specKey)
    if type(profile) ~= "table" then return nil end
    if rawget(profile, "_yhudSpecKey") == specKey
        and type(profile.entries) == "table" then
        return profile
    end
    if type(YHUD.GetScopedProfile) ~= "function" then return nil end
    local scoped = YHUD:GetScopedProfile(profile, specKey, false)
    return type(scoped) == "table" and scoped or nil
end

local function BuildStaticSnapshot(profile, specKey)
    local scoped = ResolveScopedProfile(profile, specKey)
    local sourceEntries = scoped and scoped.entries
    if type(sourceEntries) ~= "table" then return nil end

    local entries = {}
    for sourceKey, entry in pairs(sourceEntries) do
        local category = type(entry) == "table"
            and entry.officialCategory or nil
        local entryKey = type(sourceKey) == "string" and sourceKey
            or (type(entry) == "table"
                and type(entry.entryKey) == "string"
                and entry.entryKey or nil)
        if type(entry) == "table"
            and entry.origin == "official-cdm"
            and CATEGORY_ORDER[category]
            and type(entryKey) == "string"
            and entryKey ~= "" then
            local cooldownId = PositiveInteger(entry.cooldownId)
                or PositiveInteger(entryKey:match("^cdm:([1-9][0-9]*)$"))
            if cooldownId then
                local descriptor = {
                    entryKey = entryKey,
                    cooldownId = cooldownId,
                    category = category,
                    order = PositiveInteger(entry.order),
                    isKnown = entry.isKnown ~= false,
                }
                if type(entry.name) == "string" and entry.name ~= "" then
                    descriptor.name = entry.name
                end
                if type(entry.icon) == "number"
                    or type(entry.icon) == "string" then
                    descriptor.icon = entry.icon
                end
                entries[#entries + 1] = descriptor
            end
        end
    end
    if #entries == 0 then return nil end

    table.sort(entries, function(left, right)
        local leftCategory = CATEGORY_ORDER[left.category] or 99
        local rightCategory = CATEGORY_ORDER[right.category] or 99
        if leftCategory ~= rightCategory then
            return leftCategory < rightCategory
        end
        local leftOrder = left.order or math.huge
        local rightOrder = right.order or math.huge
        if leftOrder ~= rightOrder then return leftOrder < rightOrder end
        return left.entryKey < right.entryKey
    end)
    return { entries = entries }
end

local function GetBuildKey()
    if _G.GetBuildInfo then
        local _, build, _, interfaceVersion = _G.GetBuildInfo()
        return tostring(interfaceVersion or "") .. ":" .. tostring(build or "")
    end
    return "unknown"
end

local function GetCharacterKey()
    local Player = YUI.Player
    if Player and type(Player.GetCharacterKey) == "function" then
        local ok, value = pcall(Player.GetCharacterKey, Player)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    return nil
end

local function GetRoot(create)
    local db = YHUD:GetDB()
    if type(db) ~= "table" then return nil end
    local root = db.nativePreviewCache
    if type(root) ~= "table" and create == true then
        root = {
            schemaVersion = Cache.SCHEMA_VERSION,
            contentPolicyRevision = YHUD.CONTENT_POLICY_REVISION,
            build = GetBuildKey(),
            characters = {},
        }
        db.nativePreviewCache = root
    end
    if type(root) ~= "table" then return nil end
    if root.schemaVersion ~= Cache.SCHEMA_VERSION
        or root.contentPolicyRevision ~= YHUD.CONTENT_POLICY_REVISION
        or root.build ~= GetBuildKey() then
        if create ~= true then return nil end
        root = {
            schemaVersion = Cache.SCHEMA_VERSION,
            contentPolicyRevision = YHUD.CONTENT_POLICY_REVISION,
            build = GetBuildKey(),
            characters = {},
        }
        db.nativePreviewCache = root
    end
    root.characters = type(root.characters) == "table"
        and root.characters or {}
    return root
end

function Cache:Store(specKey, snapshot)
    if not YHUD:IsStableSpecKey(specKey)
        or type(snapshot) ~= "table" or next(snapshot) == nil then
        return nil, "invalid-native-preview"
    end
    if specKey ~= YHUD:GetCurrentSpecKey() then
        return nil, "not-runtime-specialization"
    end
    local characterKey = GetCharacterKey()
    if not characterKey then return nil, "character-key-unavailable" end
    local root = GetRoot(true)
    if not root then return nil, "db-unavailable" end
    local character = type(root.characters[characterKey]) == "table"
        and root.characters[characterKey] or {}
    root.characters[characterKey] = character
    character[specKey] = {
        capturedAt = _G.time and _G.time() or nil,
        snapshot = YHUD:CopyValue(snapshot),
    }
    return true
end

function Cache:CaptureFromProfile(specKey, profile)
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    local snapshot = BuildStaticSnapshot(profile, specKey)
    if not snapshot then return nil, "native-preview-empty" end
    return self:Store(specKey, snapshot)
end

function Cache:Get(specKey)
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    local characterKey = GetCharacterKey()
    if not characterKey then return nil, "character-key-unavailable" end
    local root = GetRoot(false)
    local character = root and root.characters[characterKey]
    local record = type(character) == "table" and character[specKey] or nil
    if type(record) ~= "table" or type(record.snapshot) ~= "table" then
        return nil, "native-preview-not-found"
    end
    return YHUD:CopyValue(record.snapshot), {
        capturedAt = record.capturedAt,
        build = root.build,
        schemaVersion = root.schemaVersion,
    }
end

local BaseReconcileContext = CDMCatalog.ReconcileContext
function CDMCatalog:ReconcileContext(profile, specKey, options)
    local result, report, runtimeProfile =
        BaseReconcileContext(self, profile, specKey, options)
    if result and type(report) == "table" then
        local resolvedSpecKey = report.specKey or specKey
            or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
            or YHUD:GetCurrentSpecKey()
        Cache:CaptureFromProfile(resolvedSpecKey, result)
    end
    return result, report, runtimeProfile
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Service = YUI.Settings and YUI.Settings.ConfigSets
if not Service then return end

local ConfigSets = YHUD.ConfigSets or {}
YHUD.ConfigSets = ConfigSets

ConfigSets.PROVIDER_ID = YHUD.CONFIG_SET_PROVIDER_ID
ConfigSets.BUILTIN_ID = "default"
ConfigSets.ensureBusy = false
ConfigSets.ensureResult = nil
ConfigSets.ensureDatabase = nil
ConfigSets.ensureProfileName = nil
ConfigSets.preparedUserSetData = ConfigSets.preparedUserSetData or {}
ConfigSets.CONTENT_PACK_VERSION = 2
ConfigSets.LEGACY_CONTENT_PACK_VERSION = 1
ConfigSets.SPEC_DOCUMENT_VERSION = 1
local MAX_LOCAL_CONTENT_PACK_BYTES = 512 * 1024
local MAX_LOCAL_SPEC_DOCUMENT_BYTES = 2 * 1024 * 1024
local MAX_EXPANDED_CONTENT_BYTES = 4 * 1024 * 1024
local SPECIALIZATION_DATA_ROOTS = {
    "contentBySpec",
    "officialOverridesBySpec",
    "defaultPresetTombstonesBySpec",
    "defaultPresetOverridesBySpec",
}

local SUPPORTED_SPEC_KEYS = YHUD:GetSupportedSpecKeys()

local SUPPORTED_SPEC_KEY_SET = {}
for index = 1, #SUPPORTED_SPEC_KEYS do
    SUPPORTED_SPEC_KEY_SET[SUPPORTED_SPEC_KEYS[index]] = true
end

local function ValidateSupportedSpecializationRoots(profile)
    if type(profile) ~= "table" then return true end
    YHUD:MigrateClientSpecializationKeys(profile)
    for index = 1, #SPECIALIZATION_DATA_ROOTS do
        local rootKey = SPECIALIZATION_DATA_ROOTS[index]
        local root = profile[rootKey]
        if root ~= nil and type(root) ~= "table" then
            return nil, "invalid-profile", rootKey
        end
        for specKey in pairs(root or {}) do
            if SUPPORTED_SPEC_KEY_SET[specKey] ~= true then
                return nil, "invalid-spec-document", specKey
            end
        end
    end
    return true
end

local function BuildLocalSpecDocumentFields()
    local fields = {
        {
            path = { "profile", "contentBySpecPack", "data" },
            maxBytes = MAX_LOCAL_CONTENT_PACK_BYTES,
        },
    }
    local keys = YHUD:CopyValue(SUPPORTED_SPEC_KEYS)
    for legacy in pairs(YHUD.Client.legacySpecKeyMap or {}) do keys[#keys + 1] = legacy end
    for index = 1, #keys do
        fields[#fields + 1] = {
            path = {
                "profile",
                "specDocuments",
                "blocks",
                keys[index],
            },
            maxBytes = MAX_LOCAL_SPEC_DOCUMENT_BYTES,
        }
    end
    return fields
end

local function GetContentSerializer()
    local libStub = _G.LibStub
    if not (libStub and type(libStub.GetLibrary) == "function") then
        return nil, "storage-codec-unavailable"
    end
    local serializer = libStub:GetLibrary("AceSerializer-3.0", true)
    if not (serializer and type(serializer.Serialize) == "function"
        and type(serializer.Deserialize) == "function") then
        return nil, "storage-codec-unavailable"
    end
    return serializer
end

local function GetContentCodec()
    local serializer, code = GetContentSerializer()
    if not serializer then return nil, nil, code end
    local libStub = _G.LibStub
    local deflate = libStub:GetLibrary("LibDeflate", true)
    if not (deflate and type(deflate.CompressDeflate) == "function"
        and type(deflate.DecompressDeflate) == "function") then
        return nil, nil, "storage-codec-unavailable"
    end
    return serializer, deflate
end

local function DeserializeContent(serializer, serialized)
    local ok, decoded, value = pcall(
        serializer.Deserialize,
        serializer,
        serialized
    )
    if not ok or decoded ~= true or type(value) ~= "table" then
        return nil, "invalid-content-pack"
    end
    return value
end

local ValidateExpandedContent

local function BuildSpecDocumentSummary(content)
    local summary = {
        monitorCount = 0,
        groupCounts = {},
    }
    for _ in pairs(type(content) == "table" and content.monitors or {}) do
        summary.monitorCount = summary.monitorCount + 1
    end
    for groupId, members in pairs(
        type(content) == "table" and content.groupMembers or {}
    ) do
        if type(groupId) == "string" and type(members) == "table"
            and #members > 0 then
            summary.groupCounts[groupId] = #members
        end
    end
    return summary
end

local SPEC_DOCUMENT_STATE_FIELDS = {
    {
        root = "officialOverridesBySpec",
        field = "officialOverrides",
    },
    {
        root = "defaultPresetTombstonesBySpec",
        field = "defaultPresetTombstones",
    },
    {
        root = "defaultPresetOverridesBySpec",
        field = "defaultPresetOverrides",
    },
}

local RUNTIME_SNAPSHOT_OMITTED_FIELDS = {
    contentBySpec = true,
    contentBySpecPack = true,
    specDocuments = true,
    officialOverridesBySpec = true,
    defaultPresetTombstonesBySpec = true,
    defaultPresetOverridesBySpec = true,
}

local function BuildStoredSpecDocument(profile, specKey, content)
    local document = {
        version = ConfigSets.SPEC_DOCUMENT_VERSION,
        content = content,
    }
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local definition = SPEC_DOCUMENT_STATE_FIELDS[index]
        local root = type(profile[definition.root]) == "table"
            and profile[definition.root] or nil
        local value = root and root[specKey] or nil
        if type(value) == "table" and next(value) ~= nil then
            document[definition.field] = value
        end
    end
    return document
end

local function ApplyStoredSpecDocument(profile, specKey, document)
    if type(document) ~= "table"
        or document.version ~= ConfigSets.SPEC_DOCUMENT_VERSION
        or type(document.content) ~= "table" then
        return nil, "invalid-spec-document"
    end
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local definition = SPEC_DOCUMENT_STATE_FIELDS[index]
        local value = document[definition.field]
        if value ~= nil and type(value) ~= "table" then
            return nil, "invalid-spec-document"
        end
        local root = type(profile[definition.root]) == "table"
            and profile[definition.root] or {}
        profile[definition.root] = root
        root[specKey] = type(value) == "table" and next(value) ~= nil
            and YHUD:CopyValue(value) or nil
    end
    return document.content
end

local function ClearSpecDocumentStateProjection(profile)
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        profile[SPEC_DOCUMENT_STATE_FIELDS[index].root] = nil
    end
    return profile
end

local function ValidateSpecDocuments(profile)
    YHUD:MigrateClientSpecializationKeys(profile)
    local documents = type(profile) == "table" and profile.specDocuments or nil
    if type(documents) ~= "table" then return nil, "spec-documents-missing" end
    if documents.version ~= ConfigSets.SPEC_DOCUMENT_VERSION
        or type(documents.blocks) ~= "table"
        or type(documents.summaries) ~= "table" then
        return nil, "unsupported-spec-documents"
    end
    if type(profile.contentBySpecPack) == "table" then
        return nil, "content-document-conflict"
    end
    local totalBytes = 0
    for specKey, block in pairs(documents.blocks) do
        if not SUPPORTED_SPEC_KEY_SET[specKey]
            or type(block) ~= "string" or block == ""
            or #block > MAX_LOCAL_SPEC_DOCUMENT_BYTES then
            return nil, "invalid-spec-document"
        end
        totalBytes = totalBytes + #block
        if totalBytes > MAX_EXPANDED_CONTENT_BYTES then
            return nil, "capacity-exceeded"
        end
        local summary = documents.summaries[specKey]
        if type(summary) ~= "table"
            or type(summary.monitorCount) ~= "number"
            or summary.monitorCount < 0
            or summary.monitorCount % 1 ~= 0
            or type(summary.groupCounts) ~= "table" then
            return nil, "invalid-spec-document-summary"
        end
    end
    for specKey in pairs(documents.summaries) do
        if documents.blocks[specKey] == nil then
            return nil, "invalid-spec-document-summary"
        end
    end
    return documents, nil, totalBytes
end

local function DecodeSpecDocument(profile, specKey, create)
    if type(profile) ~= "table" or not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    profile.contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    if type(profile.contentBySpec[specKey]) == "table" then
        return profile.contentBySpec[specKey]
    end
    local documents = type(profile.specDocuments) == "table"
        and profile.specDocuments or nil
    local block = documents and type(documents.blocks) == "table"
        and documents.blocks[specKey] or nil
    if block == nil then
        if create == true then
            local content = YHUD:CreateDefaultContent()
            profile.contentBySpec[specKey] = content
            return content
        end
        return nil, "content-not-found"
    end
    local serializer, code = GetContentSerializer()
    if not serializer then return nil, code end
    local document
    document, code = DeserializeContent(serializer, block)
    if not document then return nil, code end
    local content
    content, code = ApplyStoredSpecDocument(profile, specKey, document)
    if not content then return nil, code end
    local valid
    valid, code = ValidateExpandedContent({ [specKey] = content }, #block)
    if not valid then return nil, code end
    profile.contentBySpec[specKey] = content
    ConfigSets.lastSpecDocumentStats = {
        decoded = 1,
        encoded = 0,
        reused = 0,
        specKey = specKey,
    }
    return content
end

function ConfigSets:IsSpecDocumentProfile(profile)
    return type(profile) == "table"
        and type(profile.specDocuments) == "table"
end

function ConfigSets:LoadSpecDocument(profile, specKey, create)
    return DecodeSpecDocument(profile, specKey, create == true)
end

local CANONICAL_TYPE_ORDER = {
    boolean = 1,
    number = 2,
    string = 3,
}

local function CanonicalKeyLess(left, right)
    local leftType = type(left)
    local rightType = type(right)
    if leftType ~= rightType then
        return (CANONICAL_TYPE_ORDER[leftType] or 99)
            < (CANONICAL_TYPE_ORDER[rightType] or 99)
    end
    if leftType == "number" or leftType == "string" then
        return left < right
    end
    return left == false and right == true
end

local function AppendCanonical(parts, value, seen)
    local valueType = type(value)
    if valueType == "nil" then
        parts[#parts + 1] = "z;"
    elseif valueType == "boolean" then
        parts[#parts + 1] = value and "b1;" or "b0;"
    elseif valueType == "number" then
        local text = tostring(value)
        parts[#parts + 1] = "n" .. #text .. ":" .. text .. ";"
    elseif valueType == "string" then
        parts[#parts + 1] = "s" .. #value .. ":" .. value .. ";"
    elseif valueType == "table" then
        if seen[value] then return nil, "invalid-content-pack" end
        seen[value] = true
        local keys = {}
        for key in pairs(value) do
            if CANONICAL_TYPE_ORDER[type(key)] == nil then
                seen[value] = nil
                return nil, "invalid-content-pack"
            end
            keys[#keys + 1] = key
        end
        table.sort(keys, CanonicalKeyLess)
        parts[#parts + 1] = "t" .. #keys .. ":"
        for index = 1, #keys do
            local key = keys[index]
            local ok, code = AppendCanonical(parts, key, seen)
            if not ok then
                seen[value] = nil
                return nil, code
            end
            ok, code = AppendCanonical(parts, value[key], seen)
            if not ok then
                seen[value] = nil
                return nil, code
            end
        end
        parts[#parts + 1] = ";"
        seen[value] = nil
    else
        return nil, "invalid-content-pack"
    end
    return true
end

local function CanonicalSerialize(value)
    local parts = {}
    local ok, code = AppendCanonical(parts, value, {})
    if not ok then return nil, code end
    return table.concat(parts)
end

local function DecodeV2Entries(serializer, pack)
    local payload, code = DeserializeContent(serializer, pack.data)
    if not payload then return nil, code end
    local entries = payload.entries
    if type(entries) ~= "table" then
        return nil, "invalid-content-pack"
    end
    local count = #entries
    for key in pairs(entries) do
        if type(key) ~= "number" or key % 1 ~= 0
            or key < 1 or key > count then
            return nil, "invalid-content-pack"
        end
    end
    local previousKey
    for index = 1, count do
        local entry = entries[index]
        local specKey = type(entry) == "table" and entry[1] or nil
        if not (YHUD:IsStableSpecKey(specKey) or YHUD.Client.legacySpecKeyMap and YHUD.Client.legacySpecKeyMap[specKey])
            or type(entry[2]) ~= "string" or entry[2] == ""
            or (previousKey and specKey <= previousKey) then
            return nil, "invalid-content-pack"
        end
        for key in pairs(entry) do
            if key ~= 1 and key ~= 2 then
                return nil, "invalid-content-pack"
            end
        end
        previousKey = specKey
    end
    return entries
end

ValidateExpandedContent = function(contentBySpec, serializedBytes)
    YHUD:MigrateClientSpecializationMap(contentBySpec)
    if serializedBytes and serializedBytes > MAX_EXPANDED_CONTENT_BYTES then
        return nil, "capacity-exceeded"
    end
    local budget = YHUD.StorageBudget
    local nodes, nodeCode = budget and budget.CountNodes
        and budget:CountNodes(contentBySpec) or nil
    if budget and not nodes then return nil, nodeCode end
    if nodes and nodes > budget.HARD_NODE_LIMIT then
        return nil, "capacity-exceeded"
    end
    return true
end

local function UnpackLegacyContent(serializer, deflate, pack)
    local ok, serialized = pcall(
        deflate.DecompressDeflate,
        deflate,
        pack.data,
        MAX_EXPANDED_CONTENT_BYTES
    )
    if not ok or type(serialized) ~= "string"
        or serialized == "" or #serialized > MAX_EXPANDED_CONTENT_BYTES then
        return nil, "invalid-content-pack"
    end
    local payload, code = DeserializeContent(serializer, serialized)
    if not payload or type(payload.contentBySpec) ~= "table" then
        return nil, code or "invalid-content-pack"
    end
    local valid
    valid, code = ValidateExpandedContent(payload.contentBySpec, #serialized)
    if not valid then return nil, code end
    return payload.contentBySpec, nil, {
        version = ConfigSets.LEGACY_CONTENT_PACK_VERSION,
        data = pack.data,
        contentBySpec = YHUD:CopyValue(payload.contentBySpec),
    }
end

local function UnpackV2Content(serializer, deflate, pack)
    local entries, code = DecodeV2Entries(serializer, pack)
    if not entries then return nil, code end
    local contentBySpec = {}
    local entriesBySpec = {}
    local serializedBytes = 0
    for index = 1, #entries do
        local entry = entries[index]
        local ok, serialized = pcall(
            deflate.DecompressDeflate,
            deflate,
            entry[2],
            MAX_EXPANDED_CONTENT_BYTES - serializedBytes
        )
        if not ok or type(serialized) ~= "string" or serialized == "" then
            return nil, "invalid-content-pack"
        end
        serializedBytes = serializedBytes + #serialized
        if serializedBytes > MAX_EXPANDED_CONTENT_BYTES then
            return nil, "capacity-exceeded"
        end
        local content
        content, code = DeserializeContent(serializer, serialized)
        if not content then return nil, code end
        contentBySpec[entry[1]] = content
        local canonical
        canonical, code = CanonicalSerialize(content)
        if not canonical then return nil, code end
        entriesBySpec[entry[1]] = {
            serialized = canonical,
            data = entry[2],
        }
    end
    local valid
    valid, code = ValidateExpandedContent(contentBySpec, serializedBytes)
    if not valid then return nil, code end
    return contentBySpec, nil, {
        version = ConfigSets.CONTENT_PACK_VERSION,
        data = pack.data,
        entriesBySpec = entriesBySpec,
    }
end

local function UnpackContentBySpec(profile)
    local pack = type(profile) == "table" and profile.contentBySpecPack or nil
    if type(pack) ~= "table" then return profile end
    if (pack.version ~= ConfigSets.CONTENT_PACK_VERSION
            and pack.version ~= ConfigSets.LEGACY_CONTENT_PACK_VERSION)
        or type(pack.data) ~= "string" or pack.data == "" then
        return nil, "unsupported-content-pack"
    end
    if type(profile.contentBySpec) == "table"
        and next(profile.contentBySpec) ~= nil then
        return nil, "content-pack-conflict"
    end
    local serializer, deflate, code = GetContentCodec()
    if not serializer then return nil, code end
    local contentBySpec, unpackCode, baseline
    if pack.version == ConfigSets.LEGACY_CONTENT_PACK_VERSION then
        contentBySpec, unpackCode, baseline =
            UnpackLegacyContent(serializer, deflate, pack)
    else
        contentBySpec, unpackCode, baseline =
            UnpackV2Content(serializer, deflate, pack)
    end
    if not contentBySpec then return nil, unpackCode end
    profile.contentBySpec = contentBySpec
    profile.contentBySpecPack = nil
    return profile, nil, baseline
end

local function CopyStringMap(values)
    local result = {}
    for key, value in pairs(type(values) == "table" and values or {}) do
        if type(key) == "string" and type(value) == "string" then
            result[key] = value
        end
    end
    return result
end

local function CopySummaryMap(values)
    local result = {}
    for specKey, summary in pairs(
        type(values) == "table" and values or {}
    ) do
        if type(specKey) == "string" and type(summary) == "table" then
            result[specKey] = {
                monitorCount = tonumber(summary.monitorCount) or 0,
                groupCounts = YHUD:CopyValue(summary.groupCounts or {}),
            }
        end
    end
    return result
end

local function EncodeSpecDocuments(
    profile,
    previousDocuments,
    dirtySpecs,
    summaryOverrides
)
    if type(profile) ~= "table" then return nil, "invalid-profile" end
    local serializer, code = GetContentSerializer()
    if not serializer then return nil, code end
    local sourceDocuments = type(previousDocuments) == "table"
        and previousDocuments
        or type(profile.specDocuments) == "table"
            and profile.specDocuments or nil
    local blocks = CopyStringMap(sourceDocuments and sourceDocuments.blocks)
    local summaries = CopySummaryMap(
        sourceDocuments and sourceDocuments.summaries
    )
    local encoded = 0
    local reused = 0
    local contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    for specKey, content in pairs(contentBySpec) do
        if not SUPPORTED_SPEC_KEY_SET[specKey] or type(content) ~= "table" then
            return nil, "invalid-spec-document"
        end
        local mustEncode = blocks[specKey] == nil
            or type(dirtySpecs) ~= "table"
            or dirtySpecs[specKey] == true
        if mustEncode then
            local ok, block = pcall(
                serializer.Serialize,
                serializer,
                BuildStoredSpecDocument(profile, specKey, content)
            )
            if not ok or type(block) ~= "string" or block == ""
                or #block > MAX_LOCAL_SPEC_DOCUMENT_BYTES then
                return nil, ok and "capacity-exceeded"
                    or "storage-codec-failed"
            end
            blocks[specKey] = block
            summaries[specKey] = type(summaryOverrides) == "table"
                and type(summaryOverrides[specKey]) == "table"
                and YHUD:CopyValue(summaryOverrides[specKey])
                or BuildSpecDocumentSummary(content)
            encoded = encoded + 1
        else
            reused = reused + 1
        end
    end
    profile.contentBySpec = {}
    profile.contentBySpecPack = nil
    profile._yhudSpecDocumentProjection = nil
    ClearSpecDocumentStateProjection(profile)
    profile.specDocuments = {
        version = ConfigSets.SPEC_DOCUMENT_VERSION,
        blocks = blocks,
        summaries = summaries,
    }
    local documents, validateCode = ValidateSpecDocuments(profile)
    if not documents then return nil, validateCode end
    ConfigSets.lastSpecDocumentStats = {
        decoded = 0,
        encoded = encoded,
        reused = reused,
        total = 0,
    }
    for _ in pairs(blocks) do
        ConfigSets.lastSpecDocumentStats.total =
            ConfigSets.lastSpecDocumentStats.total + 1
    end
    return profile, nil, {
        version = ConfigSets.SPEC_DOCUMENT_VERSION,
        blocks = blocks,
        summaries = summaries,
    }
end

function ConfigSets:EncodeSpecDocuments(
    profile,
    previousDocuments,
    dirtySpecs,
    summaryOverrides
)
    return EncodeSpecDocuments(
        profile,
        previousDocuments,
        dirtySpecs,
        summaryOverrides
    )
end

local function BuildSparseDelta(value, defaultValue)
    if type(value) ~= "table" then
        if value == defaultValue then return nil end
        return value
    end
    if type(defaultValue) ~= "table" then
        return YHUD:CopyValue(value)
    end
    local delta
    for key, item in pairs(value) do
        local itemDelta = BuildSparseDelta(item, defaultValue[key])
        if itemDelta ~= nil then
            delta = delta or {}
            delta[key] = itemDelta
        end
    end
    return delta
end

local function CompactResourceSettings(profile, groupId)
    if groupId == nil and profile.resources and profile.resources.byGroup then
        for id in pairs(profile.resources.byGroup) do
            CompactResourceSettings(profile, id)
        end
        return profile
    end
    local resources = YHUD:GetResourceConfig(profile, groupId)
    local settings = resources
        and type(resources.settingsByResource) == "table"
        and resources.settingsByResource or nil
    local catalog = YHUD.ResourceCatalog
    if not (settings and catalog and catalog.GetDefinitionIds
        and YHUD._GetResourceSettingStorageBaseline) then
        return profile
    end
    local resourceGroupId = groupId or (YHUD.GROUP_IDS and YHUD.GROUP_IDS.RESOURCES)
    local resourceStyle = resourceGroupId
        and type(profile.style) == "table"
        and type(profile.style.groups) == "table"
        and profile.style.groups[resourceGroupId] or nil
    local initialBorderColor = type(resourceStyle) == "table"
        and resourceStyle.borderColor or nil
    local compact = {}
    local definitionIds = catalog:GetDefinitionIds()
    for index = 1, #definitionIds do
        local resourceId = definitionIds[index]
        local setting = settings[resourceId]
            or YHUD:GetResourceSetting(profile, resourceId, groupId)
        if setting then
            local defaults = YHUD:_GetResourceSettingStorageBaseline(
                resourceId,
                initialBorderColor
            )
            local delta = BuildSparseDelta(setting, defaults)
            if setting.heightOverride == nil
                and defaults.heightOverride ~= nil then
                delta = delta or {}
                delta.heightOverride = false
            end
            if delta then compact[resourceId] = delta end
        end
    end
    resources.settingsByResource = compact
    resources.settingsDeltaVersion =
        YHUD._RESOURCE_SETTINGS_DELTA_VERSION or 1
    return profile
end

local DEFAULT_SLOT_PRESET_KEYS = { "slot:13", "slot:14" }
local DEFAULT_MONITOR_REDUNDANT_FIELDS = {
    id = true,
    entryKey = true,
    sourceKey = true,
    groupId = true,
    order = true,
    contentScope = true,
    origin = true,
    officialCategory = true,
}

local function BuildDefaultMonitorDelta(monitor)
    local delta = {}
    for key, value in pairs(monitor or {}) do
        if not DEFAULT_MONITOR_REDUNDANT_FIELDS[key] then
            delta[key] = YHUD:CopyValue(value)
        end
    end
    if delta.enabled == true then delta.enabled = nil end
    if delta.view == "icon" then delta.view = nil end
    if delta.visibilityMode == "active" then delta.visibilityMode = nil end
    return next(delta) and delta or nil
end

local function CompactDefaultSlotPresets(profile)
    local overridesBySpec = type(profile.defaultPresetOverridesBySpec)
            == "table" and profile.defaultPresetOverridesBySpec or {}
    for specKey, content in pairs(profile.contentBySpec or {}) do
        if YHUD:IsStableSpecKey(specKey) and type(content) == "table" then
            local specOverrides = {}
            for key, value in pairs(type(overridesBySpec[specKey]) == "table"
                and overridesBySpec[specKey] or {}) do
                specOverrides[key] = YHUD:CopyValue(value)
            end
            local slotRecords = {}
            for slotIndex = 1, #DEFAULT_SLOT_PRESET_KEYS do
                local entryKey = DEFAULT_SLOT_PRESET_KEYS[slotIndex]
                for candidateId, candidate in pairs(content.monitors or {}) do
                    if candidate.entryKey == entryKey then
                        slotRecords[entryKey] = {
                            monitorId = candidateId,
                            monitor = candidate,
                        }
                        break
                    end
                end
            end
            for slotIndex = 1, #DEFAULT_SLOT_PRESET_KEYS do
                local entryKey = DEFAULT_SLOT_PRESET_KEYS[slotIndex]
                local record = slotRecords[entryKey]
                local monitorId = record and record.monitorId
                local monitor = record and record.monitor
                if monitor then
                    local members = content.groupMembers
                        and content.groupMembers[monitor.groupId] or {}
                    local memberIndex
                    for index = 1, #members do
                        if members[index] == monitorId then
                            memberIndex = index
                            break
                        end
                    end
                    local monitorDelta = BuildDefaultMonitorDelta(monitor)
                    local override = {}
                    local defaultGroupId =
                        YHUD.DEFAULT_SLOT_PRESET_GROUP_ID
                        or YHUD.GROUP_IDS.TRINKETS
                    if monitor.groupId ~= defaultGroupId then
                        override.groupId = monitor.groupId
                    end
                    if monitorDelta then override.monitor = monitorDelta end
                    specOverrides[entryKey] = next(override) and override or nil
                    content.monitors[monitorId] = nil
                    if memberIndex then table.remove(members, memberIndex) end
                end
                content.entries[entryKey] = nil
            end
            for groupId, members in pairs(content.groupMembers or {}) do
                for index = 1, #members do
                    local monitor = content.monitors[members[index]]
                    if monitor then
                        monitor.groupId = groupId
                        monitor.order = index
                    end
                end
            end
            overridesBySpec[specKey] = next(specOverrides)
                and specOverrides or nil
        end
    end
    profile.defaultPresetOverridesBySpec = overridesBySpec
    return profile
end

local OFFICIAL_ORIGIN = "official-cdm"
local OFFICIAL_REF_PREFIX = "official:"
local PRESET_REF_PREFIX = "preset:"
local CUSTOM_REF_PREFIX = "custom:"
local LEGACY_EQUIPMENT_AURA_ENTRY_KEY =
    YHUD.EQUIPMENT_AURA_BUNDLE_ENTRY_KEY or "bundle:equipment-auras"
local LEGACY_EQUIPMENT_AURA_MONITOR_ID =
    YHUD.EQUIPMENT_AURA_BUNDLE_MONITOR_ID
    or "monitor:bundle:equipment-auras"
local LEGACY_EQUIPMENT_AURA_KIND =
    YHUD.EQUIPMENT_AURA_BUNDLE_KIND or "equipmentAura"

local function IsOfficialEntry(entry)
    return type(entry) == "table" and entry.origin == OFFICIAL_ORIGIN
end

local function GetPresetKey(entry, entryKey)
    if type(entry) ~= "table"
        or (entry.origin ~= "preset" and entry.presetKey == nil
            and entry.presetId == nil) then
        return nil
    end
    local presetKey = entry.presetKey or entry.presetId or entryKey
    return type(presetKey) == "string" and presetKey ~= ""
        and presetKey or nil
end

local function GetCompactedPresetKey(entry, entryKey)
    if entryKey == "slot:13" or entryKey == "slot:14" then
        return entryKey
    end
    if not (YHUD.IsDefaultSlotPresetEntry
        and YHUD:IsDefaultSlotPresetEntry(entry)) then
        return nil
    end
    return GetPresetKey(entry, entryKey)
end

local function ArraysEqual(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function FindArrayValue(values, target)
    for index = 1, #values do
        if values[index] == target then return index end
    end
    return nil
end

local function MergeDormantOfficialRefs(actual, previous, presentOfficial)
    local result = YHUD:CopyValue(actual)
    for index = 1, #(previous or {}) do
        local ref = previous[index]
        local entryKey = type(ref) == "string"
            and ref:sub(1, #OFFICIAL_REF_PREFIX) == OFFICIAL_REF_PREFIX
            and ref:sub(#OFFICIAL_REF_PREFIX + 1) or nil
        if entryKey and not presentOfficial[entryKey]
            and not FindArrayValue(result, ref) then
            local insertAt
            for anchorIndex = index - 1, 1, -1 do
                local anchorAt = FindArrayValue(result, previous[anchorIndex])
                if anchorAt then
                    insertAt = anchorAt + 1
                    break
                end
            end
            if not insertAt then
                for anchorIndex = index + 1, #previous do
                    local anchorAt = FindArrayValue(
                        result,
                        previous[anchorIndex]
                    )
                    if anchorAt then
                        insertAt = anchorAt
                        break
                    end
                end
            end
            table.insert(result, insertAt or (#result + 1), ref)
        end
    end
    return result
end

local function NormalizeStateEffects(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    local keys = { "auraTimer", "auraHighlight", "inactiveDesaturate" }
    for index = 1, #keys do
        local key = keys[index]
        if type(value[key]) == "boolean" then result[key] = value[key] end
    end
    return next(result) and result or nil
end

local function NormalizeMonitorOverride(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    if value.enabled == false then result.enabled = false end
    if value.visibilityMode == "always" then
        result.visibilityMode = "always"
    end
    if value.view == "icon" or value.view == "bar"
        or value.view == "ring" then
        result.view = value.view
    end
    if type(value.appearanceOverride) == "table" then
        result.appearanceOverride =
            YHUD:NormalizeMonitorAppearanceOverride(value.appearanceOverride)
    end
    if type(value.glow) == "table" then
        result.glow = YHUD:NormalizeMonitorGlow(value.glow)
    end
    if type(value.sound) == "table" then
        result.sound = YHUD:NormalizeMonitorSound(value.sound)
    end
    if type(value.nativeProcGlowOverride) == "table" then
        result.nativeProcGlowOverride = YHUD:NormalizeNativeProcGlow(
            value.nativeProcGlowOverride
        )
    end
    result.stateEffects = NormalizeStateEffects(value.stateEffects)
    return next(result) and result or nil
end

local function NormalizeOfficialOverrides(profile)
    local source = type(profile.officialOverridesBySpec) == "table"
        and profile.officialOverridesBySpec or {}
    local normalized = {}
    for specKey, value in pairs(source) do
        if YHUD:IsStableSpecKey(specKey) and type(value) == "table" then
            local item = {}
            if type(value.groups) == "table" then
                local groups = {}
                local seenRefs = {}
                local groupOrder = profile.groups and profile.groups.order or {}
                for groupIndex = 1, #groupOrder do
                    local groupId = groupOrder[groupIndex]
                    local refs = value.groups[groupId]
                    if type(refs) == "table" then
                        local list = {}
                        for index = 1, #refs do
                            local ref = refs[index]
                            if type(ref) == "string" and not seenRefs[ref]
                                and (ref:sub(1, #OFFICIAL_REF_PREFIX)
                                        == OFFICIAL_REF_PREFIX
                                    or ref:sub(1, #PRESET_REF_PREFIX)
                                        == PRESET_REF_PREFIX
                                    or ref:sub(1, #CUSTOM_REF_PREFIX)
                                        == CUSTOM_REF_PREFIX) then
                                list[#list + 1] = ref
                                seenRefs[ref] = true
                            end
                        end
                        groups[groupId] = list
                    end
                end
                if next(groups) then item.groups = groups end
            end
            if type(value.monitors) == "table" then
                local monitors = {}
                for entryKey, override in pairs(value.monitors) do
                    if type(entryKey) == "string" then
                        override = NormalizeMonitorOverride(override)
                        if override then monitors[entryKey] = override end
                    end
                end
                if next(monitors) then item.monitors = monitors end
            end
            if type(value.suppressed) == "table" then
                local suppressed = {}
                for entryKey, hidden in pairs(value.suppressed) do
                    if type(entryKey) == "string" and hidden == true then
                        suppressed[entryKey] = true
                    end
                end
                if next(suppressed) then item.suppressed = suppressed end
            end
            if next(item) then normalized[specKey] = item end
        end
    end
    profile.officialOverridesBySpec = normalized
    return normalized
end

local function GetDefaultView(profile, groupId)
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    local model = YHUD.ProfileModel
    return group and model and model.GetDefaultView
        and model:GetDefaultView(group.layout) or nil
end

local function BuildMonitorOverride(profile, monitor)
    local result = {}
    if monitor.enabled == false then result.enabled = false end
    if monitor.visibilityMode == "always" then
        result.visibilityMode = "always"
    end
    local defaultView = GetDefaultView(profile, monitor.groupId)
    if monitor.view and monitor.view ~= defaultView then
        result.view = monitor.view
    end
    if type(monitor.appearanceOverride) == "table" then
        result.appearanceOverride =
            YHUD:CopyValue(monitor.appearanceOverride)
    end
    if type(monitor.glow) == "table" then
        result.glow = YHUD:CopyValue(monitor.glow)
    end
    if type(monitor.sound) == "table" then
        result.sound = YHUD:CopyValue(monitor.sound)
    end
    if type(monitor.nativeProcGlowOverride) == "table" then
        result.nativeProcGlowOverride = YHUD:CopyValue(
            monitor.nativeProcGlowOverride
        )
    end
    if type(monitor.stateEffects) == "table" then
        result.stateEffects = YHUD:CopyValue(monitor.stateEffects)
    end
    return next(result) and result or nil
end

local function BuildSpecOverrides(profile, content, previous)
    if type(content) ~= "table" then return nil end
    local result = {}
    local officialByMonitor = {}
    local presetByMonitor = {}
    local presentOfficial = {}
    local orderedOfficial = {}
    for entryKey, entry in pairs(content.entries or {}) do
        if IsOfficialEntry(entry) then
            presentOfficial[entryKey] = true
            orderedOfficial[#orderedOfficial + 1] = {
                entryKey = entryKey,
                groupId = YHUD.DEFAULT_GROUP_BY_CATEGORY
                    and YHUD.DEFAULT_GROUP_BY_CATEGORY[entry.officialCategory],
                order = tonumber(entry.order) or math.huge,
            }
        end
    end
    table.sort(orderedOfficial, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        return left.entryKey < right.entryKey
    end)

    local monitorOverrides = {}
    for monitorId, monitor in pairs(content.monitors or {}) do
        local entry = type(monitor) == "table"
            and content.entries[monitor.entryKey] or nil
        if IsOfficialEntry(entry) then
            officialByMonitor[monitorId] = monitor.entryKey
            local override = BuildMonitorOverride(profile, monitor)
            if override then monitorOverrides[monitor.entryKey] = override end
        else
            local presetKey = GetCompactedPresetKey(entry, monitor.entryKey)
                or GetPresetKey(entry, monitor.entryKey)
            if presetKey then presetByMonitor[monitorId] = presetKey end
        end
    end
    for entryKey, override in pairs(previous and previous.monitors or {}) do
        if not presentOfficial[entryKey] then
            monitorOverrides[entryKey] = YHUD:CopyValue(override)
        end
    end
    local suppressed = {}
    for entryKey, hidden in pairs(content.suppressedOfficial or {}) do
        if hidden == true then suppressed[entryKey] = true end
    end
    for entryKey, hidden in pairs(previous and previous.suppressed or {}) do
        if hidden == true and not presentOfficial[entryKey] then
            suppressed[entryKey] = true
        end
    end
    if next(suppressed) then result.suppressed = suppressed end

    local groupItems = profile.groups and profile.groups.items or {}
    local baselineByGroup = {}
    for index = 1, #orderedOfficial do
        local row = orderedOfficial[index]
        if row.groupId and suppressed[row.entryKey] ~= true then
            local refs = baselineByGroup[row.groupId]
            if not refs then
                refs = {}
                baselineByGroup[row.groupId] = refs
            end
            refs[#refs + 1] = OFFICIAL_REF_PREFIX .. row.entryKey
        end
    end
    local defaultPresetGroupId = YHUD.DEFAULT_SLOT_PRESET_GROUP_ID
    if defaultPresetGroupId and groupItems[defaultPresetGroupId] then
        local baseline = baselineByGroup[defaultPresetGroupId]
        if not baseline then
            baseline = {}
            baselineByGroup[defaultPresetGroupId] = baseline
        end
        baseline[#baseline + 1] = PRESET_REF_PREFIX .. "slot:13"
        baseline[#baseline + 1] = PRESET_REF_PREFIX .. "slot:14"
    end

    local groups = {}
    for groupId in pairs(groupItems) do
        local actual = {}
        local members = content.groupMembers
            and content.groupMembers[groupId] or {}
        for index = 1, #members do
            local monitorId = members[index]
            local entryKey = officialByMonitor[monitorId]
            if entryKey then
                actual[#actual + 1] = OFFICIAL_REF_PREFIX .. entryKey
            elseif presetByMonitor[monitorId] then
                actual[#actual + 1] = PRESET_REF_PREFIX
                    .. presetByMonitor[monitorId]
            elseif content.monitors and content.monitors[monitorId] then
                actual[#actual + 1] = CUSTOM_REF_PREFIX .. monitorId
            end
        end
        actual = MergeDormantOfficialRefs(
            actual,
            previous and previous.groups and previous.groups[groupId],
            presentOfficial
        )
        local baseline = baselineByGroup[groupId] or {}
        if not ArraysEqual(actual, baseline) then groups[groupId] = actual end
    end
    if next(groups) then result.groups = groups end
    if next(monitorOverrides) then result.monitors = monitorOverrides end
    return next(result) and result or nil
end

local function CompactOfficialContent(profile)
    local overrides = NormalizeOfficialOverrides(profile)
    local compactBySpec = {}
    for specKey, content in pairs(profile.contentBySpec or {}) do
        if YHUD:IsStableSpecKey(specKey) and type(content) == "table" then
            local hasCompactedOrderIdentity = false
            for entryKey, entry in pairs(content.entries or {}) do
                if IsOfficialEntry(entry)
                    or GetCompactedPresetKey(entry, entryKey) then
                    hasCompactedOrderIdentity = true
                    break
                end
            end
            if hasCompactedOrderIdentity
                or next(content.suppressedOfficial or {}) then
                local derived = BuildSpecOverrides(
                    profile,
                    content,
                    overrides[specKey]
                )
                if derived then overrides[specKey] = derived
                else overrides[specKey] = nil end
            end

            local officialMonitorIds = {}
            for monitorId, monitor in pairs(content.monitors or {}) do
                local entry = type(monitor) == "table"
                    and content.entries[monitor.entryKey] or nil
                if IsOfficialEntry(entry) then
                    officialMonitorIds[monitorId] = true
                end
            end
            for monitorId in pairs(officialMonitorIds) do
                content.monitors[monitorId] = nil
            end
            for entryKey, entry in pairs(content.entries or {}) do
                if IsOfficialEntry(entry) then content.entries[entryKey] = nil end
            end
            for groupId, members in pairs(content.groupMembers or {}) do
                local retained = {}
                for index = 1, #members do
                    local monitorId = members[index]
                    if content.monitors[monitorId] then
                        retained[#retained + 1] = monitorId
                    end
                end
                content.groupMembers[groupId] = retained
            end
            content.initialization = nil
            content.suppressedOfficial = nil
            content.projectionOrder = nil
            if next(content.entries or {}) or next(content.monitors or {}) then
                compactBySpec[specKey] = content
            end
        end
    end
    profile.contentBySpec = compactBySpec
    profile.officialOverridesBySpec = overrides
    return profile
end

local function FreezeMixedAuraDesaturation(profile)
    if type(YHUD.IsFilteredAuraMonitor) ~= "function" then return profile end
    local groups = profile.groups and profile.groups.items or {}
    local derivedGroupIds = {}
    for _, groupId in pairs(YHUD.DEFAULT_GROUP_BY_CATEGORY or {}) do
        derivedGroupIds[groupId] = true
    end
    for specKey, content in pairs(profile.contentBySpec or {}) do
        if YHUD:IsStableSpecKey(specKey) and type(content) == "table" then
            for groupId, members in pairs(content.groupMembers or {}) do
                local group = groups[groupId]
                if type(group) == "table" and type(members) == "table" then
                    local mixed = group.layout ~= "icons"
                        and group.layout ~= "bars"
                    local rebuildsDerivedMonitor =
                        derivedGroupIds[groupId] == true
                    local filtered = {}
                    for index = 1, #members do
                        local monitor = content.monitors
                            and content.monitors[members[index]]
                        local entry = monitor and content.entries
                            and content.entries[monitor.entryKey]
                        if monitor and monitor.enabled ~= false then
                            if YHUD:IsFilteredAuraMonitor(entry, monitor) then
                                filtered[#filtered + 1] = {
                                    monitor = monitor,
                                    entry = entry,
                                }
                            else
                                mixed = true
                                if IsOfficialEntry(entry) then
                                    rebuildsDerivedMonitor = true
                                end
                            end
                        end
                    end
                    if mixed and rebuildsDerivedMonitor then
                        for index = 1, #filtered do
                            local item = filtered[index]
                            local effects = type(item.monitor.stateEffects)
                                    == "table"
                                and item.monitor.stateEffects or nil
                            if (not effects
                                    or effects.inactiveDesaturate == nil)
                                and YHUD:GetEffectiveInactiveDesaturate(
                                    profile,
                                    item.monitor,
                                    item.entry
                                ) == false then
                                effects = effects or {}
                                effects.inactiveDesaturate = false
                                item.monitor.stateEffects = effects
                            end
                        end
                    end
                end
            end
        end
    end
    return profile
end

local function ResolveOverrideRef(content, monitorByEntry, monitorByPreset, ref)
    if ref:sub(1, #OFFICIAL_REF_PREFIX) == OFFICIAL_REF_PREFIX then
        return monitorByEntry[ref:sub(#OFFICIAL_REF_PREFIX + 1)]
    end
    if ref:sub(1, #PRESET_REF_PREFIX) == PRESET_REF_PREFIX then
        return monitorByPreset[ref:sub(#PRESET_REF_PREFIX + 1)]
    end
    if ref:sub(1, #CUSTOM_REF_PREFIX) == CUSTOM_REF_PREFIX then
        local monitorId = ref:sub(#CUSTOM_REF_PREFIX + 1)
        return content.monitors[monitorId] and monitorId or nil
    end
    return nil
end

local function BuildCurrentGroupRefs(content, groupId)
    local refs = {}
    local members = content.groupMembers and content.groupMembers[groupId] or {}
    for index = 1, #members do
        local monitorId = members[index]
        local monitor = content.monitors and content.monitors[monitorId]
        local entry = monitor and content.entries and content.entries[monitor.entryKey]
        if IsOfficialEntry(entry) then
            refs[#refs + 1] = OFFICIAL_REF_PREFIX .. monitor.entryKey
        else
            local presetKey = GetCompactedPresetKey(
                entry,
                monitor and monitor.entryKey
            ) or GetPresetKey(entry, monitor and monitor.entryKey)
            if presetKey then
                refs[#refs + 1] = PRESET_REF_PREFIX .. presetKey
            elseif monitor then
                refs[#refs + 1] = CUSTOM_REF_PREFIX .. monitorId
            end
        end
    end
    return refs
end

local function PromoteLegacyPresetIndexes(profile, specKey, content, overrides)
    local allLegacy = type(profile.defaultPresetOverridesBySpec) == "table"
        and profile.defaultPresetOverridesBySpec or nil
    local legacy = allLegacy and allLegacy[specKey]
    if type(legacy) ~= "table" then return false end

    local changed = false
    for presetKey, value in pairs(legacy) do
        local legacyIndex = type(value) == "table" and tonumber(value.index)
        if legacyIndex then
            local presetRef = PRESET_REF_PREFIX .. presetKey
            local alreadyStored = false
            for _, refs in pairs(overrides.groups or {}) do
                if FindArrayValue(refs, presetRef) then
                    alreadyStored = true
                    break
                end
            end

            if not alreadyStored then
                local monitorId
                for candidateId, monitor in pairs(content.monitors or {}) do
                    local entry = content.entries and content.entries[monitor.entryKey]
                    if (GetCompactedPresetKey(entry, monitor.entryKey)
                            or GetPresetKey(entry, monitor.entryKey))
                        == presetKey then
                        monitorId = candidateId
                        break
                    end
                end
                local monitor = monitorId and content.monitors[monitorId]
                local groupId = monitor and monitor.groupId
                if groupId and profile.groups and profile.groups.items
                    and profile.groups.items[groupId] then
                    local storedRefs = overrides.groups
                        and overrides.groups[groupId]
                    local refs = type(storedRefs) == "table"
                        and YHUD:CopyValue(storedRefs)
                        or BuildCurrentGroupRefs(content, groupId)
                    local currentIndex = FindArrayValue(refs, presetRef)
                    if currentIndex then table.remove(refs, currentIndex) end
                    legacyIndex = math.max(1, math.min(
                        math.floor(legacyIndex),
                        #refs + 1
                    ))
                    table.insert(refs, legacyIndex, presetRef)
                    overrides.groups = overrides.groups or {}
                    overrides.groups[groupId] = refs
                    changed = true
                end
            end

            value.index = nil
            if next(value) == nil then legacy[presetKey] = nil end
        end
    end
    if next(legacy) == nil then allLegacy[specKey] = nil end
    if next(allLegacy) == nil then profile.defaultPresetOverridesBySpec = nil end
    return changed
end

local function ApplySpecOverrides(profile, specKey, options)
    options = type(options) == "table" and options or {}
    local skipPlacementEntryKeys = type(options.skipPlacementEntryKeys) == "table"
        and options.skipPlacementEntryKeys or nil
    local allOverrides = NormalizeOfficialOverrides(profile)
    local overrides = allOverrides[specKey]
    local content = profile.contentBySpec and profile.contentBySpec[specKey]
    if type(content) ~= "table" then return profile end

    if not overrides then
        local legacy = type(profile.defaultPresetOverridesBySpec) == "table"
            and profile.defaultPresetOverridesBySpec[specKey]
        if type(legacy) ~= "table" then return profile end
        overrides = {}
        allOverrides[specKey] = overrides
    end
    PromoteLegacyPresetIndexes(profile, specKey, content, overrides)
    if next(overrides) == nil then
        allOverrides[specKey] = nil
        return profile
    end

    local monitorByEntry = {}
    local monitorByPreset = {}
    for monitorId, monitor in pairs(content.monitors or {}) do
        local entry = type(monitor) == "table"
            and content.entries[monitor.entryKey] or nil
        if IsOfficialEntry(entry) then
            monitorByEntry[monitor.entryKey] = monitorId
        else
            local presetKey = GetCompactedPresetKey(entry, monitor.entryKey)
                or GetPresetKey(entry, monitor.entryKey)
            if presetKey then monitorByPreset[presetKey] = monitorId end
        end
    end

    local desiredByGroup = {}
    local assignedGroup = {}
    for groupId, refs in pairs(overrides.groups or {}) do
        if profile.groups and profile.groups.items
            and profile.groups.items[groupId] then
            local desired = {}
            local seen = {}
            for index = 1, #refs do
                local monitorId = ResolveOverrideRef(
                    content,
                    monitorByEntry,
                    monitorByPreset,
                    refs[index]
                )
                local monitor = monitorId and content.monitors[monitorId]
                local skipPlacement = monitor
                    and skipPlacementEntryKeys
                    and skipPlacementEntryKeys[monitor.entryKey] == true
                if monitorId and not skipPlacement and not seen[monitorId] then
                    desired[#desired + 1] = monitorId
                    seen[monitorId] = true
                    assignedGroup[monitorId] = groupId
                end
            end
            desiredByGroup[groupId] = desired
        end
    end

    for groupId in pairs(profile.groups and profile.groups.items or {}) do
        local desired = desiredByGroup[groupId]
        local nextMembers = {}
        local seen = {}
        if desired ~= nil then
            for index = 1, #desired do
                local monitorId = desired[index]
                nextMembers[#nextMembers + 1] = monitorId
                seen[monitorId] = true
            end
        end
        local current = content.groupMembers
            and content.groupMembers[groupId] or {}
        for index = 1, #current do
            local monitorId = current[index]
            local assigned = assignedGroup[monitorId]
            if content.monitors[monitorId] and not seen[monitorId]
                and (assigned == nil or assigned == groupId) then
                nextMembers[#nextMembers + 1] = monitorId
                seen[monitorId] = true
            end
        end
        content.groupMembers[groupId] = nextMembers
        local defaultView = GetDefaultView(profile, groupId)
        for index = 1, #nextMembers do
            local monitor = content.monitors[nextMembers[index]]
            if monitor then
                monitor.groupId = groupId
                monitor.order = index
                local entry = content.entries[monitor.entryKey]
                if IsOfficialEntry(entry) and defaultView then
                    monitor.view = defaultView
                end
            end
        end
    end

    for entryKey, override in pairs(overrides.monitors or {}) do
        local monitorId = monitorByEntry[entryKey]
        local monitor = monitorId and content.monitors[monitorId]
        if monitor then
            local entry = content.entries[entryKey]
            local group = profile.groups and profile.groups.items
                and profile.groups.items[monitor.groupId]
            if override.enabled == false then monitor.enabled = false end
            if override.visibilityMode == "always" then
                monitor.visibilityMode = "always"
            end
            local defaultView = group
                and GetDefaultView(profile, monitor.groupId) or nil
            if defaultView then monitor.view = defaultView end
            override.view = nil
            monitor.appearanceOverride = group
                and YHUD.ProfileModel:NormalizeMonitorAppearanceForLayout(
                    override.appearanceOverride,
                    group.layout
                ) or nil
            override.appearanceOverride =
                YHUD:CopyValue(monitor.appearanceOverride)
            monitor.glow = YHUD:CopyValue(override.glow)
            monitor.sound = YHUD:CopyValue(override.sound)
            monitor.nativeProcGlowOverride = YHUD:CopyValue(
                override.nativeProcGlowOverride
            )
            monitor.stateEffects = YHUD:NormalizeMonitorStateEffects(
                override.stateEffects,
                entry
            )
        end
    end
    return profile
end

local function CollectCompactedPresetOrderSpecs(profile)
    local result = {}
    if type(profile) ~= "table" then return result end
    local overridesBySpec = type(profile.officialOverridesBySpec) == "table"
        and profile.officialOverridesBySpec or {}
    for specKey, overrides in pairs(overridesBySpec) do
        local content = profile.contentBySpec and profile.contentBySpec[specKey]
        if type(content) == "table" and type(overrides) == "table"
            and type(overrides.groups) == "table" then
            local present = {}
            for _, monitor in pairs(content.monitors or {}) do
                if monitor.entryKey == "slot:13"
                    or monitor.entryKey == "slot:14" then
                    present[monitor.entryKey] = true
                end
            end
            for _, refs in pairs(overrides.groups) do
                if type(refs) == "table" then
                    for index = 1, #refs do
                        local ref = refs[index]
                        local presetKey = type(ref) == "string"
                            and ref:match("^preset:(slot:1[34])$") or nil
                        if presetKey and not present[presetKey] then
                            result[specKey] = true
                            break
                        end
                    end
                end
                if result[specKey] then break end
            end
        end
    end
    return result
end

local function ApplyCompactedPresetOrderSpecs(profile, specs)
    for specKey in pairs(specs or {}) do
        profile = ApplySpecOverrides(profile, specKey)
    end
    return profile
end

local ExpandAllSpecDocuments

function ConfigSets:RetireLegacyTrinketGroup(profile)
    if not YHUD:HasLegacyTrinketGroup(profile) then return profile end
    if (tonumber(profile.schemaVersion) or 0) > YHUD.SCHEMA_VERSION then
        return nil, "incompatible-schema"
    end
    -- Decode every specialization on a private copy before changing any root.
    profile = YHUD:CopyValue(profile)
    local code
    if profile.specDocuments then
        profile, code = ExpandAllSpecDocuments(profile)
    else
        profile, code = UnpackContentBySpec(profile)
    end
    if not profile then return nil, code end
    return YHUD:RetireLegacyTrinketGroup(profile)
end

local function NormalizeRuntimeProfile(profile, specKey)
    local code
    if YHUD:HasLegacyTrinketGroup(profile) then
        profile, code = ConfigSets:PrepareProfileForStorage(profile, true)
        if not profile then return nil, code end
    end
    if type(profile) == "table" and type(profile.specDocuments) == "table" then
        local documents, code = ValidateSpecDocuments(profile)
        if not documents then return nil, code end
        profile.contentBySpec = type(profile.contentBySpec) == "table"
            and profile.contentBySpec or {}
        local storageOnly = next(profile.contentBySpec) == nil
        if storageOnly then
            ClearSpecDocumentStateProjection(profile)
        end
        profile = YHUD:NormalizeProfile(profile, specKey)
        if storageOnly then ClearSpecDocumentStateProjection(profile) end
        profile.specDocuments = documents
        return profile
    end
    local compactedPresetOrderSpecs =
        CollectCompactedPresetOrderSpecs(profile)
    profile = YHUD:NormalizeProfile(profile, specKey)
    return ApplyCompactedPresetOrderSpecs(
        profile,
        compactedPresetOrderSpecs
    )
end

function ConfigSets:NormalizeRuntimeProfile(profile, specKey, owned)
    if owned ~= true or YHUD:HasLegacyTrinketGroup(profile) then
        profile = YHUD:CopyValue(profile)
    end
    YHUD:MigrateClientSpecializationKeys(profile)
    local normalized, code = NormalizeRuntimeProfile(
        profile,
        specKey or YHUD:GetCurrentSpecKey()
    )
    return normalized, code
end

local function IsLegacyEquipmentAuraEntry(entry)
    return type(entry) == "table"
        and entry.entryKey == LEGACY_EQUIPMENT_AURA_ENTRY_KEY
        and entry.sourceKey == LEGACY_EQUIPMENT_AURA_ENTRY_KEY
        and entry.bundleKind == LEGACY_EQUIPMENT_AURA_KIND
end

local function MigrateLegacyEquipmentAuraBundle(profile, specKey)
    local content = YHUD:GetContent(profile, specKey, false)
    if not content then return profile, "unavailable" end
    local contentEntry = content.entries[LEGACY_EQUIPMENT_AURA_ENTRY_KEY]
    local contentMonitor = content.monitors[LEGACY_EQUIPMENT_AURA_MONITOR_ID]
    if not IsLegacyEquipmentAuraEntry(contentEntry) or not contentMonitor
        or contentMonitor.entryKey ~= LEGACY_EQUIPMENT_AURA_ENTRY_KEY then
        return profile, "not-needed"
    end
    local scoped = YHUD:GetScopedProfile(profile, specKey, true)
    if not scoped then return profile, "unavailable" end
    local legacyEntry = scoped.entries[LEGACY_EQUIPMENT_AURA_ENTRY_KEY]
    local legacyMonitor = scoped.monitors[LEGACY_EQUIPMENT_AURA_MONITOR_ID]
    if not IsLegacyEquipmentAuraEntry(legacyEntry) or not legacyMonitor
        or legacyMonitor.entryKey ~= LEGACY_EQUIPMENT_AURA_ENTRY_KEY then
        return profile, "not-needed"
    end

    legacyEntry.name = nil
    legacyEntry.nameKey = "designer.quick_equipment_auras"
    legacyEntry.bundleEnabled = legacyEntry.bundleEnabled ~= false
    legacyEntry.semantic = "buff"
    legacyEntry.origin = "preset"
    legacyEntry.contentScope = YHUD.CONTENT_SCOPE_SPEC
    legacyEntry.applicability = nil
    legacyEntry.presetKey = LEGACY_EQUIPMENT_AURA_ENTRY_KEY
    legacyEntry.crossSpecMaterialization = "deferred"
    legacyEntry.compatibleViews = {
        icon = true,
        bar = true,
        ring = true,
    }
    legacyMonitor.contentScope = YHUD.CONTENT_SCOPE_SPEC
    local persisted, code = YHUD:PersistScopedProfile(scoped)
    if not persisted then return profile, code or "persist-failed" end
    return YHUD:GetCanonicalProfile(persisted), "retained-unified-preset"
end

ConfigSets.MigrateLegacyEquipmentAuraBundle = MigrateLegacyEquipmentAuraBundle

local function RuntimeStageNowMS(enabled)
    if enabled ~= true or type(debugprofilestop) ~= "function" then
        return nil
    end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function RecordRuntimeStage(stages, field, startedAt)
    if not (stages and field and startedAt) then return end
    local finishedAt = RuntimeStageNowMS(true)
    if finishedAt then
        stages[field] = math.max(0, finishedAt - startedAt)
    end
end

local function MaterializeExpandedProfile(profile, specKey, stages)
    specKey = specKey or YHUD:GetCurrentSpecKey()
    YHUD.lastSpecializationMigrationReport = nil
    local startedAt = RuntimeStageNowMS(stages ~= nil)
    local normalizeCode
    profile, normalizeCode = NormalizeRuntimeProfile(profile, specKey)
    if not profile then return nil, normalizeCode end
    RecordRuntimeStage(stages, "normalizeMS", startedAt)
    local specializationMigration = YHUD.ConsumeSpecializationMigrationReport
        and YHUD:ConsumeSpecializationMigrationReport() or nil
    local overrides = NormalizeOfficialOverrides(profile)
    local specOverrides = overrides[specKey]
    if specOverrides then
        local content = YHUD:GetContent(profile, specKey, true)
        content.suppressedOfficial =
            YHUD:CopyValue(specOverrides.suppressed or {})
    end
    if not (YHUD.CDMCatalog and YHUD.CDMCatalog.ReconcileContext) then
        return nil, "cdm-catalog-unavailable"
    end
    startedAt = RuntimeStageNowMS(stages ~= nil)
    local materialized, report, runtimeProfile =
        YHUD.CDMCatalog:ReconcileContext(
        profile,
        specKey,
        {
            allowEmpty = true,
            reason = "config-materialize",
            runtimeOwned = true,
        }
    )
    RecordRuntimeStage(stages, "catalogMS", startedAt)
    if not materialized then return nil, report end
    materialized = YHUD:GetCanonicalProfile(materialized)
    if type(materialized) ~= "table" then
        return nil, "invalid-profile"
    end
    startedAt = RuntimeStageNowMS(stages ~= nil)
    local migrationState
    materialized, migrationState = MigrateLegacyEquipmentAuraBundle(
        materialized,
        specKey
    )
    if type(report) == "table" then
        report.legacyEquipmentAuraMigration = migrationState
        report.specializationOwnershipMigration = specializationMigration
    end
    NormalizeOfficialOverrides(materialized)
    if migrationState ~= "not-needed" then runtimeProfile = nil end
    if stages then
        stages.preparedRuntime = runtimeProfile ~= nil
    end
    RecordRuntimeStage(stages, "finalizeMS", startedAt)
    return materialized, report, runtimeProfile
end

function ConfigSets:MaterializeProfile(profile, specKey, owned, options)
    options = type(options) == "table" and options or nil
    local stages = options and options.traceStages == true and {} or nil
    local startedAt = RuntimeStageNowMS(stages ~= nil)
    if owned ~= true then profile = YHUD:CopyValue(profile) end
    RecordRuntimeStage(stages, "copyMS", startedAt)
    specKey = specKey or YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        if YHUD:IsInitialSpecialization() then
            return YHUD:CreateInitialResourceProfile(profile), {
                changed = false,
                resourceOnly = true,
            }
        end
        return nil, "invalid-spec-key"
    end
    if YHUD:HasLegacyTrinketGroup(profile) then
        local retirementCode
        profile, retirementCode = self:PrepareProfileForStorage(profile, true)
        if not profile then return nil, retirementCode end
    end
    if type(profile) == "table" and type(profile.specDocuments) == "table" then
        startedAt = RuntimeStageNowMS(stages ~= nil)
        local documents, documentCode = ValidateSpecDocuments(profile)
        if not documents then return nil, documentCode end
        local content, contentCode = DecodeSpecDocument(
            profile,
            specKey,
            true
        )
        if not content then return nil, contentCode end
        profile._yhudSpecDocumentProjection = true
        RecordRuntimeStage(stages, "decodeMS", startedAt)
        local materialized, report, runtimeProfile = MaterializeExpandedProfile(
            profile,
            specKey,
            stages
        )
        if not materialized then return nil, report end
        if type(report) == "table" then report.runtimeStages = stages end
        return materialized, report, {
            version = ConfigSets.SPEC_DOCUMENT_VERSION,
            blocks = documents.blocks,
            summaries = documents.summaries,
        }, runtimeProfile
    end
    startedAt = RuntimeStageNowMS(stages ~= nil)
    local unpacked, unpackCode, baseline = UnpackContentBySpec(profile)
    if not unpacked then return nil, unpackCode end
    profile = unpacked
    RecordRuntimeStage(stages, "decodeMS", startedAt)
    local materialized, report, runtimeProfile =
        MaterializeExpandedProfile(profile, specKey, stages)
    if not materialized then return nil, report end
    if type(report) == "table" then report.runtimeStages = stages end
    return materialized, report, baseline, runtimeProfile
end

function ConfigSets:CaptureRuntimeProfile(profile, specKey)
    if type(profile) ~= "table" or not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-profile"
    end
    profile = YHUD:GetCanonicalProfile(profile)
    local snapshot = {}
    for key, value in pairs(profile) do
        if not RUNTIME_SNAPSHOT_OMITTED_FIELDS[key]
            and not (type(key) == "string" and key:sub(1, 5) == "_yhud") then
            snapshot[key] = YHUD:CopyValue(value)
        end
    end
    snapshot.contentBySpec = {}
    local content = type(profile.contentBySpec) == "table"
        and profile.contentBySpec[specKey] or nil
    if type(content) == "table" then
        snapshot.contentBySpec[specKey] = YHUD:CopyValue(content)
    end
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local rootKey = SPEC_DOCUMENT_STATE_FIELDS[index].root
        local value = type(profile[rootKey]) == "table"
            and profile[rootKey][specKey] or nil
        if type(value) == "table" then
            snapshot[rootKey] = {
                [specKey] = YHUD:CopyValue(value),
            }
        end
    end
    if YHUD.LegacySoundMigration then YHUD.LegacySoundMigration:StripCompletedRuntime(snapshot) end
    return snapshot
end

local function ResolveSaveRuntimeSource(
    adapter,
    compacted,
    captured,
    specKey,
    dirtySpecs
)
    if type(dirtySpecs) == "table" and dirtySpecs[specKey] ~= true then
        return captured
    end
    return adapter:CaptureRuntimeProfile(compacted, specKey)
end

local function PrepareExpandedCompactProfile(profile, owned, suppliedBaseline)
    if owned ~= true then profile = YHUD:CopyValue(profile) end
    local retiringTrinkets = YHUD:HasLegacyTrinketGroup(profile)
    local retirementCode, retirementDetail
    profile, retirementCode, retirementDetail = ConfigSets:RetireLegacyTrinketGroup(profile)
    if not profile then return nil, retirementCode, retirementDetail end
    local unpacked, unpackCode, previousPack = UnpackContentBySpec(profile)
    if not unpacked then return nil, unpackCode end
    profile = unpacked
    previousPack = not retiringTrinkets and (suppliedBaseline or previousPack) or nil
    local expandedSummaries = {}
    for specKey, content in pairs(profile.contentBySpec or {}) do
        if YHUD:IsStableSpecKey(specKey) and type(content) == "table" then
            expandedSummaries[specKey] = BuildSpecDocumentSummary(content)
        end
    end
    local compactedPresetOrderSpecs =
        CollectCompactedPresetOrderSpecs(profile)
    local repaired, code, detail =
        YHUD:RepairDanglingGroupAnchors(profile)
    if not repaired then return nil, code, detail end
    profile = YHUD:NormalizeProfile(profile, YHUD:GetCurrentSpecKey())
    for specKey in pairs(expandedSummaries) do
        if type(profile.contentBySpec) ~= "table"
            or type(profile.contentBySpec[specKey]) ~= "table" then
            expandedSummaries[specKey] = nil
        end
    end
    profile = ApplyCompactedPresetOrderSpecs(
        profile,
        compactedPresetOrderSpecs
    )
    profile = FreezeMixedAuraDesaturation(profile)
    profile = CompactResourceSettings(profile)
    profile = CompactOfficialContent(profile)
    profile = CompactDefaultSlotPresets(profile)
    return profile, nil, nil, previousPack, expandedSummaries
end

local function EnsureSpecDocumentCandidates(
    profile,
    previousDocuments,
    dirtySpecs,
    summaries
)
    profile.contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    local candidates = {}
    for specKey in pairs(type(summaries) == "table" and summaries or {}) do
        if not (type(previousDocuments) == "table"
            and type(previousDocuments.blocks) == "table"
            and previousDocuments.blocks[specKey] ~= nil) then
            candidates[specKey] = true
        end
    end
    for specKey, dirty in pairs(
        type(dirtySpecs) == "table" and dirtySpecs or {}
    ) do
        if dirty == true then candidates[specKey] = true end
    end
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local root = profile[SPEC_DOCUMENT_STATE_FIELDS[index].root]
        for specKey in pairs(type(root) == "table" and root or {}) do
            candidates[specKey] = true
        end
    end
    for specKey in pairs(candidates) do
        if not SUPPORTED_SPEC_KEY_SET[specKey] then
            return nil, "invalid-spec-document"
        end
        if type(profile.contentBySpec[specKey]) ~= "table" then
            profile.contentBySpec[specKey] = YHUD:CreateDefaultContent()
        end
        summaries[specKey] = summaries[specKey]
            or BuildSpecDocumentSummary(profile.contentBySpec[specKey])
    end
    return profile
end

local function RetainDirtySpecDocumentProjections(profile, dirtySpecs)
    if type(profile) ~= "table" or type(dirtySpecs) ~= "table" then
        return profile
    end
    local contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    profile.contentBySpec = contentBySpec
    for specKey in pairs(contentBySpec) do
        if dirtySpecs[specKey] ~= true then contentBySpec[specKey] = nil end
    end
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local definition = SPEC_DOCUMENT_STATE_FIELDS[index]
        local root = type(profile[definition.root]) == "table"
            and profile[definition.root] or nil
        if root then
            for specKey in pairs(root) do
                if dirtySpecs[specKey] ~= true then root[specKey] = nil end
            end
        end
    end
    return profile
end

ExpandAllSpecDocuments = function(profile, checkpoint)
    local documents, code = ValidateSpecDocuments(profile)
    if not documents then return nil, code end
    profile.contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    local specKeys = {}
    for specKey in pairs(documents.blocks) do
        specKeys[#specKeys + 1] = specKey
    end
    table.sort(specKeys)
    for index = 1, #specKeys do
        local content
        content, code = DecodeSpecDocument(profile, specKeys[index], false)
        if not content then return nil, code end
        if checkpoint then checkpoint("decode-specialization") end
    end
    profile.specDocuments = nil
    return profile
end

local function ValidateStorageProfile(profile)
    local budget = YHUD.StorageBudget
    local packedBytes = type(profile.contentBySpecPack) == "table"
        and type(profile.contentBySpecPack.data) == "string"
        and #profile.contentBySpecPack.data or nil
    local report, budgetCode = budget and budget.Evaluate
        and budget:Evaluate(profile, packedBytes) or nil
    if budget and not report then return nil, budgetCode end
    ConfigSets.lastStorageBudgetReport = report
    if report and report.hardLimitExceeded then
        return nil, "capacity-exceeded", report
    end
    if report and report.softWarning
        and YHUD.Diagnostics and YHUD.Diagnostics.Record then
        YHUD.Diagnostics:Record("config-storage-budget", {
            status = report.status,
            nodeCount = report.nodeCount,
            softWarningNodes = report.softWarningNodes,
            hardNodeLimit = report.hardNodeLimit,
        })
    end
    return profile, nil, report
end

local function ValidateVisibilityRules(profile)
    local service = YUI.Visibility
    local groups = type(profile) == "table" and profile.groups
    groups = type(groups) == "table" and groups.items or nil
    for _, group in pairs(type(groups) == "table" and groups or {}) do
        local rule = type(group) == "table" and group.visibility or nil
        if type(rule) == "table" and rule.version ~= nil and service then
            local valid, code = service:ValidateBranches(rule, { hover = false })
            if not valid then return nil, code end
        end
    end
    return true
end

function ConfigSets:PrepareProfileForStorage(profile, owned, previousPack)
    local valid, validationCode = ValidateVisibilityRules(profile)
    if not valid then return nil, validationCode end
    if owned ~= true then profile = YHUD:CopyValue(profile) end
    local retirementCode, retirementDetail
    profile, retirementCode, retirementDetail = self:RetireLegacyTrinketGroup(profile)
    if not profile then return nil, retirementCode, retirementDetail end
    YHUD:MigrateClientSpecializationKeys(profile)
    if type(profile) == "table"
        and (tonumber(profile.schemaVersion) or 0) > YHUD.SCHEMA_VERSION then
        return nil, "incompatible-schema"
    end
    if type(profile) == "table" and type(profile.specDocuments) == "table"
        and (type(profile.contentBySpec) ~= "table"
            or next(profile.contentBySpec) == nil) then
        local documents, code = ValidateSpecDocuments(profile)
        if not documents then return nil, code end
        profile = NormalizeRuntimeProfile(
            profile,
            YHUD:GetCurrentSpecKey()
        )
        if not profile then return nil, "invalid-profile" end
        profile.contentBySpec = {}
        ClearSpecDocumentStateProjection(profile)
        return ValidateStorageProfile(profile)
    end
    local code, detail, resolvedBaseline, summaries
    profile, code, detail, resolvedBaseline, summaries =
        PrepareExpandedCompactProfile(profile, true, previousPack)
    if not profile then return nil, code, detail end
    local previousDocuments = type(resolvedBaseline) == "table"
        and resolvedBaseline.version == ConfigSets.SPEC_DOCUMENT_VERSION
        and resolvedBaseline or nil
    profile, code = EnsureSpecDocumentCandidates(
        profile,
        previousDocuments,
        nil,
        summaries
    )
    if not profile then return nil, code end
    local stored, documentCode = EncodeSpecDocuments(
        profile,
        previousDocuments,
        nil,
        summaries
    )
    if not stored then return nil, documentCode end
    return ValidateStorageProfile(stored)
end

-- Native reconciliation owns only one runtime projection. Preserve the complete
-- storage baseline and encode that specialization before replacing live storage.
function ConfigSets:PrepareNativeSyncProfile(canonical, runtimeResult, specKey)
    if not YHUD:IsStableSpecKey(specKey) then return nil, "invalid-spec-key" end
    canonical = YHUD:GetCanonicalProfile(canonical)
    runtimeResult = YHUD:GetCanonicalProfile(runtimeResult)
    local content = type(runtimeResult) == "table"
        and type(runtimeResult.contentBySpec) == "table"
        and runtimeResult.contentBySpec[specKey]
    if type(canonical) ~= "table" or type(content) ~= "table" then
        return nil, "content-not-found"
    end
    local profile, documents, dirtySpecs, code
    if canonical.specDocuments ~= nil then
        documents, code = ValidateSpecDocuments(canonical)
        if not documents then return nil, code end
        profile, code = self:CaptureRuntimeProfile(canonical, specKey)
        dirtySpecs = { [specKey] = true }
    else
        -- Legacy expanded/packed inputs retain their other specs through the
        -- existing one-time conversion; do not fill them from runtime defaults.
        profile, code = UnpackContentBySpec(YHUD:CopyValue(canonical))
    end
    if not profile then return nil, code end
    profile.contentBySpec = profile.contentBySpec or {}
    profile.contentBySpec[specKey] = YHUD:CopyValue(content)
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local rootKey = SPEC_DOCUMENT_STATE_FIELDS[index].root
        local state = type(runtimeResult[rootKey]) == "table"
            and runtimeResult[rootKey][specKey] or nil
        profile[rootKey] = profile[rootKey] or {}
        profile[rootKey][specKey] = YHUD:CopyValue(state)
    end
    local valid
    valid, code = ValidateVisibilityRules(profile)
    if not valid then return nil, code end
    if (tonumber(profile.schemaVersion) or 0) > YHUD.SCHEMA_VERSION then
        return nil, "incompatible-schema"
    end
    if YHUD.LegacySoundMigration then
        YHUD.LegacySoundMigration:StripCompletedRuntime(profile)
    end
    local summaries, detail
    profile, code, detail, documents, summaries =
        PrepareExpandedCompactProfile(profile, true, documents)
    if not profile then return nil, code, detail end
    profile, code = EnsureSpecDocumentCandidates(
        profile, documents, dirtySpecs, summaries
    )
    if not profile then return nil, code end
    profile, code = EncodeSpecDocuments(
        profile, documents, dirtySpecs, summaries
    )
    if not profile then return nil, code end
    return ValidateStorageProfile(profile)
end

function ConfigSets:PrepareProfileForSave(
    profile,
    previousPack,
    specKey,
    owned,
    options
)
    options = type(options) == "table" and options or {}
    local runtimeSource, runtimeCode =
        self:CaptureRuntimeProfile(profile, specKey)
    if not runtimeSource then return nil, runtimeCode end
    local documentBaseline = type(previousPack) == "table"
        and previousPack.version == ConfigSets.SPEC_DOCUMENT_VERSION
        and previousPack or nil
    if documentBaseline and type(options.dirtySpecs) == "table" then
        if owned ~= true then profile = YHUD:CopyValue(profile) end
        profile = RetainDirtySpecDocumentProjections(
            profile,
            options.dirtySpecs
        )
        owned = true
    end
    local compacted, code, detail, baseline, summaries =
        PrepareExpandedCompactProfile(profile, owned, previousPack)
    if not compacted then return nil, code, detail end
    local previousDocuments = type(baseline) == "table"
        and baseline.version == ConfigSets.SPEC_DOCUMENT_VERSION
        and baseline or nil
    compacted, code = EnsureSpecDocumentCandidates(
        compacted,
        previousDocuments,
        options.dirtySpecs,
        summaries
    )
    if not compacted then return nil, code end
    if YHUD.LegacySoundMigration then YHUD.LegacySoundMigration:StripCompletedRuntime(compacted) end
    runtimeSource, code = ResolveSaveRuntimeSource(
        self,
        compacted,
        runtimeSource,
        specKey,
        options.dirtySpecs
    )
    if not runtimeSource then return nil, code end
    local runtimeProfile, runtimeReport = MaterializeExpandedProfile(
        runtimeSource,
        specKey
    )
    if not runtimeProfile then return nil, runtimeReport end
    local stored
    stored, code = EncodeSpecDocuments(
        compacted,
        previousDocuments,
        options.dirtySpecs,
        summaries
    )
    if not stored then return nil, code end
    local storageCode, report
    stored, storageCode, report = ValidateStorageProfile(stored)
    if not stored then return nil, storageCode, report end
    local stats = ConfigSets.lastSpecDocumentStats
    return {
        profile = stored,
        runtimeProfile = runtimeProfile,
        report = report,
        compressedCount = 0,
        serializedCount = stats and stats.encoded or 0,
        reusedCount = stats and stats.reused or 0,
    }
end

-- Sound migration needs the stored records, not default filling or graph reconciliation.
-- Decode through the same validated document reader, yielding only outside codec pcalls.
function ConfigSets:PrepareLegacySoundProfile(profile, checkpoint)
    local valid, code = ValidateVisibilityRules(profile)
    if not valid then return nil, code end
    profile = YHUD:CopyValue(profile)
    if type(profile) ~= 'table' then return nil, 'invalid-profile' end
    if (tonumber(profile.schemaVersion) or 0) > YHUD.SCHEMA_VERSION then return nil, 'incompatible-schema' end
    if type(profile.specDocuments) == 'table' then
        profile, code = ExpandAllSpecDocuments(profile, checkpoint)
    else
        profile, code = UnpackContentBySpec(profile)
    end
    if not profile then return nil, code end
    return ValidateStorageProfile(profile)
end

function ConfigSets:PrepareProfileForTransfer(profile, owned)
    local valid, validationCode = ValidateVisibilityRules(profile)
    if not valid then return nil, validationCode end
    if owned ~= true or YHUD:HasLegacyTrinketGroup(profile) then
        profile = YHUD:CopyValue(profile)
    end
    if type(profile) == "table"
        and (tonumber(profile.schemaVersion) or 0) > YHUD.SCHEMA_VERSION then
        return nil, "incompatible-schema"
    end
    if type(profile) == "table" and type(profile.specDocuments) == "table" then
        local expanded, expandCode = ExpandAllSpecDocuments(profile)
        if not expanded then return nil, expandCode end
        profile = expanded
    end
    local code, detail
    profile, code, detail = PrepareExpandedCompactProfile(profile, true)
    if not profile then return nil, code, detail end
    profile.contentBySpecPack = nil
    profile.specDocuments = nil
    local budget = YHUD.StorageBudget
    local report, budgetCode = budget and budget.Evaluate
        and budget:Evaluate(profile) or nil
    if budget and not report then return nil, budgetCode end
    if report and report.hardLimitExceeded then
        return nil, "capacity-exceeded", report
    end
    return profile, nil, report
end

function ConfigSets:PrepareGraphicalProfileForTransfer(profile, owned)
    local expanded, code, detail = self:PrepareProfileForTransfer(profile, owned)
    if not expanded then return nil, code, detail end
    local function Strip(value)
        for key, child in pairs(value) do
            if key == 'sound' and type(child) == 'table' and type(child.rules) == 'table' then value[key] = nil
            elseif type(child) == 'table' then Strip(child) end
        end
    end
    Strip(expanded)
    return expanded, nil, detail
end

local PackJob = {}
PackJob.__index = PackJob

function PackJob:IsCurrent()
    local callback = self.options and self.options.isCurrent
    if type(callback) ~= "function" then return true end
    local ok, current = pcall(callback)
    return ok and current == true
end

function PackJob:EmitProgress(phase, processed, total, specKey)
    if self.finished then return end
    total = math.max(tonumber(total) or 0, 1)
    local progress = math.max(
        self.progress or 0,
        math.min((tonumber(processed) or 0) / total, 1)
    )
    self.progress = progress
    local callback = self.options and self.options.onProgress
    if type(callback) == "function" then
        pcall(callback, {
            phase = phase,
            progress = progress,
            processed = processed,
            total = total,
            specKey = specKey,
        })
    end
end

function PackJob:Cleanup()
    if self.timer and self.timer.Cancel then self.timer:Cancel() end
    self.timer = nil
    self.serializer = nil
    self.deflate = nil
    self.entries = nil
    self.specKeys = nil
    self.profile = nil
    self.runtimeSource = nil
    self.contentBySpec = nil
    self.previousPack = nil
    self.previousDocuments = nil
    self.blocks = nil
    self.summaries = nil
    self.summaryOverrides = nil
    self.dirtySpecs = nil
    self.options = nil
end

function PackJob:Finish(result, code, detail, cancelled)
    if self.finished then return false end
    self.finished = true
    local callback = self.options and self.options.onComplete
    if result then
        self:EmitProgress("complete", self.total or 1, self.total or 1)
    end
    self:Cleanup()
    if type(callback) == "function" and cancelled ~= true then
        pcall(callback, result, code, detail)
    end
    return true
end

function PackJob:Cancel()
    if self.finished then return false end
    return self:Finish(nil, "cancelled", nil, true)
end

function PackJob:Schedule()
    if self.finished or self.timer then return end
    if not (C_Timer and type(C_Timer.NewTimer) == "function") then
        self:Finish(nil, "pack-scheduler-unavailable")
        return
    end
    self.timer = C_Timer.NewTimer(0, function()
        self.timer = nil
        if self.finished then return end
        if not self:IsCurrent() then
            self:Finish(nil, "stale-pack-job")
            return
        end
        local ok, err = pcall(self.RunStep, self)
        if not ok then self:Finish(nil, "storage-codec-failed", err) end
    end)
end

function PackJob:FinishOpen()
    local valid, code = ValidateExpandedContent(
        self.contentBySpec,
        self.serializedBytes
    )
    if not valid then return self:Finish(nil, code) end
    self.profile.contentBySpec = self.contentBySpec
    self.profile.contentBySpecPack = nil
    local materialized, report = MaterializeExpandedProfile(
        self.profile,
        self.specKey
    )
    if not materialized then return self:Finish(nil, report) end
    return self:Finish({
        profile = materialized,
        report = report,
        packBaseline = {
            version = ConfigSets.CONTENT_PACK_VERSION,
            data = self.packData,
            entriesBySpec = self.entriesBySpec,
        },
    })
end

function PackJob:RunOpenStep()
    local entry = self.entries[self.index]
    if not entry then return self:FinishOpen() end
    local ok, serialized = pcall(
        self.deflate.DecompressDeflate,
        self.deflate,
        entry[2],
        MAX_EXPANDED_CONTENT_BYTES - self.serializedBytes
    )
    if not ok or type(serialized) ~= "string" or serialized == "" then
        return self:Finish(nil, "invalid-content-pack")
    end
    self.serializedBytes = self.serializedBytes + #serialized
    if self.serializedBytes > MAX_EXPANDED_CONTENT_BYTES then
        return self:Finish(nil, "capacity-exceeded")
    end
    local content, code = DeserializeContent(self.serializer, serialized)
    if not content then return self:Finish(nil, code) end
    self.contentBySpec[entry[1]] = content
    local canonical
    canonical, code = CanonicalSerialize(content)
    if not canonical then return self:Finish(nil, code) end
    self.entriesBySpec[entry[1]] = {
        serialized = canonical,
        data = entry[2],
    }
    local processed = self.index
    self.index = self.index + 1
    self:EmitProgress(
        "load-specializations",
        processed,
        self.total,
        entry[1]
    )
    self:Schedule()
end

function PackJob:FinishDocumentSave()
    local runtimeProfile, runtimeReport = MaterializeExpandedProfile(
        self.runtimeSource,
        self.specKey
    )
    if not runtimeProfile then return self:Finish(nil, runtimeReport) end
    self.profile.contentBySpec = {}
    self.profile.contentBySpecPack = nil
    self.profile._yhudSpecDocumentProjection = nil
    ClearSpecDocumentStateProjection(self.profile)
    self.profile.specDocuments = {
        version = ConfigSets.SPEC_DOCUMENT_VERSION,
        blocks = self.blocks,
        summaries = self.summaries,
    }
    local documents, code = ValidateSpecDocuments(self.profile)
    if not documents then return self:Finish(nil, code) end
    local stored, report
    stored, code, report = ValidateStorageProfile(self.profile)
    if not stored then return self:Finish(nil, code, report) end
    ConfigSets.lastSpecDocumentStats = {
        decoded = 0,
        encoded = self.serializedCount,
        reused = self.reusedCount,
        total = self.totalDocuments,
    }
    return self:Finish({
        profile = stored,
        runtimeProfile = runtimeProfile,
        report = report,
        compressedCount = 0,
        serializedCount = self.serializedCount,
        reusedCount = self.reusedCount,
    })
end

function PackJob:RunDocumentSaveStep()
    local specKey = self.specKeys[self.index]
    if not specKey then return self:FinishDocumentSave() end
    local content = self.contentBySpec[specKey]
    if type(content) ~= "table" then
        return self:Finish(nil, "invalid-spec-document")
    end
    local ok, block = pcall(
        self.serializer.Serialize,
        self.serializer,
        BuildStoredSpecDocument(self.profile, specKey, content)
    )
    if not ok or type(block) ~= "string" or block == "" then
        return self:Finish(nil, "storage-codec-failed")
    end
    if #block > MAX_LOCAL_SPEC_DOCUMENT_BYTES then
        return self:Finish(nil, "capacity-exceeded")
    end
    self.blocks[specKey] = block
    self.summaries[specKey] = type(self.summaryOverrides) == "table"
        and type(self.summaryOverrides[specKey]) == "table"
        and YHUD:CopyValue(self.summaryOverrides[specKey])
        or BuildSpecDocumentSummary(content)
    self.serializedCount = self.serializedCount + 1
    local processed = self.index
    self.index = self.index + 1
    self:EmitProgress(
        "prepare-specializations",
        processed,
        self.total,
        specKey
    )
    self:Schedule()
end

function ConfigSets:StartMaterializeProfile(profile, specKey, options)
    options = type(options) == "table" and options or {}
    if options.owned ~= true then profile = YHUD:CopyValue(profile) end
    local pack = type(profile) == "table" and profile.contentBySpecPack or nil
    if type(pack) ~= "table" then
        local materialized, report, baseline = self:MaterializeProfile(
            profile,
            specKey,
            true
        )
        if type(options.onComplete) == "function" then
            options.onComplete(materialized and {
                profile = materialized,
                report = report,
                packBaseline = baseline,
            } or nil, materialized and nil or report)
        end
        return { finished = true, Cancel = function() return false end }
    end
    if type(profile.contentBySpec) == "table"
        and next(profile.contentBySpec) ~= nil then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, "content-pack-conflict")
        end
        return { finished = true, Cancel = function() return false end }
    end
    if not (C_Timer and type(C_Timer.NewTimer) == "function") then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, "pack-scheduler-unavailable")
        end
        return { finished = true, Cancel = function() return false end }
    end
    if pack.version == ConfigSets.LEGACY_CONTENT_PACK_VERSION then
        local job = setmetatable({
            options = options,
            finished = false,
            total = 1,
        }, PackJob)
        job.RunStep = function(current)
            local serializer, deflate, code = GetContentCodec()
            if not serializer then return current:Finish(nil, code) end
            local content, unpackCode, baseline =
                UnpackLegacyContent(serializer, deflate, pack)
            if not content then return current:Finish(nil, unpackCode) end
            profile.contentBySpec = content
            profile.contentBySpecPack = nil
            local materialized, report = MaterializeExpandedProfile(
                profile,
                specKey
            )
            if not materialized then return current:Finish(nil, report) end
            current:EmitProgress("convert-legacy-pack", 1, 1)
            return current:Finish({
                profile = materialized,
                report = report,
                packBaseline = baseline,
            })
        end
        job:Schedule()
        return job
    end
    if pack.version ~= ConfigSets.CONTENT_PACK_VERSION then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, "unsupported-content-pack")
        end
        return { finished = true, Cancel = function() return false end }
    end
    local serializer, deflate, code = GetContentCodec()
    if not serializer then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local entries
    entries, code = DecodeV2Entries(serializer, pack)
    if not entries then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local job = setmetatable({
        mode = "open",
        options = options,
        profile = profile,
        specKey = specKey,
        packData = pack.data,
        serializer = serializer,
        deflate = deflate,
        entries = entries,
        entriesBySpec = {},
        contentBySpec = {},
        serializedBytes = 0,
        index = 1,
        total = #entries,
        finished = false,
    }, PackJob)
    job.RunStep = PackJob.RunOpenStep
    job:EmitProgress("read-configuration", 0, job.total)
    job:Schedule()
    return job
end

function ConfigSets:StartPrepareProfileForStorage(
    profile,
    previousPack,
    specKey,
    options
)
    options = type(options) == "table" and options or {}
    local runtimeSource, runtimeCode =
        self:CaptureRuntimeProfile(profile, specKey)
    if not runtimeSource then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, runtimeCode)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local documentBaseline = type(previousPack) == "table"
        and previousPack.version == ConfigSets.SPEC_DOCUMENT_VERSION
        and previousPack or nil
    if documentBaseline and type(options.dirtySpecs) == "table" then
        if options.owned ~= true then profile = YHUD:CopyValue(profile) end
        profile = RetainDirtySpecDocumentProjections(
            profile,
            options.dirtySpecs
        )
        options.owned = true
    end
    local compacted, code, detail, baseline, summaries =
        PrepareExpandedCompactProfile(
            profile,
            options.owned == true,
            previousPack
        )
    if not compacted then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code, detail)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local serializer
    serializer, code = GetContentSerializer()
    if not serializer then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local previousDocuments = type(baseline) == "table"
        and baseline.version == ConfigSets.SPEC_DOCUMENT_VERSION
        and baseline
        or type(compacted.specDocuments) == "table"
            and compacted.specDocuments or nil
    compacted, code = EnsureSpecDocumentCandidates(
        compacted,
        previousDocuments,
        options.dirtySpecs,
        summaries
    )
    if not compacted then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code)
        end
        return { finished = true, Cancel = function() return false end }
    end
    if YHUD.LegacySoundMigration then YHUD.LegacySoundMigration:StripCompletedRuntime(compacted) end
    runtimeSource, code = ResolveSaveRuntimeSource(
        self,
        compacted,
        runtimeSource,
        specKey,
        options.dirtySpecs
    )
    if not runtimeSource then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local blocks = CopyStringMap(previousDocuments and previousDocuments.blocks)
    local documentSummaries = CopySummaryMap(
        previousDocuments and previousDocuments.summaries
    )
    local dirtySpecs = type(options.dirtySpecs) == "table"
        and options.dirtySpecs or nil
    local specKeys = {}
    for key, content in pairs(compacted.contentBySpec or {}) do
        if not SUPPORTED_SPEC_KEY_SET[key] or type(content) ~= "table" then
            if type(options.onComplete) == "function" then
                options.onComplete(nil, "invalid-spec-document")
            end
            return { finished = true, Cancel = function() return false end }
        end
        if blocks[key] == nil or dirtySpecs == nil or dirtySpecs[key] == true then
            specKeys[#specKeys + 1] = key
        end
    end
    table.sort(specKeys)
    local totalDocuments = 0
    for _ in pairs(blocks) do totalDocuments = totalDocuments + 1 end
    for index = 1, #specKeys do
        if blocks[specKeys[index]] == nil then
            totalDocuments = totalDocuments + 1
        end
    end
    local reusedCount = 0
    for key in pairs(compacted.contentBySpec or {}) do
        if blocks[key] ~= nil
            and not (dirtySpecs == nil or dirtySpecs[key] == true) then
            reusedCount = reusedCount + 1
        end
    end
    local job = setmetatable({
        mode = "document-save",
        options = options,
        profile = compacted,
        runtimeSource = runtimeSource,
        specKey = specKey,
        serializer = serializer,
        contentBySpec = compacted.contentBySpec,
        previousDocuments = previousDocuments,
        blocks = blocks,
        summaries = documentSummaries,
        summaryOverrides = summaries,
        dirtySpecs = dirtySpecs,
        specKeys = specKeys,
        serializedCount = 0,
        reusedCount = reusedCount,
        totalDocuments = totalDocuments,
        index = 1,
        total = #specKeys,
        finished = false,
    }, PackJob)
    job.RunStep = PackJob.RunDocumentSaveStep
    job:EmitProgress("prepare-configuration", 0, job.total)
    if #specKeys == 0 then
        job:FinishDocumentSave()
    elseif C_Timer and type(C_Timer.NewTimer) == "function" then
        job:Schedule()
    else
        if type(options.onComplete) == "function" then
            options.onComplete(nil, "pack-scheduler-unavailable")
        end
        job.finished = true
        job:Cleanup()
    end
    return job
end

function ConfigSets:GetLastStorageBudgetReport()
    return self.lastStorageBudgetReport
        and YHUD:CopyValue(self.lastStorageBudgetReport) or nil
end

local function PreparedNow()
    return type(GetTime) == "function" and GetTime() or 0
end

function ConfigSets:CreatePreparedUserSetToken(record)
    if type(record) ~= "table" or type(record.setId) ~= "string"
        or type(record.targetStored) ~= "table"
        or type(record.targetRuntime) ~= "table"
        or type(record.previousStored) ~= "table"
        or type(record.previousRuntime) ~= "table"
        or type(record.session) ~= "table"
        or type(record.revision) ~= "number"
        or type(record.generation) ~= "number" then
        return nil, "invalid-prepared-data"
    end
    local token = {}
    record.expiresAt = PreparedNow() + 60
    self.preparedUserSetData[token] = record
    return token
end

function ConfigSets:ReleasePreparedUserSetToken(token)
    if self.preparedUserSetData[token] == nil then return false end
    self.preparedUserSetData[token] = nil
    if Service and type(Service.preparedDataEvents) == "table" then
        Service.preparedDataEvents[token] = nil
    end
    return true
end

local function ResolvePreparedUserSetData(token, context)
    local record = ConfigSets.preparedUserSetData[token]
    local options = type(context) == "table" and context.options or nil
    local reference = type(context) == "table" and context.reference or nil
    local setId = reference and reference.id or context and context.id
    if type(record) ~= "table" or type(options) ~= "table"
        or record.expiresAt < PreparedNow()
        or record.setId ~= setId
        or record.session ~= options.preparedSession
        or record.revision ~= options.preparedRevision
        or record.generation ~= options.preparedGeneration then
        ConfigSets.preparedUserSetData[token] = nil
        return nil, "invalid_payload", "invalid_prepared_token"
    end
    local data
    if record.cleanupOnly and (context.action ~= 'edit-data' or options.preparedPurpose ~= 'legacy-cleanup') then
        return nil, 'invalid_payload', 'invalid_prepared_context'
    end
    if context.action == "edit-data" then
        data = options.preparedPurpose == "rollback"
            and record.previousStored or record.targetStored
    elseif context.action == "apply" then
        data = record.targetStored
    elseif context.action == "snapshot" then
        data = record.previousStored
    else
        return nil, "invalid_payload", "invalid_prepared_context"
    end
    return {
        data = data,
        scopeIds = { "profile" },
    }
end

-- Migration has already validated/cleaned this local document in slices.
-- Reuse the bounded prepared-data path without treating binary local blocks as imports.
function ConfigSets:UpdateLegacySoundCleanup(setId, data, scopeIds)
    local token = {}
    self.preparedUserSetData[token] = { setId = setId, targetStored = data,
        cleanupOnly = true, session = token, revision = 0, generation = 0, expiresAt = PreparedNow() + 60 }
    local called, result, code, detail = pcall(Service.UpdateUserSetData, Service,
        self.PROVIDER_ID, setId, data, scopeIds, {
            preparedToken = token, preparedSession = token, preparedRevision = 0,
            preparedGeneration = 0, preparedPurpose = 'legacy-cleanup',
        })
    self:ReleasePreparedUserSetToken(token)
    if not called then return nil, 'legacy-cleanup-failed', result end
    return result, code, detail
end

local function NormalizeOwnedData(data, _, context)
    if type(data) ~= "table" then data = {} end
    local action = type(context) == "table" and context.action or nil
    local sourceSchemaVersion = type(context) == "table"
        and tonumber(context.sourceSchemaVersion) or nil
    if (action == "import" or action == "profile_import")
        and sourceSchemaVersion == YHUD.SCHEMA_VERSION then
        local valid, code, detail =
            ValidateSupportedSpecializationRoots(data.profile)
        if not valid then return nil, code, detail end
    end
    local profile, code, detail =
        ConfigSets:PrepareProfileForStorage(data.profile, true)
    if not profile then return nil, code, detail end
    data.profile = profile
    return data
end

local function NormalizeData(data)
    return NormalizeOwnedData(YHUD:CopyValue(data))
end

local function RepairCurrentStoredData(data)
    local profile = type(data) == "table" and data.profile or nil
    if type(profile) ~= "table" then return data, false end
    local original = data
    data = YHUD:CopyValue(data)
    profile = data.profile
    local needsRepair = YHUD:MigrateClientSpecializationKeys(profile)
        or YHUD:HasLegacyTrinketGroup(profile)
    for index = 1, #SPECIALIZATION_DATA_ROOTS do
        local root = profile[SPECIALIZATION_DATA_ROOTS[index]]
        for specKey in pairs(type(root) == "table" and root or {}) do
            if SUPPORTED_SPEC_KEY_SET[specKey] ~= true then
                needsRepair = true
                break
            end
        end
        if needsRepair then break end
    end
    if not needsRepair then return original, false end

    local repaired, code, detail =
        ConfigSets:PrepareProfileForStorage(profile, true)
    if not repaired then return nil, code, detail end
    data.profile = repaired
    return data, true
end

local function PrepareExportData(data)
    if type(data) ~= "table" then return nil, "invalid_payload" end
    local profile, code, detail =
        ConfigSets:PrepareGraphicalProfileForTransfer(data.profile, true)
    if not profile then return nil, code, detail end
    data.profile = profile
    return data
end

local function CanMigrate(sourceVersion, targetVersion)
    sourceVersion = tonumber(sourceVersion)
    targetVersion = tonumber(targetVersion)
    return sourceVersion and sourceVersion % 1 == 0
        and sourceVersion >= 1 and sourceVersion < YHUD.SCHEMA_VERSION
        and targetVersion == YHUD.SCHEMA_VERSION
end

local function Migrate(data, sourceVersion, targetVersion)
    if not CanMigrate(sourceVersion, targetVersion) then
        return nil, "incompatible-schema"
    end
    local migrated = YHUD:CopyValue(data)
    local profile = type(migrated) == "table" and migrated.profile or nil
    local placements = profile and profile.layout
        and profile.layout.placements or nil
    if tonumber(sourceVersion) < 27 and type(profile) == "table"
        and (type(placements) ~= "table" or next(placements) == nil)
        and YHUD.LayoutBridge
        and YHUD.LayoutBridge.CaptureProfilePlacements then
        local captured = YHUD.LayoutBridge:CaptureProfilePlacements(profile)
        if captured then
            profile.layout = type(profile.layout) == "table"
                and profile.layout or {}
            profile.layout.placements = captured
        end
    end
    return NormalizeOwnedData(migrated)
end

local function IsDesignerOpen()
    local Designer = YHUD.Designer
    return type(Designer) == "table"
        and type(Designer.IsOpen) == "function"
        and Designer:IsOpen() == true
        or false
end

local function Capture()
    local profile = YHUD:CopyValue(YHUD:GetConfigProfile())
    if YHUD.LegacySoundMigration then YHUD.LegacySoundMigration:StripCompletedRuntime(profile) end
    if profile and YHUD.LayoutBridge
        and YHUD.LayoutBridge.CaptureProfilePlacements then
        local captured, readable =
            YHUD.LayoutBridge:CaptureProfilePlacements(profile)
        if type(captured) == "table" and not IsDesignerOpen() then
            local layout = type(profile.layout) == "table"
                and profile.layout or {}
            profile.layout = layout
            local placements = type(layout.placements) == "table"
                and layout.placements or {}
            layout.placements = placements
            for groupId, placement in pairs(captured) do
                if placements[groupId] == nil
                    or readable == nil
                    or readable[groupId] == true then
                    placements[groupId] = placement
                end
            end
        end
    end
    local stored, code, detail =
        ConfigSets:PrepareProfileForStorage(profile)
    if not stored then return nil, code, detail end
    return { profile = stored }
end

local function ValuesEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    local paired = seen[left]
    if paired ~= nil then return paired == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not ValuesEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function BuildComparableRuntimeProfile(profile, specKey)
    if type(profile) ~= "table" then return profile end
    local comparable = YHUD:CopyValue(YHUD:GetCanonicalProfile(profile))
    local content = type(comparable.contentBySpec) == "table"
        and comparable.contentBySpec[specKey] or nil
    comparable.contentBySpec = content and { [specKey] = content } or {}
    for index = 1, #SPEC_DOCUMENT_STATE_FIELDS do
        local rootKey = SPEC_DOCUMENT_STATE_FIELDS[index].root
        local value = type(comparable[rootKey]) == "table"
            and comparable[rootKey][specKey] or nil
        comparable[rootKey] = value and { [specKey] = value } or nil
    end
    comparable.specDocuments = nil
    comparable.contentBySpecPack = nil
    comparable.schemaVersion = nil
    comparable.profileVersion = nil
    comparable._yhudSpecDocumentProjection = nil
    comparable._yhudCanonical = nil
    comparable._yhudSpecKey = nil
    comparable._yhudVirtualContent = nil
    comparable._yhudScopeByEntry = nil
    comparable._yhudScopeByMonitor = nil
    comparable._yhudMergedMembers = nil
    comparable._yhudLaneByMonitor = nil
    return comparable
end

function ConfigSets:RestoreOfficialOverrides(profile, specKey, options)
    if type(profile) ~= "table" then return nil, "invalid-profile" end
    if not YHUD:IsStableSpecKey(specKey) then return nil, "invalid-spec-key" end

    local working = YHUD:CopyValue(YHUD:GetCanonicalProfile(profile))
    working = ApplySpecOverrides(working, specKey, options)
    working = YHUD:NormalizeProfile(working, specKey)
    NormalizeOfficialOverrides(working)

    local scoped, code = YHUD:GetScopedProfile(working, specKey, false)
    if not scoped then return nil, code end
    local valid
    valid, code = YHUD.ProfileModel:Validate(scoped)
    if not valid then return nil, code end

    return working, {
        changed = not ValuesEqual(YHUD:GetCanonicalProfile(profile), working),
    }
end

local function ProfileNowMS()
    if YHUD.performanceDiagnosticsEnabled ~= true then return nil end
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function IsAutomaticContext(context)
    return type(context) == "table"
        and type(context.options) == "table"
        and context.options.automatic == true
end

local function RecordApplyElapsed(startedAt)
    local finishedAt = ProfileNowMS()
    local stats = YHUD.contextRefreshStats
    if startedAt and finishedAt and type(stats) == "table" then
        stats.configApplyMS = (stats.configApplyMS or 0)
            + math.max(0, finishedAt - startedAt)
    end
end

function ConfigSets:PlanNativeCategorySync(profile, specKey)
    if type(profile) ~= "table"
        or type(YHUD.GetOfficialNativeCategoryAssignments) ~= "function" then
        return nil, "native-category-profile-unavailable"
    end
    specKey = specKey or YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then return nil end
    local scopedProfile, scopeCode = YHUD:GetScopedProfile(
        profile,
        specKey,
        true
    )
    if not scopedProfile then
        return nil, scopeCode or "native-category-content-not-found"
    end
    local assignments, code =
        YHUD:GetOfficialNativeCategoryAssignments(scopedProfile)
    if not assignments then return nil, code end
    local adapter = YUI.API and YUI.API.CooldownViewer
    if not (adapter
        and type(adapter.PlanCategoryAssignments) == "function") then
        return nil, "native-category-adapter-unavailable"
    end
    local plan, report = adapter:PlanCategoryAssignments(assignments)
    if not plan then return nil, report end
    return plan, nil, report
end

function ConfigSets:ValidateNativeCategorySyncPlan(profile, specKey, plan)
    if type(plan) ~= "table"
        or plan.kind ~= "cooldown-category-reload"
        or type(plan.requests) ~= "table" then
        return nil, "invalid-native-category-plan"
    end
    specKey = specKey or YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    local scopedProfile, scopeCode = YHUD:GetScopedProfile(
        profile,
        specKey,
        true
    )
    if not scopedProfile then
        return nil, scopeCode or "native-category-content-not-found"
    end
    local assignments, code =
        YHUD:GetOfficialNativeCategoryAssignments(scopedProfile)
    if not assignments then return nil, code end

    local requestsByCooldownID = {}
    for index = 1, #plan.requests do
        local request = plan.requests[index]
        local cooldownID = type(request) == "table"
            and tonumber(request.cooldownID) or nil
        if not cooldownID or requestsByCooldownID[cooldownID] then
            return nil, "invalid-native-category-plan"
        end
        requestsByCooldownID[cooldownID] = request
    end

    local expectedCount = 0
    for index = 1, #assignments do
        local assignment = assignments[index]
        if assignment.currentCategory ~= assignment.targetCategory then
            expectedCount = expectedCount + 1
            local request = requestsByCooldownID[assignment.cooldownID]
            if not request
                or request.targetKey ~= assignment.targetCategory
                or request.originalKey ~= assignment.currentCategory then
                return nil, "stale-native-category-plan"
            end
            requestsByCooldownID[assignment.cooldownID] = nil
        end
    end
    if expectedCount ~= #plan.requests or next(requestsByCooldownID) ~= nil then
        return nil, "stale-native-category-plan"
    end
    return true
end

function ConfigSets:ApplyNativeCategoryPlanForReload(plan)
    local adapter = YUI.API and YUI.API.CooldownViewer
    if not (adapter
        and type(adapter.ApplyCategoryAssignmentPlanForReload)
            == "function") then
        return nil, "native-category-adapter-unavailable"
    end
    return adapter:ApplyCategoryAssignmentPlanForReload(plan)
end

function ConfigSets:RestoreNativeCategoryPlanForReload(plan)
    local adapter = YUI.API and YUI.API.CooldownViewer
    if not (adapter
        and type(adapter.RestoreCategoryAssignmentPlanForReload)
            == "function") then
        return nil, "native-category-adapter-unavailable"
    end
    return adapter:RestoreCategoryAssignmentPlanForReload(plan)
end

function ConfigSets:RequestNativeCategoryReloadPrompt(request)
    if type(request) ~= "table" then return false end
    self.pendingNativeCategoryReload = request
    local ui = YHUD.DesignerUI
    if ui and type(ui.ShowNativeCategoryReloadPrompt) == "function" then
        return ui:ShowNativeCategoryReloadPrompt(request)
    end
    return false
end

function ConfigSets:ReloadInterfaceNow()
    local frameAPI = YUI.API and YUI.API.Frame
    if not (frameAPI and type(frameAPI.ReloadUI) == "function") then
        return nil, "reload-unavailable"
    end
    return frameAPI.ReloadUI()
end

local function PrintNativeCategoryFailure()
    local message = YHUD:T(
        "designer.native_category_reload.failed",
        "同步暴雪冷却设置失败，已恢复原配置。"
    )
    if YUI.Print then YUI:Print(message) elseif _G.print then _G.print(message) end
end

local function IsCombatLocked()
    local combat = YUI.API and YUI.API.Combat
    local callback = combat and combat.InCombatLockdown
        or _G.InCombatLockdown
    if type(callback) ~= "function" then return false end
    local ok, value = pcall(callback)
    return ok and value == true
end

function ConfigSets:ExecuteNativeCategoryReload(plan, recovery)
    if type(plan) ~= "table" then
        return nil, "native-category-plan-unavailable"
    end
    if type(plan.requests) == "table" and #plan.requests == 0 then
        return {
            changedCount = 0,
            requiresReload = false,
            activationMode = "none",
        }
    end
    if IsCombatLocked() then
        return nil, "combat-lockdown"
    end
    local frameAPI = YUI.API and YUI.API.Frame
    if not (frameAPI and type(frameAPI.ReloadUI) == "function") then
        return nil, "reload-unavailable"
    end
    local report, code, detail =
        self:ApplyNativeCategoryPlanForReload(plan)
    if not report then
        local recovered = true
        local recoveryDetail
        if type(recovery) == "function" then
            local ok, value, callbackDetail = pcall(recovery)
            recovered = ok and value ~= nil and value ~= false
            recoveryDetail = ok and callbackDetail or value
        end
        PrintNativeCategoryFailure()
        if type(detail) == "table" and detail.lockHeld == true then
            return {
                failed = true,
                failureCode = code,
                failureDetail = recoveryDetail or detail,
                requiresReload = true,
                reloadPending = true,
            }
        end
        return nil,
            recovered and code or "native-category-recovery-failed",
            recoveryDetail or detail
    end
    report.reloadPending = report.requiresReload == true
    return report
end

function ConfigSets:ApplyPendingNativeCategoryReload(request)
    if type(request) ~= "table" or type(request.reference) ~= "table" then
        return nil, "native-category-request-unavailable"
    end
    if request.database then
        local provider = Service:GetProvider(self.PROVIDER_ID)
        local db = provider and YUI.DB:GetAceDB(provider.productId)
        local active = Service:GetActiveReference(self.PROVIDER_ID)
        if db ~= request.database or db:GetCurrentProfile() ~= request.profileName
            or YHUD:GetCurrentSpecKey() ~= request.specKey
            or not active or active.kind ~= request.reference.kind
            or active.id ~= request.reference.id then
            return nil, "stale-native-category-plan"
        end
    end
    local result, code, detail = Service:Apply(
        self.PROVIDER_ID,
        request.reference,
        YHUD,
        {
            automatic = true,
            reason = "native-category-reload",
            recordUndo = true,
            nativeCategoryReloadApproved = true,
            nativeCategoryPlan = request.plan,
            nativeCategoryReport = request.report,
        }
    )
    if not result then return nil, code, detail end
    local applyResult = type(result.result) == "table" and result.result or nil
    local plan = applyResult and applyResult.nativeCategoryPlan or request.plan
    return self:ExecuteNativeCategoryReload(plan, function()
        return Service:UndoForReload(self.PROVIDER_ID, YHUD)
    end)
end

local function Apply(data, _, context)
    local startedAt = ProfileNowMS()
    local automatic = IsAutomaticContext(context)
    local current = YHUD:GetConfigProfile()
    local targetStored = data and data.profile
    local options = type(context) == "table" and context.options or nil
    local prepared = options and options.preparedToken
        and ConfigSets.preparedUserSetData[options.preparedToken] or nil
    local rollback = type(context) == "table" and context.action == "rollback"
    local targetRuntime = prepared and (rollback
        and prepared.previousRuntime.profile
        or prepared.targetRuntime.profile) or nil
    if targetStored and not targetRuntime then
        local code
        targetRuntime, code = ConfigSets:MaterializeProfile(
            targetStored,
            YHUD:GetCurrentSpecKey()
        )
        if not targetRuntime then
            error(code or "config-materialize-failed")
        end
    end
    local nativeCategoryPlan
    local nativeCategoryReport
    local nativeCategoryReloadDeferred = false
    local nativeCategorySyncEligible = not options
        or options.nativeCategorySyncEligible ~= false
    if targetRuntime and not rollback and nativeCategorySyncEligible then
        local syncCode
        if options and options.nativeCategoryReloadApproved == true
            and type(options.nativeCategoryPlan) == "table" then
            local valid
            valid, syncCode = ConfigSets:ValidateNativeCategorySyncPlan(
                targetRuntime,
                YHUD:GetCurrentSpecKey(),
                options.nativeCategoryPlan
            )
            if not valid then error(syncCode) end
            nativeCategoryPlan = options.nativeCategoryPlan
            nativeCategoryReport = options.nativeCategoryReport
        else
            nativeCategoryPlan, syncCode, nativeCategoryReport =
                ConfigSets:PlanNativeCategorySync(targetRuntime)
            if syncCode then error(syncCode) end
        end
        if nativeCategoryReport
            and nativeCategoryReport.changedCount > 0
            and not (options
                and options.nativeCategoryReloadApproved == true) then
            if options and options.deferNativeCategoryReloadPrompt == true then
                nativeCategoryReloadDeferred = true
            else
                ConfigSets:RequestNativeCategoryReloadPrompt({
                    automatic = automatic,
                    plan = nativeCategoryPlan,
                    report = nativeCategoryReport,
                    reference = type(context) == "table"
                        and context.reference or nil,
                })
                error("native-category-reload-confirmation-required")
            end
        end
    end
    local currentRuntime = current
    if prepared and not rollback
        and type(prepared.previousRuntime) == "table"
        and type(prepared.previousRuntime.profile) == "table" then
        currentRuntime = prepared.previousRuntime.profile
    elseif not automatic and current
        and type(current.specDocuments) == "table" then
        local code
        currentRuntime, code = ConfigSets:MaterializeProfile(
            current,
            YHUD:GetCurrentSpecKey()
        )
        if not currentRuntime then
            error(code or "config-current-materialize-failed")
        end
    end
    local runtimeSpecKey = YHUD:GetCurrentSpecKey()
    local comparableCurrentRuntime = currentRuntime
        and BuildComparableRuntimeProfile(currentRuntime, runtimeSpecKey) or nil
    local comparableTargetRuntime = targetRuntime
        and BuildComparableRuntimeProfile(targetRuntime, runtimeSpecKey) or nil
    local runtimeUnchanged = comparableCurrentRuntime
        and comparableTargetRuntime
        and ValuesEqual(comparableCurrentRuntime, comparableTargetRuntime) or false
    local comparableCurrent = current
    if current and type(current.specDocuments) == "table" then
        comparableCurrent = YHUD:CopyValue(current)
        comparableCurrent.contentBySpec = {}
        comparableCurrent._yhudSpecDocumentProjection = nil
    elseif current and targetStored
        and type(targetStored.specDocuments) == "table" then
        comparableCurrent = ConfigSets:PrepareProfileForStorage(current)
            or current
    end
    if comparableCurrent and targetStored
        and ValuesEqual(comparableCurrent, targetStored)
        and runtimeUnchanged then
        RecordApplyElapsed(startedAt)
        return {
            profileChanged = false,
            contextRefresh = automatic,
            catalogMaterialized = targetRuntime ~= nil,
            nativeCategoryPlan = nativeCategoryPlan,
            nativeCategoryReport = nativeCategoryReport,
            nativeCategoryReloadDeferred = nativeCategoryReloadDeferred,
        }
    end
    local profile, code = YHUD:ReplaceConfigProfile(targetStored)
    if not profile then
        error(code or "config-apply-failed")
    end
    if targetRuntime then
        local specKey = YHUD:GetCurrentSpecKey()
        local scoped = YHUD:GetScopedProfile(targetRuntime, specKey, true)
        if scoped then
            YHUD._runtimeProfile = scoped
            YHUD._runtimeProfileCanonical = profile
            YHUD._runtimeProfileSpecKey = specKey
            YHUD._runtimeProfileRevision =
                tonumber(YHUD.runtimeProfileRevision) or 0
        end
    end
    if YHUD.Stats then YHUD.Stats:Add("configApplies") end
    RecordApplyElapsed(startedAt)
    local previewSynchronized = context and context.options
        and context.options.previewSynchronized == true or false
    return {
        profileChanged = not runtimeUnchanged,
        contextRefresh = not runtimeUnchanged
            and not previewSynchronized,
        catalogMaterialized = targetRuntime ~= nil,
        previewSynchronized = previewSynchronized,
        nativeCategoryPlan = nativeCategoryPlan,
        nativeCategoryReport = nativeCategoryReport,
        nativeCategoryReloadDeferred = nativeCategoryReloadDeferred,
    }
end

local function Refresh(reason, applyResult, context)
    if type(applyResult) == "table"
        and applyResult.previewSynchronized == true then
        return true
    end
    if IsAutomaticContext(context)
        or (type(applyResult) == "table"
            and applyResult.contextRefresh == true) then
        if YHUD.RequestContextRefresh then
            local options = type(context) == "table" and context.options or nil
            return YHUD:RequestContextRefresh(
                options and options.reason or reason or "config-context",
                {
                    catalogMaterialized = type(applyResult) == "table"
                        and applyResult.catalogMaterialized == true,
                    immediate = options ~= nil
                        and options.nativeCategoryReloadApproved == true
                        and context.action ~= "rollback",
                }
            )
        end
        return true
    end
    if type(applyResult) == "table"
        and applyResult.profileChanged == false then
        return true
    end
    return YHUD:Refresh(reason or "config-set")
end

local function RestoreForReload(snapshot)
    local profile = type(snapshot) == "table" and snapshot.profile or nil
    if type(profile) ~= "table" then
        return nil, "native-category-recovery-profile-unavailable"
    end
    return YHUD:ReplaceConfigProfile(profile)
end

local function AssignmentReady()
    if not (YUI.DB and YUI.DB.IsReady and YUI.DB:IsReady()) then
        return false, "db-not-ready"
    end
    if YHUD.IsEnabled and not YHUD:IsEnabled() then
        return false, "product-disabled"
    end
    if YHUD.View and YHUD.View.active ~= true then
        return false, "runtime-inactive"
    end
    return true
end

function ConfigSets:RegisterProvider()
    local existing = Service:GetProvider(self.PROVIDER_ID)
    if existing then
        self.provider = existing
        return existing
    end

    local provider, code, detail = Service:RegisterProvider({
        id = self.PROVIDER_ID,
        productId = YHUD.PRODUCT_ID,
        schemaVersion = YHUD.SCHEMA_VERSION,
        canMigrate = CanMigrate,
        migrate = Migrate,
        localeNamespace = "YHUD",
        maxUserSets = 30,
        maxPayloadNodes = 131072,
        previewZoom = false,
        editableUserSets = true,
        configurationModes = {
            isolatedLibraries = true,
            defaultMode = "unified",
        },
        specializationAssignments = true,
        defaultAssignment = {
            kind = "builtin",
            id = self.BUILTIN_ID,
        },
        autoApplyAssignments = true,
        assignmentReady = AssignmentReady,
        scopeOrder = { "profile" },
        scopes = {
            profile = {
                id = "profile",
                labelKey = "config.scope.profile",
            },
        },
        builtins = {
            {
                id = self.BUILTIN_ID,
                nameKey = "config.builtin.name",
                descriptionKey = "config.builtin.description",
                preview = false,
                scopeIds = { "profile" },
                data = {
                    profile = self:PrepareProfileForTransfer(
                        YHUD:CreateDefaultProfile(),
                        true
                    ),
                },
            },
        },
        capture = Capture,
        normalize = NormalizeOwnedData,
        repairCurrentStoredData = RepairCurrentStoredData,
        prepareExportData = PrepareExportData,
        resolvePreparedUserSetData = ResolvePreparedUserSetData,
        localBinaryFields = BuildLocalSpecDocumentFields(),
        apply = Apply,
        restore = Apply,
        restoreForReload = RestoreForReload,
        refresh = Refresh,
        owner = YHUD,
    })
    if not provider then
        if YHUD.Diagnostics then
            YHUD.Diagnostics:Record("config-provider", detail or code)
        end
        return nil, code, detail
    end
    self.provider = provider
    return provider
end

function ConfigSets:EnsureDefaultUserSet(force)
    if self.ensureBusy then return false end
    if not self:RegisterProvider() then return false end

    if force ~= true and self.ensureResult and self.ensureDatabase then
        local cachedProfileName = self.ensureDatabase.GetCurrentProfile
            and self.ensureDatabase:GetCurrentProfile()
        if cachedProfileName == self.ensureProfileName then
            return self.ensureResult
        end
    end

    local db = YUI.DB and YUI.DB.GetAceDB
        and YUI.DB:GetAceDB(YHUD.PRODUCT_ID)
    local profileName = db and db.GetCurrentProfile
        and db:GetCurrentProfile()
    if force ~= true
        and self.ensureResult
        and self.ensureDatabase == db
        and self.ensureProfileName == profileName then
        return self.ensureResult
    end

    self.ensureBusy = true
    local ensureOptions = force == true and {
        forceValidate = true,
    } or nil

    -- Specialization assignments use a specialization-library user set as
    -- their backing reference. Bootstrap that library first, then let the
    -- provider switch the newly-created profile to its unified default.
    local configurationModes = self.provider.configurationModes
    local defaultMode = configurationModes and configurationModes.defaultMode
    if configurationModes and defaultMode == "unified" then
        configurationModes.defaultMode = "specialization"
    end
    local ok, ensured, code, detail = pcall(
        Service.EnsureEditableUserSet,
        Service,
        self.PROVIDER_ID,
        ensureOptions
    )
    if configurationModes then configurationModes.defaultMode = defaultMode end
    if not ok then
        self.ensureBusy = false
        error(ensured, 0)
    end

    local bootstrapUnified = ensured
        and defaultMode == "unified"
        and ensured.configurationMode == "specialization"
        and (tonumber(ensured.created) or 0) > 1
    if bootstrapUnified then
        local switched
        switched, code, detail = Service:SetConfigurationMode(
            self.PROVIDER_ID,
            "unified",
            YHUD
        )
        if switched then
            ensured, code, detail = Service:EnsureEditableUserSet(
                self.PROVIDER_ID,
                ensureOptions
            )
        else
            ensured = nil
        end
    end

    if ensured then
        Service:SetPickerPreferences(self.PROVIDER_ID, {
            hideUnusedBuiltins = true,
        })
    end
    self.ensureBusy = false
    if not ensured then return nil, code, detail end
    self.ensureResult = ensured
    self.ensureDatabase = db
    self.ensureProfileName = profileName
    return ensured
end

function ConfigSets:SaveActive(reason, owner)
    if not self:RegisterProvider() then return false end
    return Service:SaveActiveUserSet(self.PROVIDER_ID, {
        reason = reason,
        owner = owner or YHUD,
    })
end

function ConfigSets:PatchActiveGroupPlacement(
    groupId,
    placement,
    reason,
    owner
)
    if type(groupId) ~= "string" or type(placement) ~= "table" then
        return nil, "invalid-placement"
    end
    if not self:RegisterProvider() then
        return nil, "config-provider-unavailable"
    end
    if type(Service.PatchActiveUserSet) ~= "function" then
        return nil, "config-sets-service-unavailable"
    end

    local profile = YHUD:GetConfigProfile()
    local groups = profile and profile.groups and profile.groups.items
    local group = type(groups) == "table" and groups[groupId]
    local layout = profile and profile.layout
    local placements = layout and layout.placements
    if type(group) ~= "table" or type(placements) ~= "table" then
        return nil, "profile-placement-unavailable"
    end

    local normalized = YHUD:NormalizeGroupPlacements(
        { [groupId] = placement },
        { [groupId] = group }
    )
    local nextPlacement = normalized and normalized[groupId]
    if type(nextPlacement) ~= "table" then
        return nil, "invalid-placement"
    end

    local hadPrevious = placements[groupId] ~= nil
    local previous = YHUD:CopyValue(placements[groupId])
    placements[groupId] = YHUD:CopyValue(nextPlacement)
    YHUD:InvalidateRuntimeProfile()

    local result, code, detail = Service:PatchActiveUserSet(
        self.PROVIDER_ID,
        {
            {
                path = { "profile", "layout", "placements", groupId },
                value = nextPlacement,
            },
        },
        {
            reason = reason or "layout-placement-commit",
            owner = owner or YHUD,
        }
    )
    if not result then
        placements[groupId] = hadPrevious and previous or nil
        YHUD:InvalidateRuntimeProfile()
        return nil, code, detail
    end

    return YHUD:CopyValue(nextPlacement), result.changed == true, result
end

function ConfigSets:Open(ownerFrame, options)
    local Picker = YUI.Settings and YUI.Settings.ConfigSetPicker
    if not (Picker and Picker.Open) then return false end
    options = type(options) == "table" and options or {}
    local ensured, code = self:EnsureDefaultUserSet()
    if not ensured then return nil, code end
    local host = options.host or _G.YUI_SettingsFrame or UIParent
    Picker:Open(ownerFrame or host, {
        providerId = self.PROVIDER_ID,
        ownerFrame = ownerFrame,
        undoOwner = YHUD,
        host = host,
        kind = options.kind,
        setId = options.setId,
        title = options.title,
        frameStrata = options.frameStrata,
        frameLevel = options.frameLevel,
        toplevel = options.toplevel,
        onApplied = options.onApplied,
        onClosed = options.onClosed,
    })
    return true
end

ConfigSets:RegisterProvider()

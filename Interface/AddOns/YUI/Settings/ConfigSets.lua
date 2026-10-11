local ADDON_NAME = ...
local YUI = _G.YUI
if not YUI or not YUI.Settings then return end

local S = YUI.Settings
S.ConfigSets = S.ConfigSets or {}
local ConfigSets = S.ConfigSets
if ConfigSets._loaded then return end
ConfigSets._loaded = true

ConfigSets.STORAGE_KEY = "SettingsConfigSets"
ConfigSets.SCHEMA_VERSION = 1
ConfigSets.MAX_USER_SETS = 32
ConfigSets.EXPORT_FORMAT_VERSION = 1
ConfigSets.EXPORT_PREFIX = "!YUI-SET:"
ConfigSets.CONFIGURATION_MODE_UNIFIED = "unified"
ConfigSets.CONFIGURATION_MODE_SPECIALIZATION = "specialization"

local MAX_PROVIDER_ID_BYTES = 96
local MAX_SET_ID_BYTES = 96
local MAX_NAME_CHARS = 48
local MAX_NAME_BYTES = 144
local MAX_DESCRIPTION_CHARS = 180
local MAX_DESCRIPTION_BYTES = 600
local MAX_PAYLOAD_DEPTH = 12
local MAX_PAYLOAD_NODES = 4096
local MAX_PROVIDER_PAYLOAD_NODES = 131072
local MAX_PAYLOAD_STRING_BYTES = 4096
local MAX_IMPORT_STRING_BYTES = 512 * 1024
local MAX_SERIALIZED_IMPORT_BYTES = 2 * 1024 * 1024
local SINGLE_SET_ENVELOPE_DEPTH_ALLOWANCE = 2
local MAX_PROFILE_STATE_NODES = MAX_PROVIDER_PAYLOAD_NODES * ConfigSets.MAX_USER_SETS
local MAX_PROFILE_STATE_DEPTH = MAX_PAYLOAD_DEPTH + 5
local MAX_PATCH_CHANGES = 64
local MAX_PATCH_PATH_DEPTH = 12
local EXPORT_PAYLOAD_KIND = "YUI_CONFIG_SET"
local MIN_PREVIEW_WIDTH = 256
local MIN_PREVIEW_HEIGHT = 144
local MIN_ZOOM_PREVIEW_WIDTH = 512
local MIN_ZOOM_PREVIEW_HEIGHT = 288
local MAX_PREVIEW_WIDTH = 2048
local MAX_PREVIEW_HEIGHT = 1152

ConfigSets.providers = ConfigSets.providers or {}
ConfigSets.transactions = ConfigSets.transactions or {}
ConfigSets.busy = ConfigSets.busy or {}
ConfigSets.activeReferences = ConfigSets.activeReferences or {}
ConfigSets.preparedDataEvents = ConfigSets.preparedDataEvents or {}

local MODE_UNIFIED = ConfigSets.CONFIGURATION_MODE_UNIFIED
local MODE_SPECIALIZATION = ConfigSets.CONFIGURATION_MODE_SPECIALIZATION
local USER_SET_SCOPE_POLICY_ALL = "all"
local USER_SET_SCOPE_POLICY_VERSION = 1
local SPECIALIZATION_PROFILE_STATE_VERSION = 1
local GetProfileIdentity
local GetProfileSpecializationState

local function SupportsConfigurationModes(provider)
    return ConfigSets.ProfileOwnership == nil and type(provider) == "table"
        and type(provider.configurationModes) == "table"
        and provider.configurationModes.isolatedLibraries == true
end

local function UsesAllUserSetScopes(provider)
    return type(provider) == "table"
        and provider.userSetScopePolicy == USER_SET_SCOPE_POLICY_ALL
end

local function NormalizeConfigurationMode(provider, mode, useDefault)
    if not SupportsConfigurationModes(provider) then return nil end
    if mode == MODE_UNIFIED or mode == MODE_SPECIALIZATION then return mode end
    if useDefault then
        return provider.configurationModes.defaultMode or MODE_SPECIALIZATION
    end
    return nil
end

local function IsInCombat()
    local CombatAPI = YUI.API and YUI.API.Combat or YUI.WOW_API or {}
    local callback = CombatAPI.InCombatLockdown or _G.InCombatLockdown
    if type(callback) ~= "function" then return false end
    local ok, value = pcall(callback)
    return ok and value == true
end

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function IsInteger(value)
    return IsFiniteNumber(value) and value == math.floor(value)
end

local function Trim(value)
    if type(value) ~= "string" then return nil end
    return value:match("^%s*(.-)%s*$")
end

local function GetSerializationLibraries()
    local libStub = _G.LibStub
    if not libStub or type(libStub.GetLibrary) ~= "function" then
        return nil, nil, "serialization_unavailable"
    end

    local serializer = libStub:GetLibrary("AceSerializer-3.0", true)
    local deflate = libStub:GetLibrary("LibDeflate", true)
    if not serializer
        or type(serializer.Serialize) ~= "function"
        or type(serializer.Deserialize) ~= "function"
        or not deflate
        or type(deflate.CompressDeflate) ~= "function"
        or type(deflate.DecompressDeflate) ~= "function"
        or type(deflate.EncodeForPrint) ~= "function"
        or type(deflate.DecodeForPrint) ~= "function" then
        return nil, nil, "serialization_unavailable"
    end
    return serializer, deflate
end

local function Utf8Length(value)
    local count = 0
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte < 128 or byte >= 192 then
            count = count + 1
        end
    end
    return count
end

local function Utf8Prefix(value, maxChars, maxBytes)
    if type(value) ~= "string" or maxChars < 1 or maxBytes < 1 then return "" end
    if Utf8Length(value) <= maxChars and #value <= maxBytes then return value end

    local index = 1
    local endIndex = 0
    local charCount = 0
    while index <= #value and charCount < maxChars do
        local byte = string.byte(value, index)
        local width = 1
        if byte >= 240 then
            width = 4
        elseif byte >= 224 then
            width = 3
        elseif byte >= 192 then
            width = 2
        end
        if index + width - 1 > #value or endIndex + width > maxBytes then break end
        endIndex = index + width - 1
        index = endIndex + 1
        charCount = charCount + 1
    end
    return value:sub(1, endIndex)
end

local function HasForbiddenControl(value, allowMultiline)
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte == 0 or byte == 127 or (byte < 32 and not (allowMultiline and (byte == 9 or byte == 10))) then
            return true
        end
    end
    return false
end

local function NormalizeName(value)
    value = Trim(value)
    if not value or value == "" or #value > MAX_NAME_BYTES or Utf8Length(value) > MAX_NAME_CHARS then
        return nil, "invalid_name"
    end
    if HasForbiddenControl(value, false) then
        return nil, "invalid_name"
    end
    return value
end

local function NormalizeDescription(value)
    if value == nil then return nil end
    if type(value) ~= "string" then
        return nil, "invalid_description"
    end
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    value = Trim(value)
    if value == "" then return nil end
    if #value > MAX_DESCRIPTION_BYTES or Utf8Length(value) > MAX_DESCRIPTION_CHARS then
        return nil, "invalid_description"
    end
    if HasForbiddenControl(value, true) then
        return nil, "invalid_description"
    end
    return value
end

local function NormalizeNameKey(value)
    return string.lower(value)
end

local function IsStableId(value, maxBytes)
    return type(value) == "string"
        and value ~= ""
        and #value <= (maxBytes or MAX_SET_ID_BYTES)
        and value:match("^[A-Za-z0-9][A-Za-z0-9%._%-]*$") ~= nil
end

local function CopyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

local function NormalizeReference(reference)
    if type(reference) ~= "table"
        or (reference.kind ~= "builtin" and reference.kind ~= "user")
        or not IsStableId(reference.id) then
        return nil
    end
    return {
        kind = reference.kind,
        id = reference.id,
    }
end

local function CopyReference(reference)
    return NormalizeReference(reference)
end

local function ReferencesEqual(left, right)
    return type(left) == "table"
        and type(right) == "table"
        and left.kind == right.kind
        and left.id == right.id
end

local function Emit(event, ...)
    if YUI.Event and type(YUI.Event.Emit) == "function" then
        YUI.Event:Emit(event, ...)
    end
end

local function ArraysEqual(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function ClonePortable(value, state, depth, localBinaryNode)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" then
        return value
    end
    if valueType == "number" then
        if not IsFiniteNumber(value) then
            return nil, "invalid_payload", "non_finite_number"
        end
        return value
    end
    if valueType == "string" then
        local localBinaryBytes = type(localBinaryNode) == "table"
            and localBinaryNode.maxBytes or nil
        local maxStringBytes = localBinaryBytes
            or (state and state.maxStringBytes)
            or MAX_PAYLOAD_STRING_BYTES
        local allowControlStrings = localBinaryBytes ~= nil
            or (state and state.allowControlStrings == true)
        if #value > maxStringBytes
            or (not allowControlStrings and HasForbiddenControl(value, true)) then
            return nil, "invalid_payload", "invalid_string"
        end
        return value
    end
    if valueType ~= "table" then
        return nil, "invalid_payload", "unsupported_type:" .. valueType
    end

    state = state or {
        seen = {},
        nodes = 0,
        maxNodes = MAX_PAYLOAD_NODES,
    }
    if state.yieldIfNeeded then state.yieldIfNeeded(state) end
    depth = depth or 0
    if depth >= (state.maxDepth or MAX_PAYLOAD_DEPTH) then
        return nil, "invalid_payload", "max_depth"
    end
    if getmetatable(value) ~= nil then
        return nil, "invalid_payload", "metatable"
    end
    if state.seen[value] then
        return nil, "invalid_payload", "cycle"
    end
    state.seen[value] = true

    local validateOnly = state.validateOnly == true
    local result = validateOnly and value or {}
    for key, item in pairs(value) do
        local keyType = type(key)
        if keyType == "string" then
            if key == "" or #key > MAX_PAYLOAD_STRING_BYTES or HasForbiddenControl(key, false) then
                state.seen[value] = nil
                return nil, "invalid_payload", "invalid_key"
            end
        elseif keyType == "number" then
            if not IsInteger(key) then
                state.seen[value] = nil
                return nil, "invalid_payload", "invalid_key"
            end
        else
            state.seen[value] = nil
            return nil, "invalid_payload", "invalid_key_type:" .. keyType
        end

        state.nodes = state.nodes + 1
        if state.nodes > (state.maxNodes or MAX_PAYLOAD_NODES) then
            state.seen[value] = nil
            return nil, "invalid_payload", "max_nodes"
        end

        local localBinaryChild = type(localBinaryNode) == "table"
            and type(localBinaryNode.children) == "table"
            and localBinaryNode.children[key] or nil
        local cloned, code, detail = ClonePortable(
            item,
            state,
            depth + 1,
            localBinaryChild
        )
        if code then
            state.seen[value] = nil
            return nil, code, detail
        end
        if not validateOnly then result[key] = cloned end
    end

    state.seen[value] = nil
    return result
end

local function CloneProviderPayloadInternal(
    provider,
    value,
    extraNodes,
    extraDepth,
    work,
    allowLocalBinaryFields,
    validateOnly
)
    local maxNodes = type(provider) == "table"
        and provider.maxPayloadNodes or MAX_PAYLOAD_NODES
    local allowance = tonumber(extraNodes) or 0
    local depthAllowance = math.max(0, math.floor(tonumber(extraDepth) or 0))
    maxNodes = math.min(
        MAX_PROVIDER_PAYLOAD_NODES + allowance,
        maxNodes + allowance
    )
    local state = {
        seen = {},
        nodes = 0,
        maxNodes = maxNodes,
        maxDepth = MAX_PAYLOAD_DEPTH + depthAllowance,
        validateOnly = validateOnly == true,
    }
    if type(work) == "table" and type(work.checkpoint) == "function" then
        state.yieldIfNeeded = function(current)
            local ratio = math.min((current.nodes or 0) / math.max(maxNodes, 1), 0.99)
            work.checkpoint(
                "prepare-config-sets",
                0.78 + (0.18 * ratio),
                { processedNodes = current.nodes }
            )
        end
    end
    local localBinaryRoot = allowLocalBinaryFields == true
        and type(provider) == "table"
        and provider.localBinaryFieldRoot or nil
    return ClonePortable(value, state, nil, localBinaryRoot)
end

local function CloneProviderPayload(provider, value, extraNodes, extraDepth, work)
    return CloneProviderPayloadInternal(
        provider,
        value,
        extraNodes,
        extraDepth,
        work,
        false,
        false
    )
end

local function CloneProviderStoredPayload(provider, value, extraNodes, extraDepth, work)
    return CloneProviderPayloadInternal(
        provider,
        value,
        extraNodes,
        extraDepth,
        work,
        true,
        false
    )
end

local function ValidateProviderStoredPayload(provider, value, extraNodes, extraDepth)
    local validated, code, detail = CloneProviderPayloadInternal(
        provider,
        value,
        extraNodes,
        extraDepth,
        nil,
        true,
        true
    )
    if not validated then return nil, code, detail end
    return true
end

local function CloneProviderExportSource(provider, value)
    return ClonePortable(value, {
        seen = {},
        nodes = 0,
        maxNodes = type(provider) == "table"
            and provider.maxPayloadNodes or MAX_PAYLOAD_NODES,
        maxDepth = MAX_PAYLOAD_DEPTH,
        maxStringBytes = MAX_SERIALIZED_IMPORT_BYTES,
        allowControlStrings = true,
    })
end

local function IsDenseDefinitionList(value)
    if type(value) ~= "table" then return false end
    local length = #value
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or not IsInteger(key)
            or key < 1 or key > length then
            return false
        end
        count = count + 1
    end
    return count == length
end

local function CompileLocalBinaryFields(provider, definitions)
    if definitions == nil then return true end
    if not IsDenseDefinitionList(definitions) or #definitions == 0 then
        return nil, "invalid_provider", "invalid_local_binary_fields"
    end
    if type(provider.prepareExportData) ~= "function" then
        return nil, "invalid_provider", "local_binary_fields_require_prepare_export_data"
    end

    local root = { children = {} }
    local compiled = {}
    for index = 1, #definitions do
        local definition = definitions[index]
        if type(definition) ~= "table"
            or not IsDenseDefinitionList(definition.path)
            or #definition.path == 0
            or #definition.path > MAX_PAYLOAD_DEPTH
            or not IsInteger(definition.maxBytes)
            or definition.maxBytes <= MAX_PAYLOAD_STRING_BYTES
            or definition.maxBytes > MAX_SERIALIZED_IMPORT_BYTES then
            return nil, "invalid_provider", "invalid_local_binary_field"
        end
        for key in pairs(definition) do
            if key ~= "path" and key ~= "maxBytes" then
                return nil, "invalid_provider", "invalid_local_binary_field"
            end
        end
        if not provider.scopes[definition.path[1]] then
            return nil, "invalid_provider", "invalid_local_binary_scope"
        end

        local node = root
        local path = {}
        for pathIndex = 1, #definition.path do
            local segment = definition.path[pathIndex]
            if type(segment) ~= "string" or segment == ""
                or #segment > MAX_PAYLOAD_STRING_BYTES
                or HasForbiddenControl(segment, false) then
                return nil, "invalid_provider", "invalid_local_binary_path"
            end
            path[pathIndex] = segment
            node.children[segment] = node.children[segment]
                or { children = {} }
            node = node.children[segment]
        end
        if node.maxBytes ~= nil then
            return nil, "invalid_provider", "duplicate_local_binary_field"
        end
        node.maxBytes = definition.maxBytes
        compiled[index] = {
            path = path,
            maxBytes = definition.maxBytes,
        }
    end
    provider.localBinaryFields = compiled
    provider.localBinaryFieldRoot = root
    return true
end

local function PortableValuesEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] ~= nil then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not PortableValuesEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function MergeMissing(target, extension)
    for key, value in pairs(extension or {}) do
        if target[key] == nil then
            local cloned, code, detail = ClonePortable(value)
            if code then return nil, code, detail end
            target[key] = cloned
        elseif type(target[key]) == "table" and type(value) == "table" then
            local ok, code, detail = MergeMissing(target[key], value)
            if not ok then return nil, code, detail end
        end
    end
    return true
end

local function SafeCallback(callback, ...)
    if type(callback) ~= "function" then
        return true
    end
    local ok, first, second, third = pcall(callback, ...)
    if not ok then
        return false, "provider_error", first
    end
    if first == false or (first == nil and second ~= nil) then
        return false, second or "provider_error", third
    end
    if first == nil then first = true end
    return true, first, second
end

local function NormalizeScopeIds(provider, scopeIds, defaultAll)
    if scopeIds == nil and defaultAll then
        return CopyArray(provider.scopeOrder)
    end
    if type(scopeIds) ~= "table" then
        return nil, "invalid_scope"
    end

    local requested = {}
    for _, scopeId in ipairs(scopeIds) do
        if type(scopeId) ~= "string" or not provider.scopes[scopeId] then
            return nil, "invalid_scope", scopeId
        end
        requested[scopeId] = true
    end

    local normalized = {}
    for _, scopeId in ipairs(provider.scopeOrder) do
        if requested[scopeId] then
            normalized[#normalized + 1] = scopeId
            requested[scopeId] = nil
        end
    end
    if next(requested) ~= nil or #normalized == 0 then
        return nil, "invalid_scope"
    end
    return normalized
end

local function ValidateScopedData(provider, data, scopeIds)
    if type(data) ~= "table" then
        return nil, "invalid_payload", "root_not_table"
    end

    local allowed = {}
    for _, scopeId in ipairs(scopeIds) do
        allowed[scopeId] = true
        if data[scopeId] == nil then
            return nil, "invalid_payload", "missing_scope:" .. scopeId
        end
    end
    for scopeId in pairs(data) do
        if type(scopeId) ~= "string" or not allowed[scopeId] or not provider.scopes[scopeId] then
            return nil, "invalid_payload", "unknown_scope:" .. tostring(scopeId)
        end
    end
    return true
end

local function ValidateScopeSubsetData(provider, data, scopeIds)
    if type(data) ~= "table" then
        return nil, "invalid_payload", "root_not_table"
    end
    local allowed = {}
    for _, scopeId in ipairs(scopeIds) do
        allowed[scopeId] = true
    end
    local count = 0
    for scopeId in pairs(data) do
        if type(scopeId) ~= "string" or not allowed[scopeId] or not provider.scopes[scopeId] then
            return nil, "invalid_payload", "unknown_scope:" .. tostring(scopeId)
        end
        count = count + 1
    end
    if count == 0 then
        return nil, "invalid_payload", "empty_snapshot_extension"
    end
    return true
end

local function NormalizeProviderData(
    provider,
    data,
    scopeIds,
    context,
    work,
    allowLocalBinaryInput
)
    local cloneInput = allowLocalBinaryInput == true
        and CloneProviderStoredPayload or CloneProviderPayload
    local cloned, code, detail = cloneInput(provider, data, nil, nil, work)
    if code then return nil, code, detail end
    local valid
    valid, code, detail = ValidateScopedData(provider, cloned, scopeIds)
    if not valid then return nil, code, detail end

    for _, scopeId in ipairs(scopeIds) do
        local scope = provider.scopes[scopeId]
        if type(scope.normalize) == "function" then
            local current = cloned[scopeId]
            local ok, normalized, callbackDetail = SafeCallback(
                scope.normalize,
                current,
                context
            )
            if not ok then return nil, normalized, callbackDetail end
            if normalized ~= current then
                normalized, code, detail = CloneProviderStoredPayload(
                    provider,
                    normalized,
                    nil,
                    nil,
                    work
                )
                if code then return nil, code, detail end
            end
            cloned[scopeId] = normalized
        end
    end

    if type(provider.normalize) == "function" then
        local ok, normalized, callbackDetail = SafeCallback(provider.normalize, cloned, CopyArray(scopeIds), context)
        if not ok then return nil, normalized, callbackDetail end
        if normalized ~= cloned then
            cloned, code, detail = CloneProviderStoredPayload(provider, normalized)
            if code then return nil, code, detail end
        end
    end

    valid, code, detail = ValidateProviderStoredPayload(provider, cloned)
    if not valid then return nil, code, detail end
    valid, code, detail = ValidateScopedData(provider, cloned, scopeIds)
    if not valid then return nil, code, detail end
    return cloned
end

-- Data written with the current provider schema has already crossed the
-- provider normalization boundary. Read/apply paths still need an owned copy
-- and structural validation, but must not re-run provider callbacks.
local function CopyCanonicalProviderData(provider, data, scopeIds)
    local cloned, code, detail = CloneProviderStoredPayload(provider, data)
    if code then return nil, code, detail end
    local valid
    valid, code, detail = ValidateScopedData(provider, cloned, scopeIds)
    if not valid then return nil, code, detail end
    return cloned
end

local function BuildContext(provider, action, extra)
    local context = {
        action = action,
        providerId = provider.id,
        productId = provider.productId,
        schemaVersion = provider.schemaVersion,
        service = ConfigSets,
    }
    for key, value in pairs(extra or {}) do
        context[key] = value
    end
    return context
end

local function ResolvePreparedProviderData(provider, scopeIds, context)
    local options = type(context) == "table" and context.options or nil
    local token = type(options) == "table" and options.preparedToken or nil
    if token == nil then return nil, nil, nil, false end
    if type(provider.resolvePreparedUserSetData) ~= "function" then
        return nil, "invalid_payload", "invalid_prepared_token", true
    end
    local ok, resolved, detail = SafeCallback(
        provider.resolvePreparedUserSetData,
        token,
        context
    )
    if not ok then return nil, resolved, detail, true end
    if type(resolved) ~= "table" or type(resolved.data) ~= "table" then
        return nil, "invalid_payload", "invalid_prepared_token", true
    end
    local resolvedScopeIds, code, cloneDetail = NormalizeScopeIds(
        provider,
        resolved.scopeIds or scopeIds,
        false
    )
    if not resolvedScopeIds or not ArraysEqual(resolvedScopeIds, scopeIds) then
        return nil, code or "invalid_scope", cloneDetail, true
    end
    local data
    data, code, cloneDetail = CopyCanonicalProviderData(
        provider,
        resolved.data,
        resolvedScopeIds
    )
    if not data then return nil, code, cloneDetail, true end
    return data, nil, nil, true
end

local function Capture(provider, scopeIds, context)
    local prepared, code, detail, handled =
        ResolvePreparedProviderData(provider, scopeIds, context)
    if handled then return prepared, code, detail end
    if type(provider.capture) ~= "function" then
        return nil, "provider_error", "missing_capture"
    end
    local ok, data, detail = SafeCallback(provider.capture, CopyArray(scopeIds), context)
    if not ok then return nil, data, detail end
    return NormalizeProviderData(provider, data, scopeIds, context, nil, true)
end

local function HasAllProviderScopes(provider, scopeIds)
    return ArraysEqual(scopeIds, provider.scopeOrder)
end

local function ValidateAllScopeRequest(provider, scopeIds)
    if not UsesAllUserSetScopes(provider) or scopeIds == nil then return true end
    local normalized, code, detail = NormalizeScopeIds(provider, scopeIds, false)
    if not normalized then return nil, code, detail end
    if not HasAllProviderScopes(provider, normalized) then
        return nil, "scope_policy_all"
    end
    return true, normalized
end

local function MaterializeAllScopeData(provider, overlayData, overlayScopeIds, context, work)
    local allScopeIds = CopyArray(provider.scopeOrder)
    local data, code, detail = Capture(provider, allScopeIds, context)
    if not data then return nil, nil, code, detail end
    if overlayData then
        local clonedOverlay
        clonedOverlay, code, detail = CloneProviderStoredPayload(
            provider,
            overlayData,
            nil,
            nil,
            work
        )
        if not clonedOverlay then return nil, nil, code, detail end
        for _, scopeId in ipairs(overlayScopeIds or {}) do
            data[scopeId] = clonedOverlay[scopeId]
        end
    end
    data, code, detail = NormalizeProviderData(
        provider,
        data,
        allScopeIds,
        context,
        work,
        true
    )
    if not data then return nil, nil, code, detail end
    return data, allScopeIds
end

local function ResolvePreviewTexture(provider, builtin)
    local preview = builtin and builtin.preview
    if type(preview) ~= "table" then return nil end
    if type(preview.texture) == "string" and preview.texture ~= "" then
        return preview.texture
    end
    if type(preview.path) ~= "string" or preview.path == "" then
        return nil
    end
    if YUI.Assets and type(YUI.Assets.Product) == "function" then
        return YUI.Assets:Product(preview.productId or provider.productId, preview.path)
    end
    return preview.path
end

local function PublicScope(provider, scopeId, index)
    local scope = provider.scopes[scopeId]
    return {
        id = scopeId,
        order = index,
        labelKey = scope.labelKey,
        label = ConfigSets:GetText(provider, scope.labelKey, scope.label or scopeId),
    }
end

local function PublicBuiltin(provider, builtin)
    local nameKey = builtin.nameKey
    local name = ConfigSets:GetText(provider, nameKey, builtin.name or builtin.id)
    local description = ConfigSets:GetText(provider, builtin.descriptionKey, builtin.description or "")
    local preview, code = ClonePortable(builtin.preview)
    if code then preview = nil end
    return {
        kind = "builtin",
        id = builtin.id,
        name = name,
        title = name,
        nameKey = nameKey,
        titleKey = nameKey,
        description = description,
        descriptionKey = builtin.descriptionKey,
        preview = preview,
        previewTexture = ResolvePreviewTexture(provider, builtin),
        scopeIds = CopyArray(builtin.scopeIds),
        providerSchemaVersion = builtin.providerSchemaVersion,
        compatible = builtin.providerSchemaVersion == provider.schemaVersion,
    }
end

local function PublicUser(provider, item)
    local compatible = item.providerSchemaVersion == provider.schemaVersion
    if not compatible and type(provider.canMigrate) == "function" then
        local ok, canMigrate = pcall(
            provider.canMigrate,
            item.providerSchemaVersion,
            provider.schemaVersion
        )
        compatible = ok and canMigrate == true
    end
    return {
        kind = "user",
        id = item.id,
        name = item.name,
        title = item.name,
        description = item.description,
        scopeIds = CopyArray(item.scopeIds),
        providerSchemaVersion = item.providerSchemaVersion,
        compatible = compatible,
        createdAt = item.createdAt,
        updatedAt = item.updatedAt,
        configurationMode = item.configurationMode,
    }
end

local function NormalizePreview(provider, preview)
    if preview == false then return false end
    if type(preview) ~= "table" then
        return nil, "invalid_provider", "missing_preview"
    end

    local width = preview.width
    local height = preview.height
    local minimumWidth = provider.previewZoom and MIN_ZOOM_PREVIEW_WIDTH or MIN_PREVIEW_WIDTH
    local minimumHeight = provider.previewZoom and MIN_ZOOM_PREVIEW_HEIGHT or MIN_PREVIEW_HEIGHT
    if not IsInteger(width)
        or not IsInteger(height)
        or width < minimumWidth
        or height < minimumHeight
        or width > MAX_PREVIEW_WIDTH
        or height > MAX_PREVIEW_HEIGHT
        or width * 9 ~= height * 16 then
        return nil, "invalid_provider", "invalid_preview_size"
    end
    if (type(preview.path) ~= "string" or preview.path == "")
        and (type(preview.texture) ~= "string" or preview.texture == "") then
        return nil, "invalid_provider", "missing_preview_path"
    end
    if preview.path and (preview.path:find("..", 1, true) or preview.path:match("^[/\\]") or preview.path:match("^%a:")) then
        return nil, "invalid_provider", "invalid_preview_path"
    end
    local cloned, code, detail = ClonePortable(preview)
    if code then return nil, code, detail end
    return cloned
end

local function NormalizeBuiltin(provider, definition)
    if type(definition) ~= "table" or not IsStableId(definition.id) then
        return nil, "invalid_provider", "invalid_builtin_id"
    end

    local nameKey = definition.nameKey or definition.titleKey
    local name = definition.name or definition.title
    if (type(nameKey) ~= "string" or nameKey == "") and (type(name) ~= "string" or name == "") then
        return nil, "invalid_provider", "missing_builtin_name"
    end
    if (type(definition.descriptionKey) ~= "string" or definition.descriptionKey == "")
        and (type(definition.description) ~= "string" or definition.description == "") then
        return nil, "invalid_provider", "missing_builtin_description"
    end

    local preview, code, detail = NormalizePreview(provider, definition.preview)
    if code then return nil, code, detail end

    local scopeIds
    scopeIds, code, detail = NormalizeScopeIds(provider, definition.scopeIds, true)
    if not scopeIds then return nil, code, detail end

    local data
    data, code, detail = NormalizeProviderData(
        provider,
        definition.data,
        scopeIds,
        BuildContext(provider, "register_builtin", { definition = definition })
    )
    if not data then return nil, code, detail end

    return {
        id = definition.id,
        name = name,
        nameKey = nameKey,
        description = definition.description,
        descriptionKey = definition.descriptionKey,
        preview = preview,
        scopeIds = scopeIds,
        providerSchemaVersion = provider.schemaVersion,
        data = data,
    }
end

local function NormalizeStoredItem(provider, raw, expectedId)
    if type(raw) ~= "table" or raw.id ~= expectedId or not IsStableId(raw.id) then
        return nil, "invalid_payload", "invalid_stored_id"
    end
    local name, code, detail = NormalizeName(raw.name)
    if not name then return nil, code, detail end
    local description
    description, code, detail = NormalizeDescription(raw.description)
    if code then return nil, code, detail end
    local scopeIds
    scopeIds, code, detail = NormalizeScopeIds(provider, raw.scopeIds, false)
    if not scopeIds then return nil, code, detail end
    local data
    data, code, detail = CloneProviderStoredPayload(provider, raw.data)
    if code then return nil, code, detail end
    local valid
    valid, code, detail = ValidateScopedData(provider, data, scopeIds)
    if not valid then return nil, code, detail end

    local schemaVersion = tonumber(raw.providerSchemaVersion)
    if not IsInteger(schemaVersion) or schemaVersion < 1 then
        return nil, "invalid_payload", "invalid_provider_schema"
    end
    local configurationMode
    if SupportsConfigurationModes(provider) then
        configurationMode = NormalizeConfigurationMode(
            provider,
            raw.configurationMode or MODE_SPECIALIZATION,
            false
        )
        if not configurationMode then
            return nil, "invalid_payload", "invalid_configuration_mode"
        end
    end
    return {
        id = raw.id,
        name = name,
        description = description,
        scopeIds = scopeIds,
        providerSchemaVersion = schemaVersion,
        data = data,
        createdAt = IsFiniteNumber(raw.createdAt) and raw.createdAt or 0,
        updatedAt = IsFiniteNumber(raw.updatedAt) and raw.updatedAt or 0,
        configurationMode = configurationMode,
    }
end

local function NormalizeStoredItemMetadata(provider, raw, expectedId)
    if type(raw) ~= "table" or raw.id ~= expectedId or not IsStableId(raw.id) then
        return nil, "invalid_payload", "invalid_stored_id"
    end
    local name, code, detail = NormalizeName(raw.name)
    if not name then return nil, code, detail end
    local description
    description, code, detail = NormalizeDescription(raw.description)
    if code then return nil, code, detail end
    local scopeIds
    scopeIds, code, detail = NormalizeScopeIds(provider, raw.scopeIds, false)
    if not scopeIds then return nil, code, detail end
    if type(raw.data) ~= "table" then
        return nil, "invalid_payload", "invalid_stored_data"
    end

    local schemaVersion = tonumber(raw.providerSchemaVersion)
    if not IsInteger(schemaVersion) or schemaVersion < 1 then
        return nil, "invalid_payload", "invalid_provider_schema"
    end
    local configurationMode
    if SupportsConfigurationModes(provider) then
        configurationMode = NormalizeConfigurationMode(
            provider,
            raw.configurationMode or MODE_SPECIALIZATION,
            false
        )
        if not configurationMode then
            return nil, "invalid_payload", "invalid_configuration_mode"
        end
    end
    return {
        id = raw.id,
        name = name,
        description = description,
        scopeIds = scopeIds,
        providerSchemaVersion = schemaVersion,
        createdAt = IsFiniteNumber(raw.createdAt) and raw.createdAt or 0,
        updatedAt = IsFiniteNumber(raw.updatedAt) and raw.updatedAt or 0,
        configurationMode = configurationMode,
    }
end

local function PrepareStoredItemForExport(
    provider,
    raw,
    expectedId,
    action,
    extraContext
)
    if type(provider.prepareExportData) ~= "function" then
        return NormalizeStoredItem(provider, raw, expectedId)
    end

    local item, code, detail = NormalizeStoredItemMetadata(
        provider,
        raw,
        expectedId
    )
    if not item then return nil, code, detail end
    local source
    source, code, detail = CloneProviderExportSource(provider, raw.data)
    if not source then return nil, code, detail end
    local context = BuildContext(provider, action, extraContext)
    local ok, prepared, callbackDetail = SafeCallback(
        provider.prepareExportData,
        source,
        CopyArray(item.scopeIds),
        context
    )
    if not ok then return nil, prepared, callbackDetail end
    prepared, code, detail = CloneProviderPayload(provider, prepared)
    if not prepared then return nil, code, detail end
    local valid
    valid, code, detail = ValidateScopedData(
        provider,
        prepared,
        item.scopeIds
    )
    if not valid then return nil, code, detail end
    item.data = prepared
    return item
end

local function GetStore(provider, create)
    if ConfigSets.ProfileOwnership then
        return ConfigSets.ProfileOwnership:GetStore(provider, create)
    end
    local DB = YUI.DB
    if not (DB and DB.IsReady and DB:IsReady() and DB.GetGlobal) then
        return nil, "db_not_ready"
    end
    local global = DB:GetGlobal(provider.productId)
    if type(global) ~= "table" then
        return nil, "db_not_ready"
    end

    local store = global[ConfigSets.STORAGE_KEY]
    if store == nil and create then
        store = {
            schemaVersion = ConfigSets.SCHEMA_VERSION,
            providers = {},
        }
        global[ConfigSets.STORAGE_KEY] = store
    end
    if store == nil then return nil end
    if type(store) ~= "table"
        or store.schemaVersion ~= ConfigSets.SCHEMA_VERSION
        or type(store.providers) ~= "table" then
        return nil, "invalid_storage"
    end
    return store
end

local function GetCatalog(provider, create)
    local store, code, detail = GetStore(provider, create)
    if not store then return nil, code, detail end
    local catalog = store.providers[provider.id]
    if catalog == nil and create then
        catalog = {
            schemaVersion = ConfigSets.SCHEMA_VERSION,
            nextId = 1,
            order = {},
            items = {},
        }
        store.providers[provider.id] = catalog
    end
    if catalog == nil then return nil end
    if type(catalog) ~= "table"
        or catalog.schemaVersion ~= ConfigSets.SCHEMA_VERSION
        or type(catalog.order) ~= "table"
        or type(catalog.items) ~= "table" then
        return nil, "invalid_storage"
    end
    return catalog
end

local function ReferenceExists(provider, reference)
    reference = NormalizeReference(reference)
    if not reference then return false, "set_not_found" end
    if reference.kind == "builtin" then
        return provider.builtins[reference.id] ~= nil, provider.builtins[reference.id] and nil or "set_not_found"
    end

    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return false, code or "set_not_found", detail end
    local item
    item, code, detail = NormalizeStoredItem(provider, catalog.items[reference.id], reference.id)
    if not item then return false, code or "set_not_found", detail end
    return true
end

local function NormalizeSpecKey(value)
    if type(value) ~= "string" then return nil end
    local classToken, rawSpecID = value:match("^([A-Za-z][A-Za-z0-9_]*):(%d+)$")
    local specID = tonumber(rawSpecID)
    if not classToken or not IsInteger(specID) or specID < 1 then return nil end
    return string.upper(classToken) .. ":" .. tostring(specID)
end

local CollectSpecializationKeys

local function ExpandConfigurationSpecKeys(key)
    local talent = YUI.API and YUI.API.Talent
    return talent and talent.GetConfigurationSpecializationKeys
        and talent.GetConfigurationSpecializationKeys(key) or { key }
end

local function CollectSpecializationKeySet()
    local set = {}
    for _, specKey in ipairs(CollectSpecializationKeys()) do
        set[specKey] = true
    end
    return set
end

local function NormalizeSpecKeys(specKeys)
    if type(specKeys) ~= "table" then return nil, "invalid_specialization" end
    local seen = {}
    local supported = CollectSpecializationKeySet()
    local result = {}
    for _, value in ipairs(specKeys) do
        local key = NormalizeSpecKey(value)
        if not key then
            return nil, "invalid_specialization", value
        end
        for _, target in ipairs(ExpandConfigurationSpecKeys(key)) do
            if supported[target] ~= true then return nil, "invalid_specialization", value end
            if not seen[target] then
                seen[target] = true
                result[#result + 1] = target
            end
        end
    end
    table.sort(result)
    return result
end

local function IsAssignmentReferenceValid(provider, reference)
    local normalized = NormalizeReference(reference)
    if not normalized then return nil end
    local exists = ReferenceExists(provider, normalized)
    return exists and normalized or nil
end

local function EffectiveDefaultReference(provider, stored)
    local explicit = stored and IsAssignmentReferenceValid(provider, stored.default)
    if explicit then return explicit end
    return IsAssignmentReferenceValid(provider, provider.defaultAssignment)
end

local function GetEffectiveRuntimeAssignment(provider, stored, specKey)
    local enabled = type(stored) == "table" and stored.enabled == true
    if not enabled then return false, nil end

    local reference
    if specKey and type(stored.bySpec) == "table" then
        reference = IsAssignmentReferenceValid(provider, stored.bySpec[specKey])
    end
    if not reference then
        reference = EffectiveDefaultReference(provider, stored)
    end
    return true, reference
end

local function EffectiveRuntimeAssignmentChanged(
    beforeEnabled,
    beforeReference,
    afterEnabled,
    afterReference
)
    if beforeEnabled ~= afterEnabled then return true end
    if not beforeEnabled then return false end
    if beforeReference == nil or afterReference == nil then
        return beforeReference ~= afterReference
    end
    return not ReferencesEqual(beforeReference, afterReference)
end

local function ReadAssignments(provider)
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then
        if code then return nil, code, detail end
        return {
            enabled = false,
            default = EffectiveDefaultReference(provider),
            bySpec = {},
            enabledSets = {},
        }
    end

    local assignmentState = catalog
    if provider.editableUserSets and SupportsConfigurationModes(provider) then
        assignmentState, code, detail = GetProfileSpecializationState(
            provider,
            catalog,
            false
        )
        if not assignmentState then
            if code then return nil, code, detail end
            return {
                enabled = false,
                default = nil,
                bySpec = {},
                enabledSets = {},
            }
        end
    end
    local stored = assignmentState.assignments
    if stored ~= nil and type(stored) ~= "table" then
        return nil, "invalid_storage"
    end
    if stored and stored.enabled ~= nil and type(stored.enabled) ~= "boolean" then
        return nil, "invalid_storage"
    end
    if stored and stored.bySpec ~= nil and type(stored.bySpec) ~= "table" then
        return nil, "invalid_storage"
    end

    local result = {
        enabled = stored and stored.enabled == true or false,
        default = EffectiveDefaultReference(provider, stored),
        bySpec = {},
        enabledSets = {},
    }
    local supportedSpecKeys = CollectSpecializationKeySet()
    for rawKey, rawReference in pairs(stored and stored.bySpec or {}) do
        local key = NormalizeSpecKey(rawKey)
        local reference = IsAssignmentReferenceValid(provider, rawReference)
        if key and reference then
            for _, target in ipairs(ExpandConfigurationSpecKeys(key)) do
                if supportedSpecKeys[target] == true then
                    result.bySpec[target] = IsAssignmentReferenceValid(provider, stored.bySpec[target]) or reference
                end
            end
        end
    end
    if provider.editableUserSets and type(assignmentState.enabledUserSets) == "table" then
        for setId, enabled in pairs(assignmentState.enabledUserSets) do
            if enabled == true and type(catalog.items[setId]) == "table" then
                result.enabledSets[setId] = true
            end
        end
    end
    return result
end

local function EnsureStoredAssignments(provider)
    local catalog, code, detail = GetCatalog(provider, true)
    if not catalog then return nil, code, detail end
    local assignmentState = catalog
    if provider.editableUserSets and SupportsConfigurationModes(provider) then
        assignmentState, code, detail = GetProfileSpecializationState(
            provider,
            catalog,
            true
        )
        if not assignmentState then return nil, code, detail end
    end
    local stored = assignmentState.assignments
    if stored == nil then
        stored = {
            enabled = false,
            bySpec = {},
        }
        assignmentState.assignments = stored
    end
    if type(stored) ~= "table"
        or (stored.enabled ~= nil and type(stored.enabled) ~= "boolean")
        or (stored.bySpec ~= nil and type(stored.bySpec) ~= "table") then
        return nil, "invalid_storage"
    end
    if stored.bySpec == nil then stored.bySpec = {} end
    local migrated = {}
    for rawKey, reference in pairs(stored.bySpec) do
        for _, target in ipairs(ExpandConfigurationSpecKeys(rawKey)) do
            migrated[target] = stored.bySpec[target] or reference
        end
    end
    stored.bySpec = migrated
    local supportedSpecKeys = CollectSpecializationKeySet()
    for rawKey in pairs(stored.bySpec) do
        local specKey = NormalizeSpecKey(rawKey)
        if not specKey or supportedSpecKeys[specKey] ~= true then
            stored.bySpec[rawKey] = nil
        elseif specKey ~= rawKey then
            stored.bySpec[specKey] = stored.bySpec[rawKey]
            stored.bySpec[rawKey] = nil
        end
    end
    return stored, catalog, assignmentState
end

CollectSpecializationKeys = function()
    if type(S.GetSpecSelectionGroups) ~= "function" then return {} end
    local groups = S:GetSpecSelectionGroups({})
    if type(groups) ~= "table" then return {} end
    local result = {}
    local seen = {}
    for _, group in ipairs(groups) do
        for _, spec in ipairs(type(group) == "table" and group.specs or {}) do
            local key = NormalizeSpecKey(spec and spec.key)
            if key and not seen[key] then
                seen[key] = true
                result[#result + 1] = key
            end
        end
    end
    table.sort(result)
    return result
end

local function RemoveAssignmentReference(stored, reference)
    if type(stored) ~= "table"
        or (stored.bySpec ~= nil and type(stored.bySpec) ~= "table") then
        return nil, "invalid_storage"
    end
    local changed = false
    if ReferencesEqual(stored.default, reference) then
        stored.default = nil
        changed = true
    end
    for specKey, assigned in pairs(stored.bySpec or {}) do
        if ReferencesEqual(assigned, reference) then
            stored.bySpec[specKey] = nil
            changed = true
        end
    end
    return changed
end

GetProfileIdentity = function(provider)
    local DB = YUI.DB
    if not (DB and DB.IsReady and DB:IsReady() and DB.GetAceDB) then
        return nil, nil, "db_not_ready"
    end
    local db = DB:GetAceDB(provider.productId)
    if type(db) ~= "table" then
        return nil, nil, "db_not_ready"
    end
    local profileName = type(db.GetCurrentProfile) == "function" and db:GetCurrentProfile() or nil
    return db, profileName
end

GetProfileSpecializationState = function(provider, catalog, create, profileName)
    if not SupportsConfigurationModes(provider) then return catalog end
    if type(catalog) ~= "table" then return nil, "invalid_storage" end
    if profileName == nil then
        local _, resolvedProfileName, code = GetProfileIdentity(provider)
        if not resolvedProfileName then return nil, code end
        profileName = resolvedProfileName
    end
    if type(profileName) ~= "string" or profileName == "" then
        return nil, "profile_unavailable"
    end
    if catalog.specializationByProfile ~= nil
        and type(catalog.specializationByProfile) ~= "table" then
        return nil, "invalid_storage"
    end
    local byProfile = catalog.specializationByProfile
    if byProfile == nil and create then
        byProfile = {}
        catalog.specializationByProfile = byProfile
    end
    local state = type(byProfile) == "table" and byProfile[profileName] or nil
    if state == nil and create then
        state = {
            assignments = {
                enabled = false,
                bySpec = {},
            },
            enabledUserSets = {},
            disabledAssignments = {},
        }
        byProfile[profileName] = state
    end
    if state ~= nil and type(state) ~= "table" then
        return nil, "invalid_storage"
    end
    return state
end

local function InvalidateProfileState(providerId, database, profileName, reason)
    local active = ConfigSets.activeReferences[providerId]
    local activeRemoved = active
        and active.database == database
        and active.profileName == profileName
    if activeRemoved then
        ConfigSets.activeReferences[providerId] = nil
    end

    local transaction = ConfigSets.transactions[providerId]
    if transaction
        and transaction.database == database
        and transaction.profileName == profileName
    then
        ConfigSets.transactions[providerId] = nil
    end

    if activeRemoved then
        Emit(
            "YUI_CONFIG_SET_ACTIVE_CHANGED",
            providerId,
            nil,
            reason or "state-invalidated"
        )
    end
end

local function NameExists(provider, catalog, name, excludeId, configurationMode)
    local nameKey = NormalizeNameKey(name)
    for id, raw in pairs(catalog.items) do
        if id ~= excludeId and type(raw) == "table" and type(raw.name) == "string" then
            local rawMode = SupportsConfigurationModes(provider)
                and (raw.configurationMode or MODE_SPECIALIZATION)
                or nil
            local normalized = NormalizeName(raw.name)
            if (configurationMode == nil or rawMode == configurationMode)
                and normalized
                and NormalizeNameKey(normalized) == nameKey then
                return true
            end
        end
    end
    return false
end

local function NextUserId(catalog)
    local nextId = tonumber(catalog.nextId)
    if not IsInteger(nextId) or nextId < 1 then nextId = 1 end
    local id
    repeat
        id = "u" .. tostring(nextId)
        nextId = nextId + 1
    until catalog.items[id] == nil
    catalog.nextId = nextId
    return id
end

local function CountItems(provider, catalog, configurationMode)
    local count = 0
    for _, raw in pairs(catalog.items) do
        local rawMode = SupportsConfigurationModes(provider)
            and type(raw) == "table"
            and (raw.configurationMode or MODE_SPECIALIZATION)
            or nil
        if configurationMode == nil or rawMode == configurationMode then
            count = count + 1
        end
    end
    return count
end

local function RemoveOrderId(order, targetId)
    for index = #order, 1, -1 do
        if order[index] == targetId then
            table.remove(order, index)
        end
    end
end

local function CurrentTime()
    if type(time) == "function" then return time() end
    return 0
end

function ConfigSets:GetText(providerOrId, key, fallback)
    if type(key) ~= "string" or key == "" then return fallback end
    local provider = type(providerOrId) == "table" and providerOrId or self.providers[providerOrId]
    local namespaces = {}
    if provider and provider.localeNamespace then
        namespaces[#namespaces + 1] = provider.localeNamespace
    end
    if not provider or provider.localeNamespace ~= "Core" then
        namespaces[#namespaces + 1] = "Core"
    end
    if YUI.Locale and type(YUI.Locale.Get) == "function" then
        for _, namespace in ipairs(namespaces) do
            local locale = YUI.Locale:Get(namespace)
            local value = locale and locale[key]
            if type(value) == "string" and value ~= "" and value ~= key then
                return value
            end
        end
    end
    return fallback or key
end

local function MakeUniqueName(provider, catalog, preferredName, configurationMode)
    if not NameExists(provider, catalog, preferredName, nil, configurationMode) then
        return preferredName
    end

    local suffix = Trim(ConfigSets:GetText(
        provider,
        "settings.config_sets.copy_suffix",
        "Copy"
    ))
    if not suffix
        or suffix == ""
        or HasForbiddenControl(suffix, false)
        or Utf8Length(suffix) > MAX_NAME_CHARS
        or #suffix > MAX_NAME_BYTES then
        suffix = "Copy"
    end

    for copyIndex = 1, provider.maxUserSets + 1 do
        local tail = " " .. suffix
        if copyIndex > 1 then
            tail = tail .. " " .. tostring(copyIndex)
        end
        local prefix = Utf8Prefix(
            preferredName,
            MAX_NAME_CHARS - Utf8Length(tail),
            MAX_NAME_BYTES - #tail
        )
        local candidate = NormalizeName((Trim(prefix) or "") .. tail)
        if candidate and not NameExists(provider, catalog, candidate, nil, configurationMode) then
            return candidate
        end
    end
    return nil, "duplicate_name"
end

local function StoredUserReference(provider, catalog, setId)
    if not IsStableId(setId) then return nil end
    local item = NormalizeStoredItem(provider, catalog.items[setId], setId)
    if not item then return nil end
    return { kind = "user", id = setId }, item
end

local function StoredUserReferenceMetadata(provider, catalog, setId)
    if not IsStableId(setId) then return nil end
    local item = NormalizeStoredItemMetadata(
        provider,
        catalog.items[setId],
        setId
    )
    if not item then return nil end
    return { kind = "user", id = setId }, item
end

local function FirstStoredUserReference(provider, catalog, excludedId, configurationMode)
    for _, setId in ipairs(catalog.order) do
        if setId ~= excludedId then
            local reference, item = StoredUserReference(provider, catalog, setId)
            if reference
                and (configurationMode == nil or item.configurationMode == configurationMode) then
                return reference
            end
        end
    end
    return nil
end

local function DefaultStoredUserReference(provider, catalog, configurationMode)
    local builtinId = provider.defaultAssignment and provider.defaultAssignment.id
        or provider.builtinOrder[1]
    local builtin = builtinId and provider.builtins[builtinId] or nil
    if not builtin then return nil end
    for _, setId in ipairs(catalog.order) do
        local reference, item = StoredUserReference(provider, catalog, setId)
        if reference
            and (configurationMode == nil
                or item.configurationMode == configurationMode)
            and item.providerSchemaVersion == provider.schemaVersion
            and ArraysEqual(item.scopeIds, builtin.scopeIds)
            and PortableValuesEqual(item.data, builtin.data) then
            return reference
        end
    end
    return nil
end

local function FirstEnabledUserReference(provider, catalog, excludedId, assignmentState)
    assignmentState = assignmentState or catalog
    local enabled = type(assignmentState.enabledUserSets) == "table"
        and assignmentState.enabledUserSets
        or {}
    for _, setId in ipairs(catalog.order) do
        if setId ~= excludedId and enabled[setId] == true then
            local reference = StoredUserReference(provider, catalog, setId)
            if reference then return reference end
        end
    end
    return nil
end

local function EnsureDisabledAssignments(provider, catalog, assignmentState)
    assignmentState = assignmentState or catalog
    local stored = assignmentState.disabledAssignments
    if stored ~= nil and type(stored) ~= "table" then
        return nil, "invalid_storage"
    end
    stored = stored or {}
    assignmentState.disabledAssignments = stored
    for setId, selection in pairs(stored) do
        if not StoredUserReference(provider, catalog, setId) then
            stored[setId] = nil
        elseif type(selection) ~= "table" then
            return nil, "invalid_storage"
        else
            local normalized = {}
            local supported = CollectSpecializationKeySet()
            for rawKey, selected in pairs(selection) do
                local specKey = NormalizeSpecKey(rawKey)
                if selected ~= true or not specKey then
                    return nil, "invalid_storage"
                end
                if supported[specKey] == true then
                    normalized[specKey] = true
                end
            end
            stored[setId] = normalized
        end
    end
    return stored
end

local function CollectStoredSpecSelection(selection)
    local result = {}
    for specKey, selected in pairs(type(selection) == "table" and selection or {}) do
        if selected == true then result[#result + 1] = specKey end
    end
    table.sort(result)
    return result
end

local function MakeStoredSpecSelection(specKeys)
    local result = {}
    for _, specKey in ipairs(specKeys or {}) do
        result[specKey] = true
    end
    return result
end

local function CollectProfileNames(database, catalog, currentProfileName)
    local names = {}
    local seen = {}
    local function Add(value)
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            names[#names + 1] = value
        end
    end
    Add(currentProfileName)
    if type(database) == "table" and type(database.GetProfiles) == "function" then
        local profiles = {}
        local ok, result = pcall(database.GetProfiles, database, profiles)
        if ok and type(result) == "table" then profiles = result end
        for key, value in pairs(profiles) do
            Add(type(value) == "string" and value or key)
        end
    end
    for _, field in ipairs({
        "activeByProfile",
        "configurationModeByProfile",
        "activeByConfigurationMode",
        "specializationByProfile",
    }) do
        for profileName in pairs(type(catalog[field]) == "table" and catalog[field] or {}) do
            Add(profileName)
        end
    end
    table.sort(names)
    return names
end

local function CloneSpecializationState(source)
    local cloned, code, detail = ClonePortable(source, {
        seen = {},
        nodes = 0,
        maxNodes = MAX_PAYLOAD_NODES,
    })
    if not cloned then return nil, code, detail end
    if type(cloned.assignments) ~= "table"
        or type(cloned.assignments.bySpec) ~= "table"
        or type(cloned.enabledUserSets) ~= "table"
        or type(cloned.disabledAssignments) ~= "table" then
        return nil, "invalid_storage"
    end
    return cloned
end

local function EnsureSpecializationProfileStorage(
    provider,
    catalog,
    database,
    profileName,
    normalizedLegacyState
)
    if not SupportsConfigurationModes(provider) then return catalog end
    local version = catalog.specializationProfileStateVersion
    if version ~= nil and version ~= SPECIALIZATION_PROFILE_STATE_VERSION then
        return nil, "invalid_storage"
    end
    if version == SPECIALIZATION_PROFILE_STATE_VERSION then
        return GetProfileSpecializationState(provider, catalog, true, profileName)
    end
    if type(normalizedLegacyState) ~= "table" then
        return nil, "invalid_storage"
    end

    local staged = {}
    for _, storedProfileName in ipairs(
        CollectProfileNames(database, catalog, profileName)
    ) do
        local cloned, code, detail = CloneSpecializationState(normalizedLegacyState)
        if not cloned then return nil, code, detail end
        staged[storedProfileName] = cloned
    end
    if staged[profileName] == nil then
        local cloned, code, detail = CloneSpecializationState(normalizedLegacyState)
        if not cloned then return nil, code, detail end
        staged[profileName] = cloned
    end

    catalog.specializationByProfile = staged
    catalog.specializationProfileStateVersion = SPECIALIZATION_PROFILE_STATE_VERSION
    catalog.assignments = nil
    catalog.enabledUserSets = nil
    catalog.disabledAssignments = nil
    return staged[profileName]
end

local function BuildEditableAssignmentSnapshot(
    provider,
    catalog,
    stored,
    allSpecKeys,
    assignmentState
)
    assignmentState = assignmentState or catalog
    local result = {
        enabled = stored.enabled == true,
        default = CopyReference(stored.default),
        bySpec = {},
        enabledSets = {},
        byReference = {},
    }
    local selectedBySet = {}
    for specKey, reference in pairs(stored.bySpec or {}) do
        if type(specKey) == "string"
            and type(reference) == "table"
            and reference.kind == "user"
            and type(reference.id) == "string"
        then
            result.bySpec[specKey] = CopyReference(reference)
            local selected = selectedBySet[reference.id]
            if not selected then
                selected = {}
                selectedBySet[reference.id] = selected
            end
            selected[specKey] = true
        end
    end
    for setId, enabled in pairs(assignmentState.enabledUserSets or {}) do
        if enabled == true and type(catalog.items[setId]) == "table" then
            result.enabledSets[setId] = true
        end
    end

    for setId, item in pairs(catalog.items or {}) do
        local itemMode = SupportsConfigurationModes(provider)
            and type(item) == "table"
            and (item.configurationMode or MODE_SPECIALIZATION)
            or MODE_SPECIALIZATION
        if type(setId) == "string"
            and type(item) == "table"
            and itemMode == MODE_SPECIALIZATION then
            local enabled = result.enabledSets[setId] == true
            local selected = enabled
                and selectedBySet[setId]
                or (assignmentState.disabledAssignments or {})[setId]
                or {}
            local specKeys = CollectStoredSpecSelection(selected)
            local ownsAll = #allSpecKeys > 0
            for _, specKey in ipairs(allSpecKeys) do
                if selected[specKey] ~= true then
                    ownsAll = false
                    break
                end
            end
            local mode = "none"
            if ownsAll
                or (enabled
                    and #allSpecKeys == 0
                    and stored.default
                    and stored.default.id == setId)
            then
                mode = "all"
            elseif #specKeys > 0 then
                mode = "specs"
            end
            result.byReference["user:" .. setId] = {
                mode = mode,
                specKeys = mode == "all" and CopyArray(allSpecKeys) or specKeys,
                enabled = enabled,
            }
        end
    end
    return result
end

local function GetEditableEffectiveRuntimeAssignment(stored, specKey)
    if type(stored) ~= "table" or stored.enabled ~= true then
        return false, nil
    end
    local reference = specKey
        and type(stored.bySpec) == "table"
        and stored.bySpec[specKey]
        or nil
    reference = reference or stored.default
    return true, CopyReference(reference)
end

local function EnsureCurrentProviderSchemaCatalog(provider, catalog)
    local prepared = {}
    local migratedCount = 0

    for _, setId in ipairs(catalog.order) do
        local raw = catalog.items[setId]
        local item, code, detail = NormalizeStoredItem(provider, raw, setId)
        if not item then return nil, code or "invalid_storage", detail end

        if item.providerSchemaVersion ~= provider.schemaVersion then
            if type(provider.canMigrate) ~= "function"
                or type(provider.migrate) ~= "function" then
                return nil, "incompatible_schema"
            end
            local canMigrateOk, canMigrate = pcall(
                provider.canMigrate,
                item.providerSchemaVersion,
                provider.schemaVersion
            )
            if not canMigrateOk or canMigrate ~= true then
                return nil, "incompatible_schema"
            end

            local context = BuildContext(provider, "schema-migration", {
                kind = "user",
                id = setId,
                sourceSchemaVersion = item.providerSchemaVersion,
            })
            local ok, migrated, migrateDetail = SafeCallback(
                provider.migrate,
                item.data,
                item.providerSchemaVersion,
                provider.schemaVersion,
                context
            )
            if not ok then return nil, migrated, migrateDetail end

            local normalized
            normalized, code, detail = NormalizeProviderData(
                provider,
                migrated,
                item.scopeIds,
                context,
                nil,
                true
            )
            if not normalized then return nil, code, detail end
            prepared[setId] = normalized
            migratedCount = migratedCount + 1
        elseif type(provider.repairCurrentStoredData) == "function" then
            local source
            source, code, detail = CloneProviderStoredPayload(
                provider,
                item.data
            )
            if not source then return nil, code, detail end
            local context = BuildContext(provider, "local-storage-repair", {
                kind = "user",
                id = setId,
                sourceSchemaVersion = item.providerSchemaVersion,
            })
            local ok, repaired, changed = SafeCallback(
                provider.repairCurrentStoredData,
                source,
                context
            )
            if not ok then return nil, repaired, changed end
            if type(repaired) ~= "table" then
                return nil, "invalid_storage", "invalid_local_repair"
            end
            if changed == true then
                repaired, code, detail = CopyCanonicalProviderData(
                    provider,
                    repaired,
                    item.scopeIds
                )
                if not repaired then return nil, code, detail end
                prepared[setId] = repaired
                migratedCount = migratedCount + 1
            end
        end
    end

    -- Commit only after every stale item has migrated and normalized.
    for setId, data in pairs(prepared) do
        local raw = catalog.items[setId]
        raw.data = data
        raw.providerSchemaVersion = provider.schemaVersion
    end
    return true, migratedCount
end

local function EnsureAllScopeCatalog(provider, catalog)
    if not UsesAllUserSetScopes(provider) then return true end
    if catalog.userSetScopePolicyVersion == USER_SET_SCOPE_POLICY_VERSION then
        return true
    end

    local allScopeIds = CopyArray(provider.scopeOrder)
    local baseline, code, detail = Capture(
        provider,
        allScopeIds,
        BuildContext(provider, "scope-policy-migration")
    )
    if not baseline then return nil, code, detail end

    local prepared = {}
    for _, setId in ipairs(catalog.order) do
        local raw = catalog.items[setId]
        local item
        item, code, detail = NormalizeStoredItem(provider, raw, setId)
        if not item then return nil, code or "invalid_storage", detail end

        local sourceData = item.data
        if item.providerSchemaVersion ~= provider.schemaVersion then
            if type(provider.canMigrate) ~= "function"
                or type(provider.migrate) ~= "function" then
                return nil, "incompatible_schema"
            end
            local canMigrateOk, canMigrate = pcall(
                provider.canMigrate,
                item.providerSchemaVersion,
                provider.schemaVersion
            )
            if not canMigrateOk or canMigrate ~= true then
                return nil, "incompatible_schema"
            end
            local migrated
            local ok
            ok, migrated, detail = SafeCallback(
                provider.migrate,
                sourceData,
                item.providerSchemaVersion,
                provider.schemaVersion,
                BuildContext(provider, "scope-policy-migration", {
                    kind = "user",
                    id = setId,
                })
            )
            if not ok then return nil, migrated, detail end
            sourceData = migrated
        end
        sourceData, code, detail = NormalizeProviderData(
            provider,
            sourceData,
            item.scopeIds,
            BuildContext(provider, "scope-policy-migration", {
                kind = "user",
                id = setId,
            }),
            nil,
            true
        )
        if not sourceData then return nil, code, detail end

        local merged
        merged, code, detail = CloneProviderStoredPayload(provider, baseline)
        if not merged then return nil, code, detail end
        for _, scopeId in ipairs(item.scopeIds) do
            merged[scopeId] = sourceData[scopeId]
        end
        merged, code, detail = NormalizeProviderData(
            provider,
            merged,
            allScopeIds,
            BuildContext(provider, "scope-policy-migration", {
                kind = "user",
                id = setId,
            }),
            nil,
            true
        )
        if not merged then return nil, code, detail end
        prepared[setId] = merged
    end

    -- Commit only after every item has been validated and materialized.
    for setId, data in pairs(prepared) do
        local raw = catalog.items[setId]
        raw.scopeIds = CopyArray(allScopeIds)
        raw.data = data
        raw.providerSchemaVersion = provider.schemaVersion
    end
    catalog.userSetScopePolicyVersion = USER_SET_SCOPE_POLICY_VERSION
    return true
end

local function CreateUserFromBuiltin(provider, catalog, builtinId, configurationMode)
    local builtin = provider.builtins[builtinId]
    if not builtin then return nil, "set_not_found" end
    configurationMode = NormalizeConfigurationMode(
        provider,
        configurationMode,
        SupportsConfigurationModes(provider)
    )
    if CountItems(provider, catalog, configurationMode) >= provider.maxUserSets then
        return nil, "set_limit"
    end

    local publicBuiltin = PublicBuiltin(provider, builtin)
    local name, code = MakeUniqueName(
        provider,
        catalog,
        publicBuiltin.name,
        configurationMode
    )
    if not name then return nil, code end
    local data, scopeIds, cloneCode, cloneDetail
    if UsesAllUserSetScopes(provider) then
        data, scopeIds, cloneCode, cloneDetail = MaterializeAllScopeData(
            provider,
            builtin.data,
            builtin.scopeIds,
            BuildContext(provider, "create-default", {
                source = { kind = "builtin", id = builtinId },
            })
        )
    else
        data, cloneCode, cloneDetail = CloneProviderStoredPayload(
            provider,
            builtin.data
        )
        scopeIds = CopyArray(builtin.scopeIds)
    end
    if not data then return nil, cloneCode, cloneDetail end

    local id = NextUserId(catalog)
    local now = CurrentTime()
    local item = {
        id = id,
        name = name,
        description = publicBuiltin.description,
        providerSchemaVersion = provider.schemaVersion,
        scopeIds = scopeIds,
        data = data,
        createdAt = now,
        updatedAt = now,
        configurationMode = configurationMode,
    }
    catalog.items[id] = item
    catalog.order[#catalog.order + 1] = id
    return { kind = "user", id = id }, item
end

local function PersistActiveReference(provider, catalog, profileName, reference)
    if not provider.editableUserSets or type(profileName) ~= "string" or profileName == "" then
        return
    end
    if catalog.activeByProfile ~= nil and type(catalog.activeByProfile) ~= "table" then
        catalog.activeByProfile = nil
    end
    catalog.activeByProfile = catalog.activeByProfile or {}
    local normalized = NormalizeReference(reference)
    if normalized and normalized.kind == "user" then
        catalog.activeByProfile[profileName] = normalized.id
    else
        catalog.activeByProfile[profileName] = nil
    end
end

local function PersistConfigurationMode(provider, catalog, profileName, mode)
    if not SupportsConfigurationModes(provider)
        or type(profileName) ~= "string"
        or profileName == "" then
        return
    end
    catalog.configurationModeByProfile =
        type(catalog.configurationModeByProfile) == "table"
        and catalog.configurationModeByProfile
        or {}
    catalog.configurationModeByProfile[profileName] = mode
end

local function PersistModeActiveReference(
    provider,
    catalog,
    profileName,
    mode,
    reference
)
    if not SupportsConfigurationModes(provider)
        or type(profileName) ~= "string"
        or profileName == ""
        or not NormalizeConfigurationMode(provider, mode, false) then
        return
    end
    catalog.activeByConfigurationMode =
        type(catalog.activeByConfigurationMode) == "table"
        and catalog.activeByConfigurationMode
        or {}
    local byMode = catalog.activeByConfigurationMode[profileName]
    if type(byMode) ~= "table" then
        byMode = {}
        catalog.activeByConfigurationMode[profileName] = byMode
    end
    local normalized = NormalizeReference(reference)
    byMode[mode] = normalized and normalized.kind == "user"
        and normalized.id
        or nil
end

local function GetModeActiveReference(provider, catalog, profileName, mode)
    if not SupportsConfigurationModes(provider) then return nil end
    local byProfile = catalog.activeByConfigurationMode
    local byMode = type(byProfile) == "table" and byProfile[profileName] or nil
    local setId = type(byMode) == "table" and byMode[mode] or nil
    local reference, item = StoredUserReferenceMetadata(
        provider,
        catalog,
        setId
    )
    if reference and item.configurationMode == mode then return reference end
    return nil
end

local function DuplicateUserIntoMode(provider, catalog, sourceId, configurationMode)
    local _, source = StoredUserReference(provider, catalog, sourceId)
    if not source then return nil, "set_not_found" end
    if CountItems(provider, catalog, configurationMode) >= provider.maxUserSets then
        return nil, "set_limit"
    end
    local data, code, detail = CloneProviderStoredPayload(provider, source.data)
    if not data then return nil, code, detail end
    local name
    name, code = MakeUniqueName(
        provider,
        catalog,
        source.name,
        configurationMode
    )
    if not name then return nil, code end
    local id = NextUserId(catalog)
    local now = CurrentTime()
    local item = {
        id = id,
        name = name,
        description = source.description,
        providerSchemaVersion = source.providerSchemaVersion,
        scopeIds = CopyArray(source.scopeIds),
        data = data,
        createdAt = now,
        updatedAt = now,
        configurationMode = configurationMode,
    }
    catalog.items[id] = item
    catalog.order[#catalog.order + 1] = id
    return { kind = "user", id = id }, item
end

local function ReplaceStoredReference(stored, previousReference, nextReference)
    if type(stored) ~= "table" then return false end
    local changed = false
    if ReferencesEqual(stored.default, previousReference) then
        stored.default = CopyReference(nextReference)
        changed = true
    end
    for specKey, reference in pairs(stored.bySpec or {}) do
        if ReferencesEqual(reference, previousReference) then
            stored.bySpec[specKey] = CopyReference(nextReference)
            changed = true
        end
    end
    return changed
end

local function EnsureConfigurationModeCatalog(
    provider,
    catalog,
    profileName,
    activeReference,
    createdItems
)
    if not SupportsConfigurationModes(provider) then return true end
    if catalog.configurationModeByProfile ~= nil
        and type(catalog.configurationModeByProfile) ~= "table" then
        return nil, "invalid_storage"
    end
    if catalog.activeByConfigurationMode ~= nil
        and type(catalog.activeByConfigurationMode) ~= "table" then
        return nil, "invalid_storage"
    end
    catalog.configurationModeByProfile = catalog.configurationModeByProfile or {}
    catalog.activeByConfigurationMode = catalog.activeByConfigurationMode or {}

    for setId, raw in pairs(catalog.items) do
        if type(raw) ~= "table" then return nil, "invalid_storage" end
        local mode = raw.configurationMode or MODE_SPECIALIZATION
        if not NormalizeConfigurationMode(provider, mode, false) then
            return nil, "invalid_storage"
        end
        raw.configurationMode = mode
    end

    if catalog.configurationModesMigrated ~= true then
        local clonedBySource = {}
        local unifiedFallback
        local function EnsureUnifiedCopy(sourceId)
            if sourceId and clonedBySource[sourceId] then
                return clonedBySource[sourceId]
            end
            local reference, item
            if sourceId then
                local _, source = StoredUserReference(provider, catalog, sourceId)
                if source and source.configurationMode == MODE_SPECIALIZATION then
                    reference, item = DuplicateUserIntoMode(
                        provider,
                        catalog,
                        sourceId,
                        MODE_UNIFIED
                    )
                end
            end
            if not reference then return nil end
            clonedBySource[sourceId] = reference
            createdItems[#createdItems + 1] = item
            unifiedFallback = unifiedFallback or reference
            return reference
        end

        for storedProfile, sourceId in pairs(
            type(catalog.activeByProfile) == "table" and catalog.activeByProfile or {}
        ) do
            local specializationReference, specializationItem =
                StoredUserReference(provider, catalog, sourceId)
            if specializationReference
                and specializationItem.configurationMode == MODE_SPECIALIZATION then
                local unifiedReference = EnsureUnifiedCopy(sourceId)
                if unifiedReference then
                    PersistModeActiveReference(
                        provider,
                        catalog,
                        storedProfile,
                        MODE_SPECIALIZATION,
                        specializationReference
                    )
                    PersistModeActiveReference(
                        provider,
                        catalog,
                        storedProfile,
                        MODE_UNIFIED,
                        unifiedReference
                    )
                    PersistConfigurationMode(
                        provider,
                        catalog,
                        storedProfile,
                        provider.configurationModes.defaultMode
                    )
                end
            end
        end

        local currentSource = activeReference
        local currentUnified = currentSource
            and EnsureUnifiedCopy(currentSource.id)
            or nil
        if not currentUnified then
            currentUnified = FirstStoredUserReference(
                provider,
                catalog,
                nil,
                MODE_UNIFIED
            )
        end
        if not currentUnified then
            local builtinId = provider.defaultAssignment and provider.defaultAssignment.id
                or provider.builtinOrder[1]
            local item
            currentUnified, item = CreateUserFromBuiltin(
                provider,
                catalog,
                builtinId,
                MODE_UNIFIED
            )
            if not currentUnified then return nil, item end
            createdItems[#createdItems + 1] = item
        end
        unifiedFallback = unifiedFallback or currentUnified

        if type(profileName) == "string" and profileName ~= "" then
            PersistModeActiveReference(
                provider,
                catalog,
                profileName,
                MODE_SPECIALIZATION,
                currentSource
            )
            PersistModeActiveReference(
                provider,
                catalog,
                profileName,
                MODE_UNIFIED,
                currentUnified
            )
            PersistConfigurationMode(
                provider,
                catalog,
                profileName,
                provider.configurationModes.defaultMode
            )
        end
        catalog.configurationModesMigrated = true
    end

    local profileModeStateWasMissing = type(
        catalog.activeByConfigurationMode[profileName]
    ) ~= "table"
    local mode = catalog.configurationModeByProfile[profileName]
    if not NormalizeConfigurationMode(provider, mode, false) then
        mode = provider.configurationModes.defaultMode
        PersistConfigurationMode(provider, catalog, profileName, mode)
    end
    local rememberedByMode = {}
    for _, targetMode in ipairs({ MODE_SPECIALIZATION, MODE_UNIFIED }) do
        local remembered = GetModeActiveReference(
            provider,
            catalog,
            profileName,
            targetMode
        )
        if not remembered
            and targetMode == MODE_SPECIALIZATION
            and type(activeReference) == "table"
            and (profileModeStateWasMissing
                or type(catalog.activeByConfigurationMode[profileName]) == "table") then
            local activeStored, activeItem = StoredUserReference(
                provider,
                catalog,
                activeReference.id
            )
            if activeStored and activeItem.configurationMode == targetMode then
                remembered = activeStored
            end
        end
        if not remembered then
            remembered = DefaultStoredUserReference(
                provider,
                catalog,
                targetMode
            )
            if not remembered and not profileModeStateWasMissing then
                remembered = FirstStoredUserReference(
                    provider,
                    catalog,
                    nil,
                    targetMode
                )
            end
        end
        if not remembered then
            local builtinId = provider.defaultAssignment and provider.defaultAssignment.id
                or provider.builtinOrder[1]
            local item, code
            remembered, item, code = CreateUserFromBuiltin(
                provider,
                catalog,
                builtinId,
                targetMode
            )
            if not remembered then return nil, item, code end
            createdItems[#createdItems + 1] = item
        end
        PersistModeActiveReference(
            provider,
            catalog,
            profileName,
            targetMode,
            remembered
        )
        rememberedByMode[targetMode] = remembered
    end
    return true, mode, rememberedByMode[mode]
end

local function EnsureEditableCatalog(provider)
    if not provider.editableUserSets then return nil, "not_editable_user_sets" end
    local catalog, code, detail = GetCatalog(provider, true)
    if not catalog then return nil, code, detail end
    if UsesAllUserSetScopes(provider)
        and catalog.userSetScopePolicyVersion ~= USER_SET_SCOPE_POLICY_VERSION then
        local scopePolicyReady
        scopePolicyReady, code, detail = EnsureAllScopeCatalog(provider, catalog)
        if not scopePolicyReady then return nil, code, detail end
    else
        local schemaReady
        schemaReady, code, detail = EnsureCurrentProviderSchemaCatalog(provider, catalog)
        if not schemaReady then return nil, code, detail end
    end

    if ConfigSets.ProfileOwnership then
        return ConfigSets.ProfileOwnership:EnsureCatalog(provider, catalog)
    end
    local builtinUsers = {}
    local createdItems = {}
    local function EnsureBuiltinUser(builtinId)
        if builtinUsers[builtinId] then return builtinUsers[builtinId] end
        local reference, item
        reference, item, detail = CreateUserFromBuiltin(provider, catalog, builtinId)
        if not reference then return nil, item, detail end
        builtinUsers[builtinId] = reference
        createdItems[#createdItems + 1] = item
        return reference
    end
    local function ConvertReference(reference)
        local normalized = NormalizeReference(reference)
        if not normalized then return nil end
        if normalized.kind == "user" then
            local storedReference, item =
                StoredUserReference(provider, catalog, normalized.id)
            if storedReference
                and (not SupportsConfigurationModes(provider)
                    or item.configurationMode == MODE_SPECIALIZATION) then
                return storedReference
            end
            return nil
        end
        if normalized.kind == "builtin" and provider.builtins[normalized.id] then
            return EnsureBuiltinUser(normalized.id)
        end
        return nil
    end

    local db, profileName, identityError = GetProfileIdentity(provider)
    if not db then return nil, identityError end
    local assignmentState = catalog
    local profileSpecializationStateWasMissing = false
    if SupportsConfigurationModes(provider)
        and catalog.specializationProfileStateVersion == SPECIALIZATION_PROFILE_STATE_VERSION then
        profileSpecializationStateWasMissing = type(catalog.specializationByProfile) ~= "table"
            or catalog.specializationByProfile[profileName] == nil
        assignmentState, code, detail = GetProfileSpecializationState(
            provider,
            catalog,
            true,
            profileName
        )
        if not assignmentState then return nil, code, detail end
    end

    local stored = assignmentState.assignments
    if stored ~= nil and type(stored) ~= "table" then
        return nil, "invalid_storage"
    end
    if stored == nil then
        stored = {
            enabled = false,
            bySpec = {},
        }
        assignmentState.assignments = stored
    end
    if stored.enabled ~= nil and type(stored.enabled) ~= "boolean" then
        return nil, "invalid_storage"
    end
    if stored.bySpec ~= nil and type(stored.bySpec) ~= "table" then
        return nil, "invalid_storage"
    end
    stored.bySpec = stored.bySpec or {}

    local defaultReference
    if stored.default then
        defaultReference, code, detail = ConvertReference(stored.default)
        if not defaultReference and code then return nil, code, detail end
    end
    if not defaultReference then
        defaultReference = DefaultStoredUserReference(
            provider,
            catalog,
            SupportsConfigurationModes(provider) and MODE_SPECIALIZATION or nil
        )
        if not defaultReference and not profileSpecializationStateWasMissing then
            defaultReference = FirstStoredUserReference(
                provider,
                catalog,
                nil,
                SupportsConfigurationModes(provider) and MODE_SPECIALIZATION or nil
            )
        end
    end
    if not defaultReference then
        local builtinId = provider.defaultAssignment and provider.defaultAssignment.id
            or provider.builtinOrder[1]
        if not builtinId then return nil, "default_required" end
        defaultReference, code, detail = EnsureBuiltinUser(builtinId)
        if not defaultReference then return nil, code, detail end
    end
    stored.default = CopyReference(defaultReference)

    for specKey, reference in pairs(stored.bySpec) do
        local converted
        converted, code, detail = ConvertReference(reference)
        if converted then
            stored.bySpec[specKey] = CopyReference(converted)
        elseif code then
            return nil, code, detail
        else
            stored.bySpec[specKey] = nil
        end
    end

    local enabledUserSets = assignmentState.enabledUserSets
    if enabledUserSets ~= nil and type(enabledUserSets) ~= "table" then
        return nil, "invalid_storage"
    end
    local migrateEnabledSets = enabledUserSets == nil
    enabledUserSets = enabledUserSets or {}
    assignmentState.enabledUserSets = enabledUserSets
    for setId, enabled in pairs(enabledUserSets) do
        local reference, item = StoredUserReference(provider, catalog, setId)
        if enabled ~= true
            or not reference
            or (SupportsConfigurationModes(provider)
                and item.configurationMode ~= MODE_SPECIALIZATION) then
            enabledUserSets[setId] = nil
        end
    end
    if migrateEnabledSets then
        if defaultReference and defaultReference.kind == "user" then
            enabledUserSets[defaultReference.id] = true
        end
        for _, reference in pairs(stored.bySpec) do
            if reference.kind == "user" then enabledUserSets[reference.id] = true end
        end
    end
    if not FirstEnabledUserReference(provider, catalog, nil, assignmentState) then
        enabledUserSets[defaultReference.id] = true
    end
    local disabledAssignments
    disabledAssignments, code = EnsureDisabledAssignments(
        provider,
        catalog,
        assignmentState
    )
    if not disabledAssignments then return nil, code end
    for setId in pairs(enabledUserSets) do
        disabledAssignments[setId] = nil
    end
    if not enabledUserSets[stored.default.id] then
        stored.default = CopyReference(
            FirstEnabledUserReference(provider, catalog, nil, assignmentState)
                or defaultReference
        )
    end
    local allSpecKeys = CollectSpecializationKeys()
    local supportedSpecKeys = {}
    for _, specKey in ipairs(allSpecKeys) do
        supportedSpecKeys[specKey] = true
        local assigned = stored.bySpec[specKey]
        if not assigned or enabledUserSets[assigned.id] ~= true then
            stored.bySpec[specKey] = CopyReference(stored.default)
        end
    end
    for specKey, reference in pairs(stored.bySpec) do
        if supportedSpecKeys[specKey] ~= true
            or enabledUserSets[reference.id] ~= true then
            stored.bySpec[specKey] = nil
        end
    end

    if SupportsConfigurationModes(provider) then
        local normalizedSpecializationState = {
            assignments = stored,
            enabledUserSets = enabledUserSets,
            disabledAssignments = disabledAssignments,
        }
        assignmentState, code, detail = EnsureSpecializationProfileStorage(
            provider,
            catalog,
            db,
            profileName,
            normalizedSpecializationState
        )
        if not assignmentState then return nil, code, detail end
        stored = assignmentState.assignments
        enabledUserSets = assignmentState.enabledUserSets
    end
    local active = ConfigSets.activeReferences[provider.id]
    local activeReference
    if active and active.database == db and active.profileName == profileName then
        activeReference, code, detail = ConvertReference(active.reference)
        if not activeReference and code then return nil, code, detail end
    end
    if not activeReference
        and type(profileName) == "string"
        and type(catalog.activeByProfile) == "table"
    then
        activeReference = StoredUserReference(
            provider,
            catalog,
            catalog.activeByProfile[profileName]
        )
    end
    if not activeReference then
        local specKey = ConfigSets:GetCurrentSpecializationKey()
        activeReference = specKey and StoredUserReference(
            provider,
            catalog,
            stored.bySpec[specKey] and stored.bySpec[specKey].id
        ) or nil
    end
    activeReference = activeReference or CopyReference(defaultReference)
    ConfigSets.activeReferences[provider.id] = {
        database = db,
        profileName = profileName,
        reference = CopyReference(activeReference),
    }
    PersistActiveReference(provider, catalog, profileName, activeReference)

    local mode
    local remembered
    local modeReady
    modeReady, mode, remembered = EnsureConfigurationModeCatalog(
        provider,
        catalog,
        profileName,
        activeReference,
        createdItems
    )
    if not modeReady then return nil, mode, remembered end
    if SupportsConfigurationModes(provider) then
        activeReference = remembered or activeReference
        ConfigSets.activeReferences[provider.id] = {
            database = db,
            profileName = profileName,
            reference = CopyReference(activeReference),
        }
        PersistActiveReference(provider, catalog, profileName, activeReference)
    end

    return {
        reference = CopyReference(activeReference),
        configurationMode = mode,
        created = #createdItems,
        createdItems = createdItems,
    }
end

local function ReadReadyEditableAssignmentCatalog(provider)
    local catalog, code, detail = GetCatalog(provider, false)
    if ConfigSets.ProfileOwnership then
        if catalog and ConfigSets.ProfileOwnership:IsReady(provider, catalog) then return catalog end
        return nil, code, detail
    end
    local assignmentState
    if type(catalog) == "table" then
        if SupportsConfigurationModes(provider) then
            assignmentState = GetProfileSpecializationState(provider, catalog, false)
        else
            assignmentState = catalog
        end
    end
    local stored = assignmentState and assignmentState.assignments
    local ready = type(catalog) == "table"
        and type(catalog.items) == "table"
        and type(catalog.order) == "table"
        and type(assignmentState) == "table"
        and type(assignmentState.enabledUserSets) == "table"
        and type(assignmentState.disabledAssignments) == "table"
        and type(stored) == "table"
        and (stored.enabled == nil or type(stored.enabled) == "boolean")
        and type(stored.bySpec) == "table"
        and type(stored.default) == "table"
        and stored.default.kind == "user"
        and type(catalog.items[stored.default.id]) == "table"
        and (not UsesAllUserSetScopes(provider)
            or catalog.userSetScopePolicyVersion == USER_SET_SCOPE_POLICY_VERSION)
    if ready then
        for _, setId in ipairs(catalog.order or {}) do
            local raw = catalog.items[setId]
            if type(raw) ~= "table"
                or tonumber(raw.providerSchemaVersion) ~= provider.schemaVersion then
                ready = false
                break
            end
        end
    end
    if ready then
        for setId, enabled in pairs(assignmentState.enabledUserSets) do
            local raw = catalog.items[setId]
            local mode = SupportsConfigurationModes(provider)
                and type(raw) == "table"
                and (raw.configurationMode or MODE_SPECIALIZATION)
                or MODE_SPECIALIZATION
            if enabled ~= true
                or type(raw) ~= "table"
                or mode ~= MODE_SPECIALIZATION then
                ready = false
                break
            end
        end
    end
    if ready then
        for specKey, reference in pairs(stored.bySpec) do
            if type(specKey) ~= "string"
                or type(reference) ~= "table"
                or reference.kind ~= "user"
                or assignmentState.enabledUserSets[reference.id] ~= true
            then
                ready = false
                break
            end
        end
    end
    if ready then return catalog end
    return nil, code, detail
end

local function GetReadyEditableAssignmentCatalog(provider)
    local catalog, code, detail = ReadReadyEditableAssignmentCatalog(provider)
    if catalog then return catalog end
    local ensured
    ensured, code, detail = EnsureEditableCatalog(provider)
    if not ensured then return nil, code, detail end
    return GetCatalog(provider, false)
end

local function EnsureEditableCatalogForExport(provider)
    if type(provider.prepareExportData) == "function" then
        local catalog, code, detail =
            GetReadyEditableAssignmentCatalog(provider)
        if not catalog then return nil, code, detail end
        return true
    end
    return EnsureEditableCatalog(provider)
end

local function GetReadyEditableAssignmentState(provider, catalog)
    catalog = catalog or GetReadyEditableAssignmentCatalog(provider)
    if type(catalog) ~= "table" then return nil, "invalid_storage" end
    if not SupportsConfigurationModes(provider) then return catalog end
    return GetProfileSpecializationState(provider, catalog, false)
end

function ConfigSets:RegisterProvider(definition)
    if type(definition) ~= "table"
        or not IsStableId(definition.id, MAX_PROVIDER_ID_BYTES)
        or not IsStableId(definition.productId or definition.id, MAX_PROVIDER_ID_BYTES) then
        return nil, "invalid_provider"
    end
    if self.providers[definition.id] then
        return nil, "invalid_provider", "duplicate_provider"
    end

    local schemaVersion = tonumber(definition.schemaVersion)
    if not IsInteger(schemaVersion) or schemaVersion < 1 then
        return nil, "invalid_provider", "invalid_schema"
    end
    local maxPayloadNodes = MAX_PAYLOAD_NODES
    if definition.maxPayloadNodes ~= nil then
        maxPayloadNodes = tonumber(definition.maxPayloadNodes)
        if not IsInteger(maxPayloadNodes)
            or maxPayloadNodes < MAX_PAYLOAD_NODES
            or maxPayloadNodes > MAX_PROVIDER_PAYLOAD_NODES then
            return nil, "invalid_provider", "invalid_max_payload_nodes"
        end
    end
    if definition.previewZoom ~= nil and type(definition.previewZoom) ~= "boolean" then
        return nil, "invalid_provider", "invalid_preview_zoom"
    end
    if definition.specializationAssignments ~= nil and type(definition.specializationAssignments) ~= "boolean" then
        return nil, "invalid_provider", "invalid_specialization_assignments"
    end
    if definition.autoApplyAssignments ~= nil and type(definition.autoApplyAssignments) ~= "boolean" then
        return nil, "invalid_provider", "invalid_auto_apply_assignments"
    end
    if definition.assignmentReady ~= nil and type(definition.assignmentReady) ~= "function" then
        return nil, "invalid_provider", "invalid_assignment_ready"
    end
    if definition.prepareExportData ~= nil
        and type(definition.prepareExportData) ~= "function" then
        return nil, "invalid_provider", "invalid_prepare_export_data"
    end
    if definition.resolvePreparedUserSetData ~= nil
        and type(definition.resolvePreparedUserSetData) ~= "function" then
        return nil, "invalid_provider", "invalid_prepared_resolver"
    end
    if definition.editableUserSets ~= nil and type(definition.editableUserSets) ~= "boolean" then
        return nil, "invalid_provider", "invalid_editable_user_sets"
    end
    if definition.userSetScopePolicy ~= nil
        and definition.userSetScopePolicy ~= USER_SET_SCOPE_POLICY_ALL then
        return nil, "invalid_provider", "invalid_user_set_scope_policy"
    end
    if definition.userSetScopePolicy == USER_SET_SCOPE_POLICY_ALL
        and definition.editableUserSets ~= true then
        return nil, "invalid_provider", "scope_policy_requires_editable_user_sets"
    end
    local configurationModes
    if definition.configurationModes ~= nil then
        if type(definition.configurationModes) ~= "table"
            or definition.configurationModes.isolatedLibraries ~= true then
            return nil, "invalid_provider", "invalid_configuration_modes"
        end
        local defaultMode = definition.configurationModes.defaultMode
            or MODE_SPECIALIZATION
        if defaultMode ~= MODE_UNIFIED and defaultMode ~= MODE_SPECIALIZATION then
            return nil, "invalid_provider", "invalid_configuration_mode"
        end
        configurationModes = {
            isolatedLibraries = true,
            defaultMode = defaultMode,
        }
    end
    local defaultAssignment
    if definition.defaultAssignment ~= nil then
        defaultAssignment = NormalizeReference(definition.defaultAssignment)
        if not defaultAssignment or defaultAssignment.kind ~= "builtin" then
            return nil, "invalid_provider", "invalid_default_assignment"
        end
    end
    if type(definition.scopes) ~= "table" or type(definition.scopeOrder) ~= "table" then
        return nil, "invalid_provider", "missing_scopes"
    end

    local provider = {
        id = definition.id,
        productId = definition.productId or definition.id,
        schemaVersion = schemaVersion,
        localeNamespace = definition.localeNamespace or "Core",
        maxUserSets = math.max(1, math.floor(tonumber(definition.maxUserSets) or self.MAX_USER_SETS)),
        maxPayloadNodes = maxPayloadNodes,
        previewZoom = definition.previewZoom ~= false,
        scopes = {},
        scopeOrder = {},
        builtins = {},
        builtinOrder = {},
        canApply = definition.canApply,
        capture = definition.capture,
        normalize = definition.normalize,
        repairCurrentStoredData = definition.repairCurrentStoredData,
        prepareExportData = definition.prepareExportData,
        resolvePreparedUserSetData = definition.resolvePreparedUserSetData,
        apply = definition.apply,
        restore = definition.restore,
        restoreForReload = definition.restoreForReload,
        refresh = definition.refresh,
        migrate = definition.migrate,
        canMigrate = definition.canMigrate,
        owner = definition.owner,
        specializationAssignments = definition.specializationAssignments == true,
        defaultAssignment = defaultAssignment,
        autoApplyAssignments = definition.autoApplyAssignments == true,
        assignmentReady = definition.assignmentReady,
        editableUserSets = definition.editableUserSets == true,
        userSetScopePolicy = definition.userSetScopePolicy,
        configurationModes = not self.ProfileOwnership and configurationModes or nil,
    }

    local seenScopes = {}
    for _, scopeId in ipairs(definition.scopeOrder) do
        local scope = definition.scopes[scopeId]
        if not IsStableId(scopeId) or seenScopes[scopeId] or type(scope) ~= "table" then
            return nil, "invalid_provider", "invalid_scope"
        end
        seenScopes[scopeId] = true
        provider.scopeOrder[#provider.scopeOrder + 1] = scopeId
        provider.scopes[scopeId] = {
            id = scopeId,
            label = scope.label,
            labelKey = scope.labelKey,
            normalize = scope.normalize,
        }
    end
    if #provider.scopeOrder == 0 then
        return nil, "invalid_provider", "missing_scopes"
    end
    for scopeId in pairs(definition.scopes) do
        if not seenScopes[scopeId] then
            return nil, "invalid_provider", "unordered_scope:" .. tostring(scopeId)
        end
    end
    if type(provider.capture) ~= "function" or type(provider.apply) ~= "function" then
        return nil, "invalid_provider", "missing_callbacks"
    end
    if provider.restoreForReload ~= nil
        and type(provider.restoreForReload) ~= "function" then
        return nil, "invalid_provider", "invalid_reload_restore"
    end
    local binaryFieldsOK, binaryFieldsCode, binaryFieldsDetail =
        CompileLocalBinaryFields(provider, definition.localBinaryFields)
    if not binaryFieldsOK then
        return nil, binaryFieldsCode, binaryFieldsDetail
    end

    for _, builtinDefinition in ipairs(definition.builtins or {}) do
        local builtin, code, detail = NormalizeBuiltin(provider, builtinDefinition)
        if not builtin then return nil, code, detail end
        if provider.builtins[builtin.id] then
            return nil, "invalid_provider", "duplicate_builtin"
        end
        provider.builtins[builtin.id] = builtin
        provider.builtinOrder[#provider.builtinOrder + 1] = builtin.id
    end
    if provider.defaultAssignment
        and provider.defaultAssignment.kind == "builtin"
        and not provider.builtins[provider.defaultAssignment.id] then
        return nil, "invalid_provider", "default_assignment_not_found"
    end
    if provider.autoApplyAssignments and not provider.specializationAssignments then
        return nil, "invalid_provider", "auto_apply_without_specialization_assignments"
    end
    if provider.editableUserSets and #provider.builtinOrder == 0 then
        return nil, "invalid_provider", "editable_user_sets_require_builtins"
    end
    if SupportsConfigurationModes(provider)
        and (
            not provider.editableUserSets
            or not provider.specializationAssignments
            or not provider.autoApplyAssignments
        ) then
        return nil, "invalid_provider", "configuration_modes_require_editable_assignments"
    end

    self.providers[provider.id] = provider
    Emit("YUI_CONFIG_SET_PROVIDER_REGISTERED", provider.id, provider)
    local runtime = S.ConfigSetRuntime
    if runtime and type(runtime.ReconcileProvider) == "function" then
        runtime:ReconcileProvider(provider.id, "provider-registered")
    end
    return provider
end


function ConfigSets:RegisterBuiltin(providerId, definition)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local builtin, code, detail = NormalizeBuiltin(provider, definition)
    if not builtin then return nil, code, detail end
    if provider.builtins[builtin.id] then
        return nil, "invalid_provider", "duplicate_builtin"
    end
    provider.builtins[builtin.id] = builtin
    provider.builtinOrder[#provider.builtinOrder + 1] = builtin.id
    local public = PublicBuiltin(provider, builtin)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "register-builtin", public)
    return public
end

function ConfigSets:GetProvider(providerId)
    return self.providers[providerId]
end

function ConfigSets:GetScopes(providerId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local result = {}
    for index, scopeId in ipairs(provider.scopeOrder) do
        result[index] = PublicScope(provider, scopeId, index)
    end
    return result
end

function ConfigSets:ListBuiltins(providerId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local result = {}
    for _, id in ipairs(provider.builtinOrder) do
        result[#result + 1] = PublicBuiltin(provider, provider.builtins[id])
    end
    return result
end

function ConfigSets:ListUserSets(providerId, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if provider.editableUserSets then
        local ready, readyCode, readyDetail =
            GetReadyEditableAssignmentCatalog(provider)
        if not ready then return nil, readyCode, readyDetail end
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then
        if code then return nil, code, detail end
        return {}
    end
    options = type(options) == "table" and options or {}
    local configurationMode
    if SupportsConfigurationModes(provider) then
        configurationMode = NormalizeConfigurationMode(
            provider,
            options.configurationMode or MODE_SPECIALIZATION,
            false
        )
        if not configurationMode then return nil, "invalid_configuration_mode" end
    end
    local result = {}
    for _, id in ipairs(catalog.order) do
        local item = NormalizeStoredItemMetadata(
            provider,
            catalog.items[id],
            id
        )
        if item and (
            configurationMode == nil
            or item.configurationMode == configurationMode
        ) then
            result[#result + 1] = PublicUser(provider, item)
        end
    end
    return result
end

function ConfigSets:GetSet(providerId, kind, setId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if kind == "builtin" then
        local builtin = provider.builtins[setId]
        if not builtin then return nil, "set_not_found" end
        return PublicBuiltin(provider, builtin)
    end
    if kind ~= "user" then return nil, "set_not_found" end
    if provider.editableUserSets then
        local ready, readyCode, readyDetail =
            GetReadyEditableAssignmentCatalog(provider)
        if not ready then return nil, readyCode, readyDetail end
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local item
    item, code, detail = NormalizeStoredItemMetadata(
        provider,
        catalog.items[setId],
        setId
    )
    if not item then return nil, code or "set_not_found", detail end
    return PublicUser(provider, item)
end

function ConfigSets:GetPreviewTexture(providerId, setId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local builtin = provider.builtins[setId]
    if not builtin then return nil, "set_not_found" end
    return ResolvePreviewTexture(provider, builtin)
end

function ConfigSets:GetCurrentSpecializationKey()
    local TalentAPI = YUI.API and YUI.API.Talent or YUI.WOW_API or {}
    local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API or {}
    local classToken
    local unitClass = UnitAPI.UnitClass or _G.UnitClass
    if type(unitClass) == "function" then
        local ok, _, token = pcall(unitClass, "player")
        if ok then classToken = token end
    end

    if type((TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)) == "function" then
        local ok, specInfo = pcall((TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo))
        if ok and type(specInfo) == "table" then
            if specInfo.isInitial == true then return nil end
            if not IsInteger(tonumber(specInfo.specID)) or tonumber(specInfo.specID) < 1 then
                return nil
            end
            return NormalizeSpecKey(
                tostring(specInfo.classFile or classToken or "")
                    .. ":"
                    .. tostring(specInfo.specID)
            )
        end
    end

    -- Wrath 的专精适配层在未投入天赋点时会明确返回 specID=nil。
    -- 不能继续回退到双天赋组序号，否则会生成并不存在的稳定专精键。
    if YUI.IsWrath or (YUI.IsForever and TalentAPI.GetCurrentConfigurationSpecializationInfo) then return nil end
    if type(S.GetCurrentSpecSelectionKey) == "function" then
        local ok, value = pcall(S.GetCurrentSpecSelectionKey, S)
        if ok then return NormalizeSpecKey(value) end
    end
    return nil
end

function ConfigSets:GetSpecializationGroups(providerId, options)
    if type(providerId) == "table" and options == nil then
        options = providerId
        providerId = nil
    end
    if providerId ~= nil then
        local provider = self.providers[providerId]
        if not provider then return nil, "provider_not_found" end
        if not provider.specializationAssignments then
            return nil, "specialization_assignments_not_supported"
        end
    end
    if type(S.GetSpecSelectionGroups) ~= "function" then
        return nil, "specialization_unavailable"
    end
    return S:GetSpecSelectionGroups(type(options) == "table" and options or {})
end

function ConfigSets:GetAssignments(providerId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.specializationAssignments then
        return nil, "specialization_assignments_not_supported"
    end
    if self.ProfileOwnership and provider.editableUserSets then
        local catalog, code = GetReadyEditableAssignmentCatalog(provider)
        if not catalog then return nil, code end
        return S.ConfigSetAssignments:Snapshot(catalog)
    end
    if provider.editableUserSets then
        local catalog, code, detail =
            GetReadyEditableAssignmentCatalog(provider)
        if not catalog then return nil, code, detail end
        local assignmentState
        assignmentState, code, detail = GetReadyEditableAssignmentState(
            provider,
            catalog
        )
        if not assignmentState then return nil, code, detail end
        return BuildEditableAssignmentSnapshot(
            provider,
            catalog,
            assignmentState.assignments,
            CollectSpecializationKeys(),
            assignmentState
        )
    end
    return ReadAssignments(provider)
end

function ConfigSets:GetAssignment(providerId, reference)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.specializationAssignments then
        return nil, "specialization_assignments_not_supported"
    end
    if provider.editableUserSets then
        if type(reference) == "table" and reference.kind ~= "user" then
            return nil, "set_not_found"
        end
        reference = NormalizeReference(reference)
        if not reference or reference.kind ~= "user" then
            return nil, "set_not_found"
        end
        local assignments, code, detail = self:GetAssignments(providerId)
        if not assignments then return nil, code, detail end
        local assignment = assignments.byReference[
            "user:" .. reference.id
        ]
        if not assignment then return nil, "set_not_found" end
        return {
            mode = assignment.mode,
            specKeys = CopyArray(assignment.specKeys),
            enabled = assignment.enabled == true,
        }
    end
    reference = NormalizeReference(reference)
    local exists, code, detail = ReferenceExists(provider, reference)
    if not exists then return nil, code, detail end

    local assignments
    assignments, code, detail = ReadAssignments(provider)
    if not assignments then return nil, code, detail end
    if ReferencesEqual(assignments.default, reference) then
        return {
            mode = "default",
            specKeys = {},
        }
    end

    local specKeys = {}
    for specKey, assigned in pairs(assignments.bySpec) do
        if ReferencesEqual(assigned, reference) then
            specKeys[#specKeys + 1] = specKey
        end
    end
    table.sort(specKeys)
    if #specKeys > 0 then
        return {
            mode = "specs",
            specKeys = specKeys,
        }
    end
    return {
        mode = "none",
        specKeys = {},
    }
end

function ConfigSets:SetAssignment(providerId, reference, mode, specKeys)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.specializationAssignments then
        return nil, "specialization_assignments_not_supported"
    end
    if self.ProfileOwnership and provider.editableUserSets then
        if self.busy[providerId] then return nil, "busy" end
        local catalog, why = GetReadyEditableAssignmentCatalog(provider)
        if not catalog then return nil, why end
        if type(mode) == "table" then specKeys, mode = mode.specKeys or mode.specializationKeys, mode.mode end
        local nextState, report = S.ConfigSetAssignments:Prepare(catalog, reference, mode, specKeys,
            CollectSpecializationKeySet(), self:GetCurrentSpecializationKey())
        if not nextState then return nil, report end
        local assignment = report.assignmentSnapshot.byReference["user:" .. reference.id]
        if report.changed then
            catalog.assignments = nextState
            Emit("YUI_CONFIG_SETS_CHANGED", providerId, "assignment", report)
            if report.runtimeChanged then Emit("YUI_CONFIG_SET_ASSIGNMENTS_CHANGED", providerId, CopyReference(reference), assignment) end
        end
        return assignment, nil, report
    end
    local code, detail
    local editableCatalog
    if provider.editableUserSets then
        if type(reference) == "table" and reference.kind ~= "user" then
            return nil, "set_not_found"
        end
        editableCatalog, code, detail =
            GetReadyEditableAssignmentCatalog(provider)
        if not editableCatalog then return nil, code, detail end
    end

    if type(mode) == "table" then
        local options = mode
        mode = options.mode
        specKeys = options.specKeys or options.specializationKeys
    end
    if provider.editableUserSets and mode == "default" then mode = "all" end
    if provider.editableUserSets then
        if mode ~= "all" and mode ~= "specs" and mode ~= "none" then
            return nil, "invalid_assignment_mode"
        end
    elseif mode ~= "default" and mode ~= "specs" and mode ~= "none" then
        return nil, "invalid_assignment_mode"
    end

    reference = NormalizeReference(reference)
    if provider.editableUserSets then
        if not reference
            or reference.kind ~= "user"
            or type(editableCatalog.items[reference.id]) ~= "table"
        then
            return nil, "set_not_found"
        end
        if SupportsConfigurationModes(provider) then
            local item = NormalizeStoredItem(
                provider,
                editableCatalog.items[reference.id],
                reference.id
            )
            if not item or item.configurationMode ~= MODE_SPECIALIZATION then
                return nil, "wrong_configuration_mode"
            end
        end
    else
        local exists
        exists, code, detail = ReferenceExists(provider, reference)
        if not exists then return nil, code, detail end
    end

    local normalizedSpecKeys = {}
    if mode == "specs" then
        normalizedSpecKeys, code, detail = NormalizeSpecKeys(specKeys)
        if not normalizedSpecKeys then return nil, code, detail end
        if #normalizedSpecKeys == 0 then return nil, "invalid_specialization" end
    end

    if provider.editableUserSets then
        local catalog = editableCatalog
        local assignmentState
        assignmentState, code, detail = GetReadyEditableAssignmentState(
            provider,
            catalog
        )
        if not assignmentState then return nil, code, detail end
        local stored = assignmentState.assignments

        local allSpecKeys = CollectSpecializationKeys()
        if mode == "all" then
            normalizedSpecKeys = CopyArray(allSpecKeys)
        end
        local isEnabled = type(assignmentState.enabledUserSets) == "table"
            and assignmentState.enabledUserSets[reference.id] == true
        if not isEnabled then
            local disabledAssignments
            disabledAssignments, code = EnsureDisabledAssignments(
                provider,
                catalog,
                assignmentState
            )
            if not disabledAssignments then return nil, code end
            disabledAssignments[reference.id] =
                MakeStoredSpecSelection(normalizedSpecKeys)

            local assignmentSnapshot = BuildEditableAssignmentSnapshot(
                provider,
                catalog,
                stored,
                allSpecKeys,
                assignmentState
            )
            local assignment =
                assignmentSnapshot.byReference["user:" .. reference.id]
            local publicReference = CopyReference(reference)
            Emit("YUI_CONFIG_SETS_CHANGED", providerId, "assignment-draft", {
                reference = publicReference,
                assignment = assignment,
                assignmentSnapshot = assignmentSnapshot,
            })
            return assignment, nil, {
                assignmentSnapshot = assignmentSnapshot,
                runtimeChanged = false,
            }
        end

        local currentSpecKey = self:GetCurrentSpecializationKey()
        local runtimeEnabledBefore, runtimeReferenceBefore =
            GetEditableEffectiveRuntimeAssignment(stored, currentSpecKey)
        local selected = {}
        for _, specKey in ipairs(normalizedSpecKeys) do
            selected[specKey] = true
        end
        local fallback = FirstEnabledUserReference(
            provider,
            catalog,
            reference.id,
            assignmentState
        )
        if not fallback and mode == "none" then
            return nil, "enabled_required"
        end
        if not fallback and mode == "specs" then
            normalizedSpecKeys = CopyArray(allSpecKeys)
            selected = {}
            for _, specKey in ipairs(normalizedSpecKeys) do
                selected[specKey] = true
            end
        end
        for specKey, assigned in pairs(stored.bySpec) do
            if ReferencesEqual(assigned, reference)
                and not selected[specKey]
                and fallback
            then
                stored.bySpec[specKey] = CopyReference(fallback)
            end
        end
        for _, specKey in ipairs(normalizedSpecKeys) do
            stored.bySpec[specKey] = CopyReference(reference)
        end
        if mode == "all" then
            stored.default = CopyReference(reference)
        elseif mode == "none"
            and fallback
            and ReferencesEqual(stored.default, reference)
        then
            stored.default = CopyReference(fallback)
        elseif not stored.default
            or assignmentState.enabledUserSets[stored.default.id] ~= true
        then
            stored.default = CopyReference(
                FirstEnabledUserReference(
                    provider,
                    catalog,
                    nil,
                    assignmentState
                ) or reference
            )
        end
        stored.enabled = true

        local assignmentSnapshot = BuildEditableAssignmentSnapshot(
            provider,
            catalog,
            stored,
            allSpecKeys,
            assignmentState
        )
        local assignment =
            assignmentSnapshot.byReference["user:" .. reference.id]
        local publicReference = CopyReference(reference)
        local runtimeEnabledAfter, runtimeReferenceAfter =
            GetEditableEffectiveRuntimeAssignment(stored, currentSpecKey)
        local runtimeChanged = EffectiveRuntimeAssignmentChanged(
            runtimeEnabledBefore,
            runtimeReferenceBefore,
            runtimeEnabledAfter,
            runtimeReferenceAfter
        )
        if runtimeChanged then
            Emit(
                "YUI_CONFIG_SET_ASSIGNMENTS_CHANGED",
                providerId,
                publicReference,
                assignment
            )
        end
        Emit("YUI_CONFIG_SETS_CHANGED", providerId, "assignment", {
            reference = publicReference,
            assignment = assignment,
            assignmentSnapshot = assignmentSnapshot,
        })
        return assignment, nil, {
            assignmentSnapshot = assignmentSnapshot,
            runtimeChanged = runtimeChanged,
            currentReference = CopyReference(runtimeReferenceAfter),
        }
    end

    local current
    current, code, detail = ReadAssignments(provider)
    if not current then return nil, code, detail end
    local currentSpecKey = self:GetCurrentSpecializationKey()
    local runtimeEnabledBefore, runtimeReferenceBefore =
        GetEffectiveRuntimeAssignment(provider, current, currentSpecKey)
    local currentAssignment
    currentAssignment, code, detail = self:GetAssignment(providerId, reference)
    if not currentAssignment then return nil, code, detail end
    if mode == "none" and currentAssignment.mode == "none" then
        if current.enabled and not current.default then
            return nil, "default_required"
        end
        return currentAssignment
    end
    if mode ~= "default" and not current.default then
        return nil, "default_required"
    end
    local promotedFallback
    if mode ~= "default" and ReferencesEqual(current.default, reference) then
        local fallback
        if provider.editableUserSets then
            local catalog
            catalog, code, detail = GetCatalog(provider, false)
            if not catalog then return nil, code, detail end
            fallback = FirstStoredUserReference(
                provider,
                catalog,
                reference.id,
                SupportsConfigurationModes(provider) and MODE_SPECIALIZATION or nil
            )
        else
            fallback = IsAssignmentReferenceValid(provider, provider.defaultAssignment)
        end
        if not fallback or ReferencesEqual(fallback, reference) then
            return nil, "default_required"
        end
        promotedFallback = fallback
    end

    local stored
    stored, code, detail = EnsureStoredAssignments(provider)
    if not stored then return nil, code, detail end
    stored.enabled = true
    local removed
    removed, code = RemoveAssignmentReference(stored, reference)
    if removed == nil then return nil, code end
    if promotedFallback then
        local fallbackRemoved
        fallbackRemoved, code = RemoveAssignmentReference(stored, promotedFallback)
        if fallbackRemoved == nil then return nil, code end
    end
    if mode == "default" then
        stored.default = CopyReference(reference)
    elseif mode == "specs" then
        for _, specKey in ipairs(normalizedSpecKeys) do
            stored.bySpec[specKey] = CopyReference(reference)
        end
    end

    local assignment
    assignment, code, detail = self:GetAssignment(providerId, reference)
    if not assignment then return nil, code, detail end
    local publicReference = CopyReference(reference)
    local runtimeEnabledAfter, runtimeReferenceAfter =
        GetEffectiveRuntimeAssignment(provider, stored, currentSpecKey)
    if EffectiveRuntimeAssignmentChanged(
        runtimeEnabledBefore,
        runtimeReferenceBefore,
        runtimeEnabledAfter,
        runtimeReferenceAfter
    ) then
        Emit(
            "YUI_CONFIG_SET_ASSIGNMENTS_CHANGED",
            providerId,
            publicReference,
            assignment
        )
    end
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "assignment", {
        reference = publicReference,
        assignment = assignment,
    })
    return assignment
end

function ConfigSets:SetUserSetEnabled(providerId, setId, enabled)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.editableUserSets then return nil, "not_editable_user_sets" end
    if type(enabled) ~= "boolean" then return nil, "invalid_enabled_state" end
    if self.ProfileOwnership then
        -- Assignment is the only activation policy in the owned library.
        -- Old callers must choose a default/spec assignment explicitly.
        return nil, "assignment_required"
    end

    local ensured, code, detail = EnsureEditableCatalog(provider)
    if not ensured then return nil, code, detail end
    local catalog
    catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local reference, item = StoredUserReference(provider, catalog, setId)
    if not reference then return nil, "set_not_found" end
    if SupportsConfigurationModes(provider)
        and item.configurationMode ~= MODE_SPECIALIZATION then
        return nil, "wrong_configuration_mode"
    end
    local assignmentState
    assignmentState, code, detail = GetReadyEditableAssignmentState(
        provider,
        catalog
    )
    if not assignmentState then return nil, code, detail end
    local enabledSets = assignmentState.enabledUserSets
    local disabledAssignments
    disabledAssignments, code = EnsureDisabledAssignments(
        provider,
        catalog,
        assignmentState
    )
    if not disabledAssignments then return nil, code end
    local current = enabledSets[setId] == true
    if current == enabled then
        return self:GetAssignment(providerId, reference)
    end

    local stored
    stored, code, detail = EnsureStoredAssignments(provider)
    if not stored then return nil, code, detail end
    if enabled then
        local dormantSpecKeys =
            CollectStoredSpecSelection(disabledAssignments[setId])
        enabledSets[setId] = true
        stored.enabled = true
        if #dormantSpecKeys > 0 then
            for _, specKey in ipairs(dormantSpecKeys) do
                stored.bySpec[specKey] = CopyReference(reference)
            end
            local allSpecKeys = CollectSpecializationKeys()
            local selected = MakeStoredSpecSelection(dormantSpecKeys)
            local ownsAll = #allSpecKeys > 0
            for _, specKey in ipairs(allSpecKeys) do
                if selected[specKey] ~= true then
                    ownsAll = false
                    break
                end
            end
            if ownsAll then stored.default = CopyReference(reference) end
        else
            local specKey = self:GetCurrentSpecializationKey()
            if specKey then stored.bySpec[specKey] = CopyReference(reference) end
        end
        disabledAssignments[setId] = nil
        if not stored.default or not enabledSets[stored.default.id] then
            stored.default = CopyReference(reference)
        end
    else
        local fallback = FirstEnabledUserReference(
            provider,
            catalog,
            setId,
            assignmentState
        )
        if not fallback then return nil, "enabled_required" end

        local active = self.activeReferences[providerId]
        if active and ReferencesEqual(active.reference, reference) then
            local applied, applyCode, applyDetail = self:Apply(
                providerId,
                fallback,
                provider,
                { recordUndo = false, reason = "disable-select-next" }
            )
            if not applied then return nil, applyCode, applyDetail end
        end
        local dormantSelection = {}
        for specKey, assigned in pairs(stored.bySpec) do
            if ReferencesEqual(assigned, reference) then
                dormantSelection[specKey] = true
                stored.bySpec[specKey] = CopyReference(fallback)
            end
        end
        disabledAssignments[setId] = dormantSelection
        enabledSets[setId] = nil
        if ReferencesEqual(stored.default, reference) then
            stored.default = CopyReference(fallback)
        end
    end

    local assignment
    assignment, code, detail = self:GetAssignment(providerId, reference)
    if not assignment then return nil, code, detail end
    Emit("YUI_CONFIG_SET_ASSIGNMENTS_CHANGED", providerId, reference, assignment)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, enabled and "enable" or "disable", {
        reference = CopyReference(reference),
        assignment = assignment,
    })
    return assignment
end

function ConfigSets:ResolveAssignment(providerId, specKey)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.specializationAssignments then
        return nil, "specialization_assignments_not_supported"
    end
    local catalog
    if provider.editableUserSets then
        local code, detail
        catalog, code, detail = GetReadyEditableAssignmentCatalog(provider)
        if not catalog then return nil, code, detail end
    end

    local normalizedKey
    if specKey ~= nil then
        normalizedKey = NormalizeSpecKey(specKey)
        if not normalizedKey then return nil, "invalid_specialization" end
    end
    local assignments, code, detail
    if self.ProfileOwnership and provider.editableUserSets then
        -- Routing only needs references. The legacy reader validates and copies
        -- every assigned payload, including repeated references to the same set.
        local stored = catalog.assignments
        if stored.enabled ~= nil and type(stored.enabled) ~= "boolean" then
            return nil, "invalid_storage"
        end
        assignments, code = S.ConfigSetAssignments:Snapshot(catalog)
        if normalizedKey and not CollectSpecializationKeySet()[normalizedKey] then
            normalizedKey = nil
        end
    else
        assignments, code, detail = ReadAssignments(provider)
    end
    if not assignments then return nil, code, detail end
    if normalizedKey and assignments.bySpec[normalizedKey] then
        return CopyReference(assignments.bySpec[normalizedKey]), "spec"
    end
    if assignments.default then
        return CopyReference(assignments.default), "default"
    end
    return nil
end

function ConfigSets:GetActiveReference(providerId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local db, profileName, code = GetProfileIdentity(provider)
    if not db then return nil, code end
    local editableCatalog
    if provider.editableUserSets then
        local readyCode, readyDetail
        editableCatalog, readyCode, readyDetail =
            GetReadyEditableAssignmentCatalog(provider)
        if not editableCatalog then return nil, readyCode, readyDetail end
    end
    local active = self.activeReferences[providerId]
    if SupportsConfigurationModes(provider) then
        local catalog = editableCatalog or GetCatalog(provider, false)
        local mode = type(catalog) == "table"
            and type(catalog.configurationModeByProfile) == "table"
            and NormalizeConfigurationMode(
                provider,
                catalog.configurationModeByProfile[profileName],
                false
            )
            or nil
        local remembered = mode and GetModeActiveReference(
            provider,
            catalog,
            profileName,
            mode
        ) or nil
        if remembered then
            if not (
                active
                and active.database == db
                and active.profileName == profileName
                and ReferencesEqual(active.reference, remembered)
            ) then
                active = {
                    database = db,
                    profileName = profileName,
                    reference = CopyReference(remembered),
                }
                self.activeReferences[providerId] = active
                PersistActiveReference(
                    provider,
                    catalog,
                    profileName,
                    remembered
                )
            end
            return CopyReference(remembered)
        end
    end
    if active and active.database == db and active.profileName == profileName then
        return CopyReference(active.reference)
    end
    if provider.editableUserSets then
        local catalog = editableCatalog
        active = self.activeReferences[providerId]
        if active and active.database == db and active.profileName == profileName then
            return CopyReference(active.reference)
        end
        local persistedId = type(catalog.activeByProfile) == "table"
            and catalog.activeByProfile[profileName]
            or nil
        local persisted = StoredUserReferenceMetadata(
            provider,
            catalog,
            persistedId
        )
        if persisted then
            self.activeReferences[providerId] = {
                database = db,
                profileName = profileName,
                reference = CopyReference(persisted),
            }
            return CopyReference(persisted)
        end
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
        active = self.activeReferences[providerId]
        if active and active.database == db and active.profileName == profileName then
            return CopyReference(active.reference)
        end
    end
    return nil
end

function ConfigSets:GetConfigurationMode(providerId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not SupportsConfigurationModes(provider) then
        return nil, "configuration_modes_not_supported"
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if catalog
        and catalog.configurationModesMigrated == true
        and type(catalog.configurationModeByProfile) == "table"
        and type(catalog.activeByConfigurationMode) == "table" then
        local _, profileName, identityError = GetProfileIdentity(provider)
        if not profileName then return nil, identityError end
        local mode = NormalizeConfigurationMode(
            provider,
            catalog.configurationModeByProfile[profileName],
            false
        )
        local specializationReference = GetModeActiveReference(
            provider,
            catalog,
            profileName,
            MODE_SPECIALIZATION
        )
        local unifiedReference = GetModeActiveReference(
            provider,
            catalog,
            profileName,
            MODE_UNIFIED
        )
        local specializationState = GetProfileSpecializationState(
            provider,
            catalog,
            false,
            profileName
        )
        if mode
            and specializationReference
            and unifiedReference
            and type(specializationState) == "table" then
            return mode
        end
    elseif code then
        return nil, code, detail
    end

    local ensured
    ensured, code, detail = EnsureEditableCatalog(provider)
    if not ensured then return nil, code, detail end
    return ensured.configurationMode
end

function ConfigSets:GetConfigurationModeReference(providerId, mode)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not SupportsConfigurationModes(provider) then
        return nil, "configuration_modes_not_supported"
    end
    mode = NormalizeConfigurationMode(provider, mode, false)
    if not mode then return nil, "invalid_configuration_mode" end
    local readyMode, code, detail = self:GetConfigurationMode(providerId)
    if not readyMode then return nil, code, detail end
    if mode == MODE_SPECIALIZATION then
        return self:ResolveAssignment(
            providerId,
            self:GetCurrentSpecializationKey()
        )
    end
    local catalog
    catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local _, profileName, identityError = GetProfileIdentity(provider)
    if not profileName then return nil, identityError end
    local reference = GetModeActiveReference(
        provider,
        catalog,
        profileName,
        MODE_UNIFIED
    )
    if reference then return CopyReference(reference), "unified" end
    return nil, "set_not_found"
end

function ConfigSets:SetConfigurationMode(providerId, mode, owner)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not SupportsConfigurationModes(provider) then
        return nil, "configuration_modes_not_supported"
    end
    mode = NormalizeConfigurationMode(provider, mode, false)
    if not mode then return nil, "invalid_configuration_mode" end
    if self.busy[providerId] then return nil, "busy" end
    if IsInCombat() then return nil, "combat-lockdown" end

    local previousMode, code, detail = self:GetConfigurationMode(providerId)
    if not previousMode then return nil, code, detail end
    if previousMode == mode then
        local currentReference, referenceCode, referenceDetail =
            self:GetConfigurationModeReference(
            providerId,
            mode
        )
        if not currentReference then
            return nil, referenceCode, referenceDetail
        end
        return {
            providerId = providerId,
            mode = mode,
            previousMode = previousMode,
            reference = CopyReference(currentReference),
            changed = false,
        }
    end

    local reference, source
    reference, source, detail = self:GetConfigurationModeReference(
        providerId,
        mode
    )
    if not reference then return nil, source, detail end
    local applied
    applied, code, detail = self:Apply(providerId, reference, owner or provider, {
        recordUndo = false,
        reason = "configuration-mode",
        configurationMode = mode,
    })
    if not applied then return nil, code, detail end

    local catalog
    catalog, code, detail = GetCatalog(provider, true)
    if not catalog then return nil, code, detail end
    local _, profileName, identityError = GetProfileIdentity(provider)
    if not profileName then return nil, identityError end
    PersistConfigurationMode(provider, catalog, profileName, mode)
    Emit(
        "YUI_CONFIG_SET_MODE_CHANGED",
        providerId,
        mode,
        previousMode
    )
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "configuration-mode", {
        mode = mode,
        previousMode = previousMode,
        reference = CopyReference(reference),
    })
    return {
        providerId = providerId,
        mode = mode,
        previousMode = previousMode,
        reference = CopyReference(reference),
        changed = true,
        applied = applied,
    }
end

function ConfigSets:EnsureEditableUserSet(providerId, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    options = type(options) == "table" and options or nil
    if not (options and options.forceValidate == true) then
        local catalog = ReadReadyEditableAssignmentCatalog(provider)
        if catalog then
            local configurationMode
            local code, detail
            if SupportsConfigurationModes(provider) then
                configurationMode, code, detail = self:GetConfigurationMode(providerId)
                if not configurationMode then return nil, code, detail end
            end
            local reference
            reference, code, detail = self:GetActiveReference(providerId)
            if not reference then return nil, code or "set_not_found", detail end
            return {
                reference = CopyReference(reference),
                configurationMode = configurationMode,
                created = 0,
                createdItems = {},
            }
        end
    end
    return EnsureEditableCatalog(provider)
end

function ConfigSets:SaveActiveUserSet(providerId, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.editableUserSets then return nil, "not_editable_user_sets" end
    if self.busy[providerId] then return nil, "busy" end
    options = type(options) == "table" and options or {}

    local ensured, code, detail = EnsureEditableCatalog(provider)
    if not ensured then return nil, code, detail end
    local reference = ensured.reference
    if not reference or reference.kind ~= "user" then return nil, "set_not_found" end

    local catalog
    catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local item
    item, code, detail = NormalizeStoredItemMetadata(
        provider,
        catalog.items[reference.id],
        reference.id
    )
    if not item then return nil, code or "set_not_found", detail end

    local data
    data, code, detail = Capture(provider, item.scopeIds, BuildContext(provider, "autosave", {
        kind = "user",
        id = reference.id,
        owner = options.owner,
        reason = options.reason,
    }))
    if not data then return nil, code, detail end

    local stored = catalog.items[reference.id]
    stored.data = data
    stored.providerSchemaVersion = provider.schemaVersion
    stored.createdAt = item.createdAt
    stored.updatedAt = CurrentTime()
    item.providerSchemaVersion = provider.schemaVersion
    item.updatedAt = stored.updatedAt

    local public = PublicUser(provider, item)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "autosave", public)
    Emit("YUI_CONFIG_SET_AUTOSAVED", providerId, CopyReference(reference), public)
    return public
end

local function ScopeListContains(scopeIds, targetScopeId)
    for index = 1, #scopeIds do
        if scopeIds[index] == targetScopeId then return true end
    end
    return false
end

local function NormalizePatchPath(provider, item, path)
    if type(path) ~= "table" then
        return nil, "invalid_patch_path"
    end
    local length = #path
    if length < 2 or length > MAX_PATCH_PATH_DEPTH then
        return nil, "invalid_patch_path"
    end
    local count = 0
    local normalized = {}
    for key in pairs(path) do
        if type(key) ~= "number"
            or not IsInteger(key)
            or key < 1
            or key > length
        then
            return nil, "invalid_patch_path"
        end
        count = count + 1
    end
    if count ~= length then return nil, "invalid_patch_path" end

    for index = 1, length do
        local key = path[index]
        local keyType = type(key)
        if keyType == "string" then
            if key == ""
                or #key > MAX_PAYLOAD_STRING_BYTES
                or HasForbiddenControl(key, false)
            then
                return nil, "invalid_patch_path"
            end
        elseif keyType == "number" then
            if not IsInteger(key) then return nil, "invalid_patch_path" end
        else
            return nil, "invalid_patch_path"
        end
        normalized[index] = key
    end

    local scopeId = normalized[1]
    if type(scopeId) ~= "string"
        or not provider.scopes[scopeId]
        or not ScopeListContains(item.scopeIds, scopeId)
    then
        return nil, "invalid_patch_scope", scopeId
    end
    return normalized
end

local function PatchPathsOverlap(left, right)
    local commonLength = math.min(#left, #right)
    for index = 1, commonLength do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function ClonePortableArray(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil, "invalid_patch_path" end
    local length = #value
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number"
            or not IsInteger(key)
            or key < 1
            or key > length
        then
            return nil, "invalid_patch_path"
        end
        count = count + 1
    end
    if count ~= length then return nil, "invalid_patch_path" end
    return ClonePortable(value)
end

function ConfigSets:PatchActiveUserSet(providerId, changes, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if not provider.editableUserSets then return nil, "not_editable_user_sets" end
    if self.busy[providerId] then return nil, "busy" end
    if type(changes) ~= "table" then return nil, "invalid_patch" end
    options = type(options) == "table" and options or {}

    local changeCount = #changes
    if changeCount < 1 or changeCount > MAX_PATCH_CHANGES then
        return nil, "invalid_patch"
    end
    local denseCount = 0
    for key in pairs(changes) do
        if type(key) ~= "number"
            or not IsInteger(key)
            or key < 1
            or key > changeCount
        then
            return nil, "invalid_patch"
        end
        denseCount = denseCount + 1
    end
    if denseCount ~= changeCount then return nil, "invalid_patch" end

    local reference, code, detail = self:GetActiveReference(providerId)
    if not reference then return nil, code or "set_not_found", detail end
    if reference.kind ~= "user" then return nil, "set_not_found" end

    local catalog
    catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local stored = catalog.items[reference.id]
    local item
    item, code, detail = NormalizeStoredItemMetadata(
        provider,
        stored,
        reference.id
    )
    if not item then return nil, code or "set_not_found", detail end
    if item.providerSchemaVersion ~= provider.schemaVersion then
        return nil, "incompatible_schema"
    end

    local prepared = {}
    local normalizedPaths = {}
    for index = 1, changeCount do
        local change = changes[index]
        if type(change) ~= "table" then return nil, "invalid_patch" end
        local path
        path, code, detail = NormalizePatchPath(provider, item, change.path)
        if not path then return nil, code, detail end
        for previousIndex = 1, #normalizedPaths do
            if PatchPathsOverlap(normalizedPaths[previousIndex], path) then
                return nil, "invalid_patch_path", "overlapping_path"
            end
        end
        normalizedPaths[#normalizedPaths + 1] = path

        local parent = stored.data
        for pathIndex = 1, #path - 1 do
            parent = parent[path[pathIndex]]
            if type(parent) ~= "table" then
                return nil, "invalid_patch_path"
            end
        end
        local leafKey = path[#path]
        local remove = change.remove == true
        if change.remove ~= nil and type(change.remove) ~= "boolean" then
            return nil, "invalid_patch"
        end
        local arrayAddValue = change.arrayAddValue
        local arrayRemoveValue = change.arrayRemoveValue
        local arrayOperationCount = (arrayAddValue ~= nil and 1 or 0)
            + (arrayRemoveValue ~= nil and 1 or 0)
        if arrayOperationCount > 1
            or (remove and (change.value ~= nil or arrayOperationCount > 0))
            or (not remove and change.value ~= nil and arrayOperationCount > 0)
            or (not remove and change.value == nil and arrayOperationCount == 0)
        then
            return nil, "invalid_patch"
        end

        local value
        if arrayOperationCount > 0 then
            value, code, detail = ClonePortableArray(parent[leafKey])
            if not value then return nil, code, detail end
            local needle
            local needleSource
            if arrayAddValue ~= nil then
                needleSource = arrayAddValue
            else
                needleSource = arrayRemoveValue
            end
            needle, code, detail = ClonePortable(needleSource)
            if code then return nil, code, detail end
            local matchedIndex
            for valueIndex = 1, #value do
                if PortableValuesEqual(value[valueIndex], needle) then
                    matchedIndex = valueIndex
                    break
                end
            end
            if arrayAddValue ~= nil and not matchedIndex then
                value[#value + 1] = needle
            elseif arrayRemoveValue ~= nil and matchedIndex then
                table.remove(value, matchedIndex)
            end
        elseif not remove then
            value, code, detail = ClonePortable(change.value)
            if code then return nil, code, detail end
        end
        local changed = remove
            and parent[leafKey] ~= nil
            or (not remove and not PortableValuesEqual(parent[leafKey], value))
        if changed then
            prepared[#prepared + 1] = {
                parent = parent,
                key = leafKey,
                remove = remove,
                value = value,
            }
        end
    end

    if #prepared == 0 then
        local public = PublicUser(provider, item)
        public.changed = false
        public.changeCount = 0
        return public
    end

    for index = 1, #prepared do
        local change = prepared[index]
        if change.remove then
            change.parent[change.key] = nil
        else
            change.parent[change.key] = change.value
        end
    end
    stored.updatedAt = CurrentTime()
    item.updatedAt = stored.updatedAt

    local public = PublicUser(provider, item)
    public.changed = true
    public.changeCount = #prepared
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "data-patch", public)
    Emit(
        "YUI_CONFIG_SET_AUTOSAVED",
        providerId,
        CopyReference(reference),
        public
    )
    return public
end

function ConfigSets:GetPickerPreferences(providerId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then
        if code then return nil, code, detail end
        return { hideUnusedBuiltins = false }
    end
    local picker = catalog.picker
    if picker ~= nil and type(picker) ~= "table" then
        return nil, "invalid_storage"
    end
    return {
        hideUnusedBuiltins = picker and picker.hideUnusedBuiltins == true or false,
    }
end

function ConfigSets:SetPickerPreferences(providerId, preferences)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if type(preferences) ~= "table" or type(preferences.hideUnusedBuiltins) ~= "boolean" then
        return nil, "invalid_picker_preferences"
    end
    local catalog, code, detail = GetCatalog(provider, true)
    if not catalog then return nil, code, detail end
    if catalog.picker ~= nil and type(catalog.picker) ~= "table" then
        return nil, "invalid_storage"
    end
    catalog.picker = catalog.picker or {}
    if catalog.picker.hideUnusedBuiltins
        == preferences.hideUnusedBuiltins then
        return {
            hideUnusedBuiltins = catalog.picker.hideUnusedBuiltins,
        }
    end
    catalog.picker.hideUnusedBuiltins = preferences.hideUnusedBuiltins
    local result = {
        hideUnusedBuiltins = catalog.picker.hideUnusedBuiltins,
    }
    Emit("YUI_CONFIG_SET_PICKER_PREFERENCES_CHANGED", providerId, result)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "picker-preferences", result)
    return result
end

function ConfigSets:GetExportPrefix(providerId)
    if not self.providers[providerId] then return nil, "provider_not_found" end
    return self.EXPORT_PREFIX
        .. providerId
        .. ":v"
        .. tostring(self.EXPORT_FORMAT_VERSION)
        .. ":"
end

function ConfigSets:ExportUserSet(providerId, setId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if UsesAllUserSetScopes(provider) then
        local ensured, ensureCode, ensureDetail =
            EnsureEditableCatalogForExport(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end

    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local item
    item, code, detail = PrepareStoredItemForExport(
        provider,
        catalog.items[setId],
        setId,
        "export_user_set",
        { setId = setId }
    )
    if not item then return nil, code or "set_not_found", detail end

    local serializer, deflate
    serializer, deflate, code = GetSerializationLibraries()
    if not serializer then return nil, code end

    local envelope = {
        kind = EXPORT_PAYLOAD_KIND,
        formatVersion = self.EXPORT_FORMAT_VERSION,
        providerId = provider.id,
        providerSchemaVersion = item.providerSchemaVersion,
        set = {
            name = item.name,
            description = item.description,
            scopeIds = CopyArray(item.scopeIds),
            data = item.data,
        },
    }
    local portable
    portable, code, detail = CloneProviderPayload(
        provider,
        envelope,
        64,
        SINGLE_SET_ENVELOPE_DEPTH_ALLOWANCE
    )
    if not portable then return nil, code, detail end

    local ok, serialized = pcall(serializer.Serialize, serializer, portable)
    if not ok or type(serialized) ~= "string" or serialized == "" then
        return nil, "serialization_unavailable"
    end
    local compressed
    ok, compressed = pcall(deflate.CompressDeflate, deflate, serialized)
    if not ok or type(compressed) ~= "string" or compressed == "" then
        return nil, "serialization_unavailable"
    end
    local encoded
    ok, encoded = pcall(deflate.EncodeForPrint, deflate, compressed)
    if not ok or type(encoded) ~= "string" or encoded == "" then
        return nil, "serialization_unavailable"
    end

    local prefix = self:GetExportPrefix(providerId)
    local result = prefix .. encoded
    if #result > MAX_IMPORT_STRING_BYTES then
        return nil, "invalid_payload", "export_too_large"
    end
    return result
end

function ConfigSets:DecodeUserSet(providerId, value)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    value = Trim(value)
    if not value or value == "" or #value > MAX_IMPORT_STRING_BYTES then
        return nil, "invalid_import_string"
    end

    local importedProviderId, formatVersion, encoded = value:match(
        "^!YUI%-SET:([A-Za-z0-9][A-Za-z0-9%._%-]*):v(%d+):(.+)$"
    )
    if not importedProviderId or not encoded or encoded == "" then
        return nil, "invalid_import_string"
    end
    if importedProviderId ~= providerId then
        return nil, "wrong_provider"
    end
    if tonumber(formatVersion) ~= self.EXPORT_FORMAT_VERSION then
        return nil, "unsupported_format"
    end

    local serializer, deflate, code = GetSerializationLibraries()
    if not serializer then return nil, code end

    local ok, compressed = pcall(deflate.DecodeForPrint, deflate, encoded)
    if not ok or type(compressed) ~= "string" or compressed == "" then
        return nil, "decode_failed"
    end
    local serialized
    ok, serialized = pcall(
        deflate.DecompressDeflate,
        deflate,
        compressed,
        MAX_SERIALIZED_IMPORT_BYTES
    )
    if not ok or type(serialized) ~= "string" or serialized == "" then
        return nil, "decode_failed"
    end
    if #serialized > MAX_SERIALIZED_IMPORT_BYTES then
        return nil, "invalid_payload", "import_too_large"
    end
    local deserialized, envelope
    ok, deserialized, envelope = pcall(serializer.Deserialize, serializer, serialized)
    if not ok or deserialized ~= true or type(envelope) ~= "table" then
        return nil, "decode_failed"
    end

    local portable, detail
    portable, code, detail = CloneProviderPayload(
        provider,
        envelope,
        64,
        SINGLE_SET_ENVELOPE_DEPTH_ALLOWANCE
    )
    if not portable then return nil, "invalid_payload", detail end
    if portable.kind ~= EXPORT_PAYLOAD_KIND
        or portable.formatVersion ~= self.EXPORT_FORMAT_VERSION
        or portable.providerId ~= providerId
        or type(portable.set) ~= "table" then
        return nil, "invalid_payload"
    end

    return portable
end

function ConfigSets:ImportUserSet(providerId, value, metadata)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local portable, code, detail = self:DecodeUserSet(providerId, value)
    if not portable then return nil, code, detail end
    metadata = type(metadata) == "table" and metadata or {}
    local configurationMode
    if SupportsConfigurationModes(provider) then
        configurationMode = NormalizeConfigurationMode(
            provider,
            metadata.configurationMode or MODE_SPECIALIZATION,
            false
        )
        if not configurationMode then return nil, "invalid_configuration_mode" end
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end

    local requestedName
    if metadata.name ~= nil then
        requestedName = Trim(metadata.name)
        if requestedName == nil then return nil, "invalid_name" end
    end
    if requestedName == "" then requestedName = nil end
    local name
    name, code, detail = NormalizeName(requestedName or portable.set.name)
    if not name then return nil, code, detail end
    local description
    description, code, detail = NormalizeDescription(portable.set.description)
    if code then return nil, code, detail end
    local scopeIds
    scopeIds, code, detail = NormalizeScopeIds(provider, portable.set.scopeIds, false)
    if not scopeIds then return nil, code, detail end

    local sourceSchemaVersion = tonumber(portable.providerSchemaVersion)
    if not IsInteger(sourceSchemaVersion) or sourceSchemaVersion < 1 then
        return nil, "invalid_payload", "invalid_provider_schema"
    end

    local data
    data, code, detail = CloneProviderPayload(provider, portable.set.data)
    if not data then return nil, code, detail end
    local context = BuildContext(provider, "import", {
        kind = "user",
        sourceSchemaVersion = sourceSchemaVersion,
    })
    local migratedByProvider = false
    if sourceSchemaVersion ~= provider.schemaVersion then
        if type(provider.canMigrate) ~= "function" or type(provider.migrate) ~= "function" then
            return nil, "incompatible_schema"
        end
        local canMigrateOk, canMigrate = pcall(
            provider.canMigrate,
            sourceSchemaVersion,
            provider.schemaVersion
        )
        if not canMigrateOk or canMigrate ~= true then
            return nil, "incompatible_schema"
        end
        local migratedOk, migrated, migrateDetail = SafeCallback(
            provider.migrate,
            data,
            sourceSchemaVersion,
            provider.schemaVersion,
            context
        )
        if not migratedOk then return nil, migrated, migrateDetail end
        data = migrated
        migratedByProvider = true
    end
    data, code, detail = NormalizeProviderData(
        provider,
        data,
        scopeIds,
        context,
        nil,
        migratedByProvider
    )
    if not data then return nil, code, detail end
    if UsesAllUserSetScopes(provider) then
        data, scopeIds, code, detail = MaterializeAllScopeData(
            provider,
            data,
            scopeIds,
            context
        )
        if not data then return nil, code, detail end
    end

    local catalog
    catalog, code, detail = GetCatalog(provider, true)
    if not catalog then return nil, code, detail end
    if CountItems(provider, catalog, configurationMode) >= provider.maxUserSets then
        return nil, "set_limit"
    end
    name, code = MakeUniqueName(provider, catalog, name, configurationMode)
    if not name then return nil, code end

    local id = NextUserId(catalog)
    local now = CurrentTime()
    local item = {
        id = id,
        name = name,
        description = description,
        providerSchemaVersion = provider.schemaVersion,
        scopeIds = CopyArray(scopeIds),
        data = data,
        createdAt = now,
        updatedAt = now,
        configurationMode = configurationMode,
    }
    catalog.items[id] = item
    catalog.order[#catalog.order + 1] = id
    local public = PublicUser(provider, item)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "import", public)
    return public
end

local PROFILE_STATE_SCHEMA_VERSION = 1
local PROFILE_STATE_KIND = "YUI_CONFIG_SETS_PROFILE"

local function IsDenseProfileStateArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if not IsInteger(key) or key < 1 then return false end
        count = count + 1
    end
    return count == #value
end

local function GetProductProfileProviders(productId, providerIds)
    local DB = YUI.DB
    if not (DB and DB.IsReady and DB:IsReady() and DB.GetAceDB) then
        return nil, nil, "db_not_ready"
    end
    local database = DB:GetAceDB(productId)
    if type(database) ~= "table" then return nil, nil, "db_not_ready" end
    local requested
    if providerIds ~= nil then
        if not IsDenseProfileStateArray(providerIds) then return nil, nil, "invalid_provider" end
        requested = {}
        for _, providerId in ipairs(providerIds) do
            if not IsStableId(providerId, MAX_PROVIDER_ID_BYTES) or requested[providerId] then
                return nil, nil, "invalid_provider"
            end
            requested[providerId] = true
        end
    end
    local providers = {}
    for _, provider in pairs(ConfigSets.providers) do
        if (SupportsConfigurationModes(provider) or (ConfigSets.ProfileOwnership and provider.editableUserSets))
            and DB:GetAceDB(provider.productId) == database
            and (not requested or requested[provider.id]) then
            providers[#providers + 1] = provider
            if requested then requested[provider.id] = nil end
        end
    end
    if requested and next(requested) ~= nil then return nil, nil, "provider_not_found" end
    table.sort(providers, function(left, right) return left.id < right.id end)
    return database, providers
end

local function PackageReference(keyBySetId, reference, expectedMode, itemById)
    local normalized = NormalizeReference(reference)
    if not normalized or normalized.kind ~= "user" then return nil end
    local item = itemById[normalized.id]
    if not item or item.configurationMode ~= expectedMode then return nil end
    return keyBySetId[normalized.id]
end

local function CopyStringMap(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        result[key] = value
    end
    return result
end

local function IsDenseArray(value)
    if type(value) ~= "table" then return false end
    local length = #value
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number"
            or not IsInteger(key)
            or key < 1
            or key > length then
            return false
        end
        count = count + 1
    end
    return count == length
end

local function CloneCatalogForProfileImport(catalog)
    local cloned = {}
    for key, value in pairs(catalog) do cloned[key] = value end
    cloned.order = CopyArray(catalog.order)
    cloned.items = CopyStringMap(catalog.items)
    cloned.activeByProfile = CopyStringMap(catalog.activeByProfile)
    cloned.configurationModeByProfile = CopyStringMap(
        catalog.configurationModeByProfile
    )
    cloned.activeByConfigurationMode = {}
    for profileName, byMode in pairs(catalog.activeByConfigurationMode or {}) do
        cloned.activeByConfigurationMode[profileName] = CopyStringMap(byMode)
    end
    cloned.specializationByProfile = CopyStringMap(
        catalog.specializationByProfile
    )
    return cloned
end

local function NormalizeProfileImportedSet(provider, portable, configurationMode, work)
    if type(portable) ~= "table" or not IsStableId(portable.key) then
        return nil, "invalid_payload", "invalid_profile_set"
    end
    local name, code, detail = NormalizeName(portable.name)
    if not name then return nil, code, detail end
    local description
    description, code, detail = NormalizeDescription(portable.description)
    if code then return nil, code, detail end
    local scopeIds
    scopeIds, code, detail = NormalizeScopeIds(provider, portable.scopeIds, false)
    if not scopeIds then return nil, code, detail end
    local sourceSchemaVersion = tonumber(portable.providerSchemaVersion)
    if not IsInteger(sourceSchemaVersion) or sourceSchemaVersion < 1 then
        return nil, "invalid_payload", "invalid_provider_schema"
    end
    local data
    data, code, detail = CloneProviderPayload(provider, portable.data, nil, nil, work)
    if not data then return nil, code, detail end
    local context = BuildContext(provider, "profile_import", {
        kind = "user",
        sourceSchemaVersion = sourceSchemaVersion,
        configurationMode = configurationMode,
    })
    local migratedByProvider = false
    if sourceSchemaVersion ~= provider.schemaVersion then
        if type(provider.canMigrate) ~= "function"
            or type(provider.migrate) ~= "function" then
            return nil, "incompatible_schema"
        end
        local ok, canMigrate = pcall(
            provider.canMigrate,
            sourceSchemaVersion,
            provider.schemaVersion
        )
        if not ok or canMigrate ~= true then return nil, "incompatible_schema" end
        local migratedOk, migrated, migrateDetail = SafeCallback(
            provider.migrate,
            data,
            sourceSchemaVersion,
            provider.schemaVersion,
            context
        )
        if not migratedOk then return nil, migrated, migrateDetail end
        data = migrated
        migratedByProvider = true
    end
    data, code, detail = NormalizeProviderData(
        provider,
        data,
        scopeIds,
        context,
        work,
        migratedByProvider
    )
    if not data then return nil, code, detail end
    if UsesAllUserSetScopes(provider) then
        data, scopeIds, code, detail = MaterializeAllScopeData(
            provider,
            data,
            scopeIds,
            context,
            work
        )
        if not data then return nil, code, detail end
    end
    return {
        key = portable.key,
        name = name,
        description = description,
        providerSchemaVersion = provider.schemaVersion,
        scopeIds = CopyArray(scopeIds),
        data = data,
        configurationMode = configurationMode,
    }
end

function ConfigSets:ExportProfileState(productId, profileName, providerIds)
    if self.ProfileOwnership then
        return self.ProfileOwnership:ExportProfileState(productId, profileName, providerIds)
    end
    local database, providers, code = GetProductProfileProviders(productId, providerIds)
    if not database then return nil, code end
    local currentProfile = type(database.GetCurrentProfile) == "function"
        and database:GetCurrentProfile() or nil
    profileName = profileName or currentProfile
    if profileName ~= currentProfile then return nil, "profile_not_active" end

    local result = {
        kind = PROFILE_STATE_KIND,
        schema = PROFILE_STATE_SCHEMA_VERSION,
        providers = {},
    }
    for _, provider in ipairs(providers) do
        local ensured, ensureCode, ensureDetail =
            EnsureEditableCatalogForExport(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
        local catalog
        catalog, ensureCode, ensureDetail = GetCatalog(provider, false)
        if not catalog then return nil, ensureCode, ensureDetail end
        local specializationState
        specializationState, ensureCode, ensureDetail =
            GetProfileSpecializationState(provider, catalog, false, profileName)
        if not specializationState then
            return nil, ensureCode or "invalid_storage", ensureDetail
        end
        local mode = NormalizeConfigurationMode(
            provider,
            catalog.configurationModeByProfile[profileName],
            false
        )
        if not mode then return nil, "invalid_storage" end
        local unifiedReference = GetModeActiveReference(
            provider,
            catalog,
            profileName,
            MODE_UNIFIED
        )
        local specializationReference = GetModeActiveReference(
            provider,
            catalog,
            profileName,
            MODE_SPECIALIZATION
        )
        if not unifiedReference or not specializationReference then
            return nil, "set_not_found"
        end

        local required = {
            [unifiedReference.id] = true,
            [specializationReference.id] = true,
        }
        for setId, enabled in pairs(specializationState.enabledUserSets or {}) do
            if enabled == true then required[setId] = true end
        end
        local assignments = specializationState.assignments
        if type(assignments) ~= "table" or type(assignments.bySpec) ~= "table" then
            return nil, "invalid_storage"
        end
        if type(assignments.default) == "table" then
            required[assignments.default.id] = true
        end
        for _, reference in pairs(assignments.bySpec) do
            if type(reference) == "table" then required[reference.id] = true end
        end

        local keyBySetId = {}
        local itemById = {}
        local sets = {}
        for _, setId in ipairs(catalog.order) do
            if required[setId] then
                local item
                item, ensureCode, ensureDetail = PrepareStoredItemForExport(
                    provider,
                    catalog.items[setId],
                    setId,
                    "export_profile_state",
                    {
                        profileName = profileName,
                        setId = setId,
                    }
                )
                if not item then return nil, ensureCode, ensureDetail end
                local key = "s" .. tostring(#sets + 1)
                keyBySetId[setId] = key
                itemById[setId] = item
                sets[#sets + 1] = {
                    key = key,
                    name = item.name,
                    description = item.description,
                    providerSchemaVersion = item.providerSchemaVersion,
                    scopeIds = CopyArray(item.scopeIds),
                    data = item.data,
                    configurationMode = item.configurationMode,
                }
            end
        end
        for setId in pairs(required) do
            if not keyBySetId[setId] then return nil, "set_not_found" end
        end

        local enabledKeys = {}
        for _, setId in ipairs(catalog.order) do
            if specializationState.enabledUserSets[setId] == true then
                enabledKeys[#enabledKeys + 1] = keyBySetId[setId]
            end
        end
        local bySpec = {}
        for specKey, reference in pairs(assignments.bySpec) do
            local key = PackageReference(
                keyBySetId,
                reference,
                MODE_SPECIALIZATION,
                itemById
            )
            if not key then return nil, "invalid_storage" end
            bySpec[specKey] = key
        end
        local defaultKey = PackageReference(
            keyBySetId,
            assignments.default,
            MODE_SPECIALIZATION,
            itemById
        )
        if not defaultKey then return nil, "invalid_storage" end
        result.providers[provider.id] = {
            mode = mode,
            sets = sets,
            unified = PackageReference(
                keyBySetId,
                unifiedReference,
                MODE_UNIFIED,
                itemById
            ),
            specialization = {
                active = PackageReference(
                    keyBySetId,
                    specializationReference,
                    MODE_SPECIALIZATION,
                    itemById
                ),
                enabled = enabledKeys,
                assignments = {
                    enabled = assignments.enabled == true,
                    default = defaultKey,
                    bySpec = bySpec,
                },
            },
        }
    end
    return result
end

function ConfigSets:PrepareProfileStateImport(
    productId,
    targetProfileName,
    payload,
    providerIds,
    work
)
    if type(targetProfileName) ~= "string" or targetProfileName == "" then
        return nil, "profile_unavailable"
    end
    local cloneState = {
        seen = {},
        nodes = 0,
        maxNodes = MAX_PROFILE_STATE_NODES,
        maxDepth = MAX_PROFILE_STATE_DEPTH,
    }
    if type(work) == "table" and type(work.checkpoint) == "function" then
        cloneState.yieldIfNeeded = function(current)
            local ratio = math.min(
                (current.nodes or 0) / math.max(MAX_PROFILE_STATE_NODES, 1),
                0.99
            )
            work.checkpoint(
                "prepare-config-sets",
                0.72 + (0.06 * ratio),
                { processedNodes = current.nodes }
            )
        end
    end
    local portable, code, detail = ClonePortable(payload, cloneState)
    if not portable then return nil, code, detail end
    if self.ProfileOwnership then
        return self.ProfileOwnership:PrepareProfileStateImport(productId, targetProfileName, portable, providerIds, work)
    end
    if portable.kind ~= PROFILE_STATE_KIND
        or portable.schema ~= PROFILE_STATE_SCHEMA_VERSION
        or type(portable.providers) ~= "table" then
        return nil, "invalid_payload"
    end
    local database, providers, providerCode = GetProductProfileProviders(productId, providerIds)
    if not database then return nil, providerCode end
    local providerById = {}
    for _, provider in ipairs(providers) do providerById[provider.id] = provider end
    for providerId in pairs(portable.providers) do
        if not providerById[providerId] then
            return nil, "provider_not_found", providerId
        end
    end

    local prepared = {
        kind = PROFILE_STATE_KIND,
        database = database,
        targetProfileName = targetProfileName,
        entries = {},
    }
    local providerCount = 0
    for _ in pairs(portable.providers) do providerCount = providerCount + 1 end
    local providerIndex = 0
    for providerId, providerPayload in pairs(portable.providers) do
        providerIndex = providerIndex + 1
        if type(work) == "table" and type(work.checkpoint) == "function" then
            work.checkpoint(
                "prepare-config-sets",
                0.78 + (0.18 * ((providerIndex - 1) / math.max(providerCount, 1)))
            )
        end
        local provider = providerById[providerId]
        if type(providerPayload) ~= "table"
            or not IsDenseArray(providerPayload.sets)
            or #providerPayload.sets < 2
            or type(providerPayload.specialization) ~= "table" then
            return nil, "invalid_payload", providerId
        end
        local mode = NormalizeConfigurationMode(
            provider,
            providerPayload.mode,
            false
        )
        if not mode then return nil, "invalid_configuration_mode", providerId end
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
        local catalog
        catalog, ensureCode, ensureDetail = GetCatalog(provider, false)
        if not catalog then return nil, ensureCode, ensureDetail end
        local stagedCatalog = CloneCatalogForProfileImport(catalog)
        local referenceByKey = {}
        local modeByKey = {}
        local seenKeys = {}
        local setCount = #providerPayload.sets
        for setIndex, rawSet in ipairs(providerPayload.sets) do
            if type(work) == "table" and type(work.checkpoint) == "function" then
                work.checkpoint(
                    "prepare-config-sets",
                    0.78 + (0.18 * (
                        ((providerIndex - 1) + ((setIndex - 1) / math.max(setCount, 1)))
                        / math.max(providerCount, 1)
                    ))
                )
            end
            if type(rawSet) ~= "table"
                or not IsStableId(rawSet.key)
                or seenKeys[rawSet.key] then
                return nil, "invalid_payload", "duplicate_profile_set"
            end
            seenKeys[rawSet.key] = true
            local setMode = NormalizeConfigurationMode(
                provider,
                rawSet.configurationMode,
                false
            )
            if not setMode then return nil, "invalid_configuration_mode" end
            if CountItems(provider, stagedCatalog, setMode) >= provider.maxUserSets then
                return nil, "set_limit", providerId
            end
            local normalized
            normalized, ensureCode, ensureDetail = NormalizeProfileImportedSet(
                provider,
                rawSet,
                setMode,
                work
            )
            if not normalized then return nil, ensureCode, ensureDetail end
            local uniqueName
            uniqueName, ensureCode = MakeUniqueName(
                provider,
                stagedCatalog,
                normalized.name,
                setMode
            )
            if not uniqueName then return nil, ensureCode end
            local id = NextUserId(stagedCatalog)
            local now = CurrentTime()
            stagedCatalog.items[id] = {
                id = id,
                name = uniqueName,
                description = normalized.description,
                providerSchemaVersion = provider.schemaVersion,
                scopeIds = normalized.scopeIds,
                data = normalized.data,
                createdAt = now,
                updatedAt = now,
                configurationMode = setMode,
            }
            stagedCatalog.order[#stagedCatalog.order + 1] = id
            referenceByKey[normalized.key] = { kind = "user", id = id }
            modeByKey[normalized.key] = setMode
        end
        local function ResolveKey(key, expectedMode)
            local reference = type(key) == "string" and referenceByKey[key] or nil
            if not reference or modeByKey[key] ~= expectedMode then return nil end
            return CopyReference(reference)
        end
        local unifiedReference = ResolveKey(
            providerPayload.unified,
            MODE_UNIFIED
        )
        local specializationPayload = providerPayload.specialization
        local specializationReference = ResolveKey(
            specializationPayload.active,
            MODE_SPECIALIZATION
        )
        local assignmentPayload = specializationPayload.assignments
        if not unifiedReference
            or not specializationReference
            or not IsDenseArray(specializationPayload.enabled)
            or #specializationPayload.enabled < 1
            or type(assignmentPayload) ~= "table"
            or type(assignmentPayload.enabled) ~= "boolean"
            or type(assignmentPayload.bySpec) ~= "table" then
            return nil, "invalid_payload", providerId
        end
        local enabledUserSets = {}
        for _, key in ipairs(specializationPayload.enabled) do
            local reference = ResolveKey(key, MODE_SPECIALIZATION)
            if not reference then return nil, "invalid_payload", providerId end
            enabledUserSets[reference.id] = true
        end
        local defaultReference = ResolveKey(
            assignmentPayload.default,
            MODE_SPECIALIZATION
        )
        if not defaultReference or enabledUserSets[defaultReference.id] ~= true then
            return nil, "invalid_payload", providerId
        end
        local bySpec = {}
        for rawSpecKey, key in pairs(assignmentPayload.bySpec) do
            local specKey = NormalizeSpecKey(rawSpecKey)
            local reference = ResolveKey(key, MODE_SPECIALIZATION)
            if not specKey
                or CollectSpecializationKeySet()[specKey] ~= true
                or not reference
                or enabledUserSets[reference.id] ~= true then
                return nil, "invalid_payload", providerId
            end
            bySpec[specKey] = reference
        end
        stagedCatalog.specializationByProfile[targetProfileName] = {
            assignments = {
                enabled = assignmentPayload.enabled,
                default = defaultReference,
                bySpec = bySpec,
            },
            enabledUserSets = enabledUserSets,
            disabledAssignments = {},
        }
        stagedCatalog.specializationProfileStateVersion =
            SPECIALIZATION_PROFILE_STATE_VERSION
        stagedCatalog.configurationModeByProfile[targetProfileName] = mode
        stagedCatalog.activeByConfigurationMode[targetProfileName] = {
            [MODE_UNIFIED] = unifiedReference.id,
            [MODE_SPECIALIZATION] = specializationReference.id,
        }
        stagedCatalog.activeByProfile[targetProfileName] =
            mode == MODE_UNIFIED
            and unifiedReference.id
            or specializationReference.id
        local store
        store, ensureCode, ensureDetail = GetStore(provider, true)
        if not store then return nil, ensureCode, ensureDetail end
        prepared.entries[#prepared.entries + 1] = {
            providerId = providerId,
            store = store,
            catalog = stagedCatalog,
            previousCatalog = store.providers[providerId],
            hadPreviousCatalog = store.providers[providerId] ~= nil,
        }
    end
    table.sort(prepared.entries, function(left, right)
        return left.providerId < right.providerId
    end)
    return prepared
end

function ConfigSets:CommitProfileStateImport(prepared)
    if self.ProfileOwnership then return self.ProfileOwnership:CommitProfileStateImport(prepared) end
    if type(prepared) ~= "table"
        or prepared.kind ~= PROFILE_STATE_KIND
        or prepared.committed == true
        or prepared.restored == true
        or type(prepared.entries) ~= "table" then
        return nil, "invalid_payload"
    end
    for _, entry in ipairs(prepared.entries) do
        if type(entry.store) ~= "table"
            or type(entry.store.providers) ~= "table"
            or type(entry.providerId) ~= "string"
            or type(entry.catalog) ~= "table" then
            return nil, "invalid_payload"
        end
    end
    for _, entry in ipairs(prepared.entries) do
        entry.store.providers[entry.providerId] = entry.catalog
        self.activeReferences[entry.providerId] = nil
        self.transactions[entry.providerId] = nil
    end
    prepared.committed = true
    return true
end

function ConfigSets:ValidateProfileStateImport(prepared)
    if self.ProfileOwnership then return self.ProfileOwnership:ValidateProfileStateImport(prepared) end
    return type(prepared) == "table" and prepared.committed ~= true and prepared.restored ~= true
end

function ConfigSets:RestoreProfileStateImport(prepared)
    if self.ProfileOwnership then return self.ProfileOwnership:RestoreProfileStateImport(prepared) end
    if type(prepared) ~= "table"
        or prepared.kind ~= PROFILE_STATE_KIND
        or prepared.committed ~= true
        or prepared.restored == true
        or type(prepared.entries) ~= "table" then
        return nil, "invalid_payload"
    end
    for _, entry in ipairs(prepared.entries) do
        if type(entry.store) ~= "table"
            or type(entry.store.providers) ~= "table"
            or type(entry.providerId) ~= "string" then
            return nil, "invalid_payload"
        end
    end
    for _, entry in ipairs(prepared.entries) do
        if entry.hadPreviousCatalog then
            entry.store.providers[entry.providerId] = entry.previousCatalog
        else
            entry.store.providers[entry.providerId] = nil
        end
        self.activeReferences[entry.providerId] = nil
        self.transactions[entry.providerId] = nil
    end
    prepared.restored = true
    return true
end

function ConfigSets:CopyProfileState(productId, sourceProfileName, targetProfileName)
    if self.ProfileOwnership then return self.ProfileOwnership:CopyProfileState(productId, sourceProfileName, targetProfileName) end
    if type(sourceProfileName) ~= "string" or sourceProfileName == ""
        or type(targetProfileName) ~= "string" or targetProfileName == "" then
        return nil, "profile_unavailable"
    end
    local _, providers, code = GetProductProfileProviders(productId)
    if not providers then return nil, code end
    local prepared = {}
    for _, provider in ipairs(providers) do
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
        local catalog
        catalog, ensureCode, ensureDetail = GetCatalog(provider, false)
        if not catalog then return nil, ensureCode, ensureDetail end
        local sourceState
        sourceState, ensureCode, ensureDetail = GetProfileSpecializationState(
            provider,
            catalog,
            false,
            sourceProfileName
        )
        if not sourceState then return nil, ensureCode or "profile_unavailable", ensureDetail end
        local cloned
        cloned, ensureCode, ensureDetail = CloneSpecializationState(sourceState)
        if not cloned then return nil, ensureCode, ensureDetail end
        local sourceMode = NormalizeConfigurationMode(
            provider,
            catalog.configurationModeByProfile[sourceProfileName],
            false
        )
        local sourceByMode = catalog.activeByConfigurationMode[sourceProfileName]
        if not sourceMode
            or type(sourceByMode) ~= "table"
            or not GetModeActiveReference(
                provider,
                catalog,
                sourceProfileName,
                MODE_UNIFIED
            )
            or not GetModeActiveReference(
                provider,
                catalog,
                sourceProfileName,
                MODE_SPECIALIZATION
            ) then
            return nil, "invalid_storage"
        end
        prepared[#prepared + 1] = {
            catalog = catalog,
            providerId = provider.id,
            state = cloned,
            mode = sourceMode,
            byMode = CopyStringMap(sourceByMode),
            activeId = type(catalog.activeByProfile) == "table"
                and catalog.activeByProfile[sourceProfileName]
                or nil,
        }
    end
    for _, entry in ipairs(prepared) do
        local catalog = entry.catalog
        catalog.specializationByProfile[targetProfileName] = entry.state
        catalog.configurationModeByProfile[targetProfileName] = entry.mode
        catalog.activeByConfigurationMode[targetProfileName] = entry.byMode
        catalog.activeByProfile = catalog.activeByProfile or {}
        catalog.activeByProfile[targetProfileName] = entry.activeId
    end
    return true
end

function ConfigSets:DeleteProfileState(productId, profileName)
    if self.ProfileOwnership then return self.ProfileOwnership:DeleteProfileState(productId, profileName) end
    if type(profileName) ~= "string" or profileName == "" then
        return nil, "profile_unavailable"
    end
    local _, providers, code = GetProductProfileProviders(productId)
    if not providers then return nil, code end
    for _, provider in ipairs(providers) do
        local catalog = GetCatalog(provider, false)
        if catalog then
            if type(catalog.specializationByProfile) == "table" then
                catalog.specializationByProfile[profileName] = nil
            end
            if type(catalog.configurationModeByProfile) == "table" then
                catalog.configurationModeByProfile[profileName] = nil
            end
            if type(catalog.activeByConfigurationMode) == "table" then
                catalog.activeByConfigurationMode[profileName] = nil
            end
            if type(catalog.activeByProfile) == "table" then
                catalog.activeByProfile[profileName] = nil
            end
            local active = self.activeReferences[provider.id]
            if active and active.profileName == profileName then
                self.activeReferences[provider.id] = nil
            end
        end
    end
    return true
end

function ConfigSets:ResetProfileState(productId, profileName)
    local ok, code, detail = self:DeleteProfileState(productId, profileName)
    if not ok then return nil, code, detail end
    local database, providers, providerCode = GetProductProfileProviders(productId)
    if not database then return nil, providerCode end
    local currentProfile = type(database.GetCurrentProfile) == "function"
        and database:GetCurrentProfile() or nil
    if currentProfile == profileName then
        for _, provider in ipairs(providers) do
            local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
            if not ensured then return nil, ensureCode, ensureDetail end
        end
    end
    return true
end

local ResolveApplyData

function ConfigSets:CreateUserSet(providerId, metadata)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    metadata = type(metadata) == "table" and metadata or {}
    local scopeRequestOk, scopeRequestCode, scopeRequestDetail =
        ValidateAllScopeRequest(provider, metadata.scopeIds)
    if not scopeRequestOk then
        return nil, scopeRequestCode, scopeRequestDetail
    end
    local configurationMode
    if SupportsConfigurationModes(provider) then
        configurationMode = NormalizeConfigurationMode(
            provider,
            metadata.configurationMode or MODE_SPECIALIZATION,
            false
        )
        if not configurationMode then return nil, "invalid_configuration_mode" end
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end

    local name, code, detail = NormalizeName(metadata.name)
    if not name then return nil, code, detail end
    local description
    description, code, detail = NormalizeDescription(metadata.description)
    if code then return nil, code, detail end

    local scopeIds
    local data
    local sourceReference = metadata.source and NormalizeReference(metadata.source) or nil
    if metadata.source ~= nil and not sourceReference then
        return nil, "set_not_found"
    end
    if provider.editableUserSets then
        if not sourceReference then return nil, "source_required" end
        if sourceReference.kind ~= "builtin" then return nil, "invalid_source" end
    end
    if sourceReference then
        local context = BuildContext(provider, "copy", {
            kind = "user",
            owner = metadata.owner,
            source = sourceReference,
        })
        local sourceScopeIds
        local sourceItem
        data, sourceScopeIds, sourceItem, code, detail = ResolveApplyData(
            provider,
            sourceReference,
            context
        )
        if not data then return nil, code, detail end
        if UsesAllUserSetScopes(provider) then
            data, scopeIds, code, detail = MaterializeAllScopeData(
                provider,
                data,
                sourceScopeIds,
                context
            )
            if not data then return nil, code, detail end
        elseif metadata.scopeIds ~= nil then
            scopeIds, code, detail = NormalizeScopeIds(provider, metadata.scopeIds, false)
            if not scopeIds then return nil, code, detail end
            local available = {}
            for _, scopeId in ipairs(sourceScopeIds) do available[scopeId] = true end
            local selectedData = {}
            for _, scopeId in ipairs(scopeIds) do
                if not available[scopeId] then
                    return nil, "invalid_scope", scopeId
                end
                selectedData[scopeId] = data[scopeId]
            end
            data, code, detail = NormalizeProviderData(
                provider,
                selectedData,
                scopeIds,
                context,
                nil,
                true
            )
            if not data then return nil, code, detail end
        else
            scopeIds = sourceScopeIds
        end
    else
        scopeIds, code, detail = NormalizeScopeIds(provider, metadata.scopeIds, true)
        if not scopeIds then return nil, code, detail end
    end

    local catalog
    catalog, code, detail = GetCatalog(provider, true)
    if not catalog then return nil, code, detail end
    if CountItems(provider, catalog, configurationMode) >= provider.maxUserSets then
        return nil, "set_limit"
    end
    if NameExists(provider, catalog, name, nil, configurationMode) then
        return nil, "duplicate_name"
    end

    if not data then
        local context = BuildContext(provider, "capture", {
            kind = "user",
            owner = metadata.owner,
        })
        data, code, detail = Capture(provider, scopeIds, context)
        if not data then return nil, code, detail end
    end

    local id = NextUserId(catalog)
    local now = CurrentTime()
    local item = {
        id = id,
        name = name,
        description = description,
        providerSchemaVersion = provider.schemaVersion,
        scopeIds = CopyArray(scopeIds),
        data = data,
        createdAt = now,
        updatedAt = now,
        configurationMode = configurationMode,
    }
    catalog.items[id] = item
    catalog.order[#catalog.order + 1] = id
    local public = PublicUser(provider, item)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, sourceReference and "copy" or "create", public)
    return public
end

function ConfigSets:UpdateUserSet(providerId, setId, metadata, recapture)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    metadata = type(metadata) == "table" and metadata or {}
    local scopeRequestOk, scopeRequestCode, scopeRequestDetail =
        ValidateAllScopeRequest(provider, metadata.scopeIds)
    if not scopeRequestOk then
        return nil, scopeRequestCode, scopeRequestDetail
    end
    if UsesAllUserSetScopes(provider) then
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local item
    item, code, detail = NormalizeStoredItem(provider, catalog.items[setId], setId)
    if not item then return nil, code or "set_not_found", detail end

    local name = item.name
    if metadata.name ~= nil then
        name, code, detail = NormalizeName(metadata.name)
        if not name then return nil, code, detail end
    end
    if NameExists(
        provider,
        catalog,
        name,
        setId,
        item.configurationMode
    ) then
        return nil, "duplicate_name"
    end

    local description = item.description
    if metadata.description ~= nil then
        description, code, detail = NormalizeDescription(metadata.description)
        if code then return nil, code, detail end
    end

    local scopeIds = item.scopeIds
    if metadata.scopeIds ~= nil then
        scopeIds, code, detail = NormalizeScopeIds(provider, metadata.scopeIds, false)
        if not scopeIds then return nil, code, detail end
    end

    local data = item.data
    local shouldCapture = recapture ~= false
    if not shouldCapture and not ArraysEqual(scopeIds, item.scopeIds) then
        return nil, "recapture_required"
    end
    if shouldCapture then
        local context = BuildContext(provider, "capture", {
            kind = "user",
            id = setId,
            owner = metadata.owner,
        })
        data, code, detail = Capture(provider, scopeIds, context)
        if not data then return nil, code, detail end
    end

    local stored = catalog.items[setId]
    stored.name = name
    stored.description = description
    stored.scopeIds = CopyArray(scopeIds)
    stored.data = data
    stored.providerSchemaVersion = provider.schemaVersion
    stored.createdAt = item.createdAt
    stored.updatedAt = CurrentTime()
    local normalized, normalizeCode, normalizeDetail = NormalizeStoredItem(provider, stored, setId)
    if not normalized then return nil, normalizeCode, normalizeDetail end
    local public = PublicUser(provider, normalized)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "update", public)
    return public
end

function ConfigSets:DuplicateUserSet(providerId, setId, newName, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if UsesAllUserSetScopes(provider) then
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local source
    source, code, detail = NormalizeStoredItem(provider, catalog.items[setId], setId)
    if not source then return nil, code or "set_not_found", detail end
    options = type(options) == "table" and options or {}
    local configurationMode = source.configurationMode
    if SupportsConfigurationModes(provider) and options.configurationMode ~= nil then
        configurationMode = NormalizeConfigurationMode(
            provider,
            options.configurationMode,
            false
        )
        if not configurationMode then return nil, "invalid_configuration_mode" end
    end
    if CountItems(provider, catalog, configurationMode) >= provider.maxUserSets then
        return nil, "set_limit"
    end
    local name
    name, code, detail = NormalizeName(newName)
    if not name then return nil, code, detail end
    if NameExists(provider, catalog, name, nil, configurationMode) then
        return nil, "duplicate_name"
    end

    local duplicatedData
    duplicatedData, code, detail = CloneProviderStoredPayload(provider, source.data)
    if not duplicatedData then return nil, code, detail end

    local id = NextUserId(catalog)
    local now = CurrentTime()
    local item = {
        id = id,
        name = name,
        description = source.description,
        providerSchemaVersion = source.providerSchemaVersion,
        scopeIds = CopyArray(source.scopeIds),
        data = duplicatedData,
        createdAt = now,
        updatedAt = now,
        configurationMode = configurationMode,
    }
    catalog.items[id] = item
    catalog.order[#catalog.order + 1] = id
    local public = PublicUser(provider, item)
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "duplicate", public)
    return public
end

function ConfigSets:DeleteUserSet(providerId, setId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if provider.editableUserSets then
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local deletingItem
    deletingItem, code, detail = NormalizeStoredItem(
        provider,
        catalog.items[setId],
        setId
    )
    if not deletingItem then return nil, code or "set_not_found", detail end
    local deletingMode = deletingItem.configurationMode
    local reference = { kind = "user", id = setId }
    local replacementReference
    local replacementItem
    local replacementCreated = false
    if provider.editableUserSets then
        replacementReference = FirstStoredUserReference(
            provider,
            catalog,
            setId,
            deletingMode
        )
        if self.ProfileOwnership and catalog.assignments
            and catalog.assignments.default.id ~= setId then
            replacementReference = CopyReference(catalog.assignments.default)
        end
        if not replacementReference then
            local builtinId = provider.defaultAssignment and provider.defaultAssignment.id
                or provider.builtinOrder[1]
            replacementReference, replacementItem, detail = CreateUserFromBuiltin(
                provider,
                catalog,
                builtinId,
                deletingMode
            )
            if not replacementReference then return nil, replacementItem, detail end
            replacementCreated = true
        end
    end
    local assignments
    local promotedFallback
    local currentAssignmentState = catalog
    if provider.editableUserSets and SupportsConfigurationModes(provider) then
        currentAssignmentState, code, detail = GetReadyEditableAssignmentState(
            provider,
            catalog
        )
        if not currentAssignmentState then return nil, code, detail end
    end
    if currentAssignmentState.assignments ~= nil
        and (not SupportsConfigurationModes(provider)
            or deletingMode == MODE_SPECIALIZATION) then
        assignments, code, detail = ReadAssignments(provider)
        if not assignments then return nil, code, detail end
        if ReferencesEqual(assignments.default, reference) then
            local fallback = replacementReference
                or IsAssignmentReferenceValid(provider, provider.defaultAssignment)
            if assignments.enabled and (
                not fallback or ReferencesEqual(fallback, reference)
            ) then
                return nil, "default_required"
            end
            if fallback and not ReferencesEqual(fallback, reference) then
                promotedFallback = fallback
            end
        end
    end
    local active = self.activeReferences[providerId]
    local replaceActive = active and ReferencesEqual(active.reference, reference)
    if replaceActive and replacementReference then
        local applied, applyCode, applyDetail = self:Apply(
            providerId,
            replacementReference,
            provider,
            {
                recordUndo = false,
                reason = replacementCreated and "delete-create-default" or "delete-select-next",
            }
        )
        if not applied then
            if replacementCreated then
                catalog.items[replacementReference.id] = nil
                RemoveOrderId(catalog.order, replacementReference.id)
            end
            return nil, applyCode, applyDetail
        end
    end
    local assignmentsChanged = false
    local assignmentStates = { catalog }
    if SupportsConfigurationModes(provider) then
        assignmentStates = {}
        for _, state in pairs(catalog.specializationByProfile or {}) do
            if type(state) ~= "table" then return nil, "invalid_storage" end
            assignmentStates[#assignmentStates + 1] = state
        end
    end
    if not SupportsConfigurationModes(provider)
        or deletingMode == MODE_SPECIALIZATION then
        for _, assignmentState in ipairs(assignmentStates) do
            local storedAssignments = assignmentState.assignments
            if type(storedAssignments) == "table" then
                local changed
                if provider.editableUserSets and replacementReference then
                    changed = ReplaceStoredReference(
                        storedAssignments,
                        reference,
                        replacementReference
                    )
                else
                    changed, code = RemoveAssignmentReference(
                        storedAssignments,
                        reference
                    )
                    if changed == nil then return nil, code end
                    if promotedFallback then
                        local fallbackChanged
                        fallbackChanged, code = RemoveAssignmentReference(
                            storedAssignments,
                            promotedFallback
                        )
                        if fallbackChanged == nil then return nil, code end
                        changed = changed or fallbackChanged
                    end
                end
                assignmentsChanged = assignmentsChanged or changed
            end
        end
    end
    if provider.editableUserSets and (
        not SupportsConfigurationModes(provider)
        or deletingMode == MODE_SPECIALIZATION
    ) then
        for _, assignmentState in ipairs(assignmentStates) do
            if type(assignmentState.enabledUserSets) == "table" then
                local wasEnabled = assignmentState.enabledUserSets[setId] == true
                assignmentState.enabledUserSets[setId] = nil
                if wasEnabled and replacementReference then
                    assignmentState.enabledUserSets[replacementReference.id] = true
                end
            end
            if type(assignmentState.disabledAssignments) == "table" then
                assignmentState.disabledAssignments[setId] = nil
            end
        end
    end
    catalog.items[setId] = nil
    RemoveOrderId(catalog.order, setId)
    if replacementCreated and replacementItem then
        local builtinId = provider.defaultAssignment and provider.defaultAssignment.id
            or provider.builtinOrder[1]
        local builtin = provider.builtins[builtinId]
        local preferredName = builtin and PublicBuiltin(provider, builtin).name
        if preferredName and not NameExists(
            provider,
            catalog,
            preferredName,
            replacementReference.id,
            deletingMode
        ) then
            catalog.items[replacementReference.id].name = preferredName
            replacementItem.name = preferredName
        end
    end

    if provider.editableUserSets and type(catalog.activeByProfile) == "table" then
        for profileName, activeSetId in pairs(catalog.activeByProfile) do
            if activeSetId == setId then
                catalog.activeByProfile[profileName] = replacementReference.id
            end
        end
    end
    if SupportsConfigurationModes(provider)
        and type(catalog.activeByConfigurationMode) == "table" then
        for _, byMode in pairs(catalog.activeByConfigurationMode) do
            if type(byMode) == "table" and byMode[deletingMode] == setId then
                byMode[deletingMode] = replacementReference.id
            end
        end
    end

    if replaceActive and not replacementReference then
        self.activeReferences[providerId] = nil
        Emit("YUI_CONFIG_SET_ACTIVE_CHANGED", providerId, nil, "delete")
    end
    local transaction = self.transactions[providerId]
    if transaction and ReferencesEqual(transaction.previousActiveReference, reference) then
        transaction.previousActiveReference = nil
    end
    if transaction
        and ReferencesEqual(transaction.previousModeActiveReference, reference) then
        transaction.previousModeActiveReference = nil
    end
    if assignmentsChanged then
        Emit("YUI_CONFIG_SET_ASSIGNMENTS_CHANGED", providerId, reference, nil)
    end
    if replacementCreated and replacementItem then
        Emit(
            "YUI_CONFIG_SETS_CHANGED",
            providerId,
            "create-default",
            PublicUser(provider, replacementItem)
        )
    end
    Emit("YUI_CONFIG_SETS_CHANGED", providerId, "delete", reference)
    return true
end

ResolveApplyData = function(provider, reference, context)
    if type(reference) ~= "table" or not IsStableId(reference.id) then
        return nil, nil, nil, "set_not_found"
    end
    if reference.kind == "builtin" then
        local builtin = provider.builtins[reference.id]
        if not builtin then return nil, nil, nil, "set_not_found" end
        local data, code, detail = CloneProviderStoredPayload(provider, builtin.data)
        return data, CopyArray(builtin.scopeIds), builtin, code, detail
    end
    if reference.kind ~= "user" then
        return nil, nil, nil, "set_not_found"
    end

    if provider.editableUserSets then
        local ready, readyCode, readyDetail =
            GetReadyEditableAssignmentCatalog(provider)
        if not ready then
            return nil, nil, nil, readyCode, readyDetail
        end
    end

    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, nil, nil, code or "set_not_found", detail end
    local stored = catalog.items[reference.id]
    local item
    item, code, detail = NormalizeStoredItemMetadata(provider, stored, reference.id)
    if not item then return nil, nil, nil, code or "set_not_found", detail end

    local data = stored.data
    if item.providerSchemaVersion ~= provider.schemaVersion then
        data, code, detail = CloneProviderStoredPayload(provider, data)
        if not data then return nil, nil, nil, code, detail end
        if type(provider.migrate) ~= "function" then
            return nil, nil, nil, "incompatible_schema"
        end
        local ok, migrated, migrateDetail = SafeCallback(
            provider.migrate,
            data,
            item.providerSchemaVersion,
            provider.schemaVersion,
            context
        )
        if not ok then return nil, nil, nil, migrated, migrateDetail end
        data = migrated
    end

    if item.providerSchemaVersion == provider.schemaVersion then
        data, code, detail = CopyCanonicalProviderData(
            provider,
            data,
            item.scopeIds
        )
    else
        data, code, detail = NormalizeProviderData(
            provider,
            data,
            item.scopeIds,
            context,
            nil,
            true
        )
    end
    return data, CopyArray(item.scopeIds), item, code, detail
end

function ConfigSets:GetSetData(providerId, kind, setId)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local reference = NormalizeReference({
        kind = kind,
        id = setId,
    })
    if not reference then return nil, "set_not_found" end

    local data, scopeIds, source, code, detail = ResolveApplyData(
        provider,
        reference,
        BuildContext(provider, "read-data", {
            reference = reference,
        })
    )
    if not data then return nil, code, detail end

    local public
    if reference.kind == "builtin" then
        public = PublicBuiltin(provider, source)
    else
        public = PublicUser(provider, source)
    end
    return {
        kind = reference.kind,
        id = reference.id,
        providerSchemaVersion = provider.schemaVersion,
        scopeIds = CopyArray(scopeIds),
        data = data,
        set = public,
    }
end

function ConfigSets:UpdateUserSetData(providerId, setId, data, scopeIds, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    local scopeRequestOk, scopeRequestCode, scopeRequestDetail =
        ValidateAllScopeRequest(provider, scopeIds)
    if not scopeRequestOk then
        return nil, scopeRequestCode, scopeRequestDetail
    end
    if UsesAllUserSetScopes(provider) then
        local ensured, ensureCode, ensureDetail = EnsureEditableCatalog(provider)
        if not ensured then return nil, ensureCode, ensureDetail end
    end
    local catalog, code, detail = GetCatalog(provider, false)
    if not catalog then return nil, code or "set_not_found", detail end
    local item
    item, code, detail = NormalizeStoredItem(provider, catalog.items[setId], setId)
    if not item then return nil, code or "set_not_found", detail end

    if scopeIds == nil then
        scopeIds = item.scopeIds
    else
        scopeIds, code, detail = NormalizeScopeIds(provider, scopeIds, false)
        if not scopeIds then return nil, code, detail end
    end

    options = type(options) == "table" and options or {}
    local context = BuildContext(provider, "edit-data", {
        kind = "user",
        id = setId,
        reference = { kind = "user", id = setId },
        options = options,
    })
    local normalized, preparedHandled
    normalized, code, detail, preparedHandled =
        ResolvePreparedProviderData(provider, scopeIds, context)
    if not preparedHandled then
        normalized, code, detail = NormalizeProviderData(
            provider,
            data,
            scopeIds,
            context
        )
    end
    if not normalized then return nil, code, detail end

    local stored = catalog.items[setId]
    stored.scopeIds = CopyArray(scopeIds)
    stored.data = normalized
    stored.providerSchemaVersion = provider.schemaVersion
    stored.createdAt = item.createdAt
    stored.updatedAt = CurrentTime()

    local updated
    updated, code, detail = NormalizeStoredItem(provider, stored, setId)
    if not updated then return nil, code, detail end
    local public = PublicUser(provider, updated)
    local preparedToken = options.preparedToken
    if preparedToken ~= nil and options.preparedPurpose == "rollback" then
        self.preparedDataEvents[preparedToken] = nil
    elseif preparedToken ~= nil and options.deferPreparedEvent == true then
        self.preparedDataEvents[preparedToken] = {
            providerId = providerId,
            setId = setId,
            public = public,
        }
    else
        Emit("YUI_CONFIG_SETS_CHANGED", providerId, "data-update", public)
    end
    return {
        kind = "user",
        id = setId,
        providerSchemaVersion = provider.schemaVersion,
        scopeIds = CopyArray(updated.scopeIds),
        data = updated.data,
        set = public,
    }
end

local function MergeSnapshotExtension(provider, snapshot, scopeIds, extension, context)
    if extension == nil then return snapshot end
    local cloned, code, detail = CloneProviderStoredPayload(provider, snapshot)
    if code then return nil, code, detail end
    local portableExtension
    portableExtension, code, detail = CloneProviderPayload(
        provider,
        extension
    )
    if code then return nil, code, detail end
    local valid
    valid, code, detail = ValidateScopeSubsetData(provider, portableExtension, scopeIds)
    if not valid then return nil, code, detail end
    local ok
    ok, code, detail = MergeMissing(cloned, portableExtension)
    if not ok then return nil, code, detail end
    return NormalizeProviderData(provider, cloned, scopeIds, context, nil, true)
end

local function RefreshProvider(provider, reason, result, context)
    if type(provider.refresh) ~= "function" then return true, nil end
    local ok, refreshResult, detail = SafeCallback(provider.refresh, reason, result, context)
    if not ok then return false, refreshResult, detail end
    return true, refreshResult
end

local function RestoreSnapshot(provider, snapshot, scopeIds, context)
    local restore = provider.restore or provider.apply
    local ok, result, detail = SafeCallback(restore, snapshot, CopyArray(scopeIds), context)
    if not ok then return false, result, detail end
    local refreshOk, refreshResult, refreshDetail = RefreshProvider(provider, "config-set:rollback", result, context)
    if not refreshOk then return false, refreshResult, refreshDetail end
    return true, result
end

function ConfigSets:Apply(providerId, reference, owner, options)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if self.busy[providerId] then return nil, "busy" end
    options = type(options) == "table" and options or {}

    local db, profileName, identityError = GetProfileIdentity(provider)
    if not db then return nil, identityError end
    local previousActiveReference
    local previousActive = self.activeReferences[providerId]
    if previousActive
        and previousActive.database == db
        and previousActive.profileName == profileName then
        previousActiveReference = CopyReference(previousActive.reference)
    end

    local ownerKey = owner or provider
    local context = BuildContext(provider, "apply", {
        owner = ownerKey,
        reference = reference,
        options = options,
        database = db,
        profileName = profileName,
    })
    if type(provider.canApply) == "function" then
        local ok, allowed, detail = SafeCallback(provider.canApply, context)
        if not ok then return nil, allowed, detail end
        if allowed ~= true then return nil, "apply_failed", detail end
    end

    local data, scopeIds, source, code, detail = ResolveApplyData(provider, reference, context)
    if not data then return nil, code, detail end
    local preparedData, preparedCode, preparedDetail, preparedHandled =
        ResolvePreparedProviderData(provider, scopeIds, context)
    if preparedHandled then
        if not preparedData then
            return nil, preparedCode, preparedDetail
        end
        data = preparedData
    end
    local resolvedConfigurationMode
    if SupportsConfigurationModes(provider) then
        local expectedMode = options.configurationMode
        if expectedMode ~= nil then
            expectedMode = NormalizeConfigurationMode(
                provider,
                expectedMode,
                false
            )
            if not expectedMode then return nil, "invalid_configuration_mode" end
        else
            expectedMode, code, detail = self:GetConfigurationMode(providerId)
            if not expectedMode then return nil, code, detail end
        end
        resolvedConfigurationMode = expectedMode
        if reference.kind ~= "builtin"
            and (type(source) ~= "table"
                or source.configurationMode ~= expectedMode) then
            return nil, "configuration_mode_mismatch"
        end
    end
    local snapshot
    snapshot, code, detail = Capture(provider, scopeIds, BuildContext(provider, "snapshot", {
        owner = ownerKey,
        reference = reference,
        options = options,
        database = db,
        profileName = profileName,
    }))
    if not snapshot then return nil, code, detail end

    self.busy[providerId] = true
    context.scopeIds = CopyArray(scopeIds)
    context.undoSnapshot = snapshot
    local ok, applyResult, applyDetail = SafeCallback(provider.apply, data, CopyArray(scopeIds), context)
    if not ok then
        local rollbackContext = BuildContext(provider, "rollback", {
            owner = ownerKey,
            reference = reference,
            options = options,
            database = db,
            profileName = profileName,
            applyResult = applyResult,
            failure = applyDetail,
        })
        local restored, rollbackCode, rollbackDetail = RestoreSnapshot(provider, snapshot, scopeIds, rollbackContext)
        self.busy[providerId] = nil
        if options.preparedToken ~= nil then
            self.preparedDataEvents[options.preparedToken] = nil
        end
        if not restored then
            InvalidateProfileState(providerId, db, profileName, "rollback-failed")
            return nil, "rollback_failed", rollbackDetail or rollbackCode
        end
        return nil, "apply_failed", applyDetail or applyResult
    end

    local extension = type(applyResult) == "table" and applyResult.snapshotExtension or nil
    if extension then
        local extendedSnapshot
        extendedSnapshot, code, detail = MergeSnapshotExtension(provider, snapshot, scopeIds, extension, context)
        if not extendedSnapshot then
            local rollbackContext = BuildContext(provider, "rollback", {
                owner = ownerKey,
                reference = reference,
                options = options,
                database = db,
                profileName = profileName,
                applyResult = applyResult,
                failure = detail,
            })
            local restored = RestoreSnapshot(provider, context.undoSnapshot, scopeIds, rollbackContext)
            self.busy[providerId] = nil
            if options.preparedToken ~= nil then
                self.preparedDataEvents[options.preparedToken] = nil
            end
            if not restored then
                InvalidateProfileState(providerId, db, profileName, "rollback-failed")
                return nil, "rollback_failed", detail
            end
            return nil, code, detail
        end
        snapshot = extendedSnapshot
        context.undoSnapshot = snapshot
    end

    local refreshOk, refreshResult, refreshDetail = RefreshProvider(provider, "config-set:apply", applyResult, context)
    if refreshOk and type(refreshResult) == "table" and refreshResult.snapshotExtension then
        local extendedSnapshot
        extendedSnapshot, code, detail = MergeSnapshotExtension(
            provider,
            snapshot,
            scopeIds,
            refreshResult.snapshotExtension,
            context
        )
        if not extendedSnapshot then
            refreshOk = false
            refreshDetail = detail or code
        else
            snapshot = extendedSnapshot
            context.undoSnapshot = snapshot
        end
    end
    if not refreshOk and type(applyResult) == "table" and applyResult.snapshotExtension then
        local extendedSnapshot, extensionCode, extensionDetail = MergeSnapshotExtension(
            provider,
            snapshot,
            scopeIds,
            applyResult.snapshotExtension,
            context
        )
        if extendedSnapshot then
            snapshot = extendedSnapshot
            context.undoSnapshot = snapshot
        else
            refreshDetail = refreshDetail or extensionDetail or extensionCode
        end
    end
    if not refreshOk then
        local rollbackContext = BuildContext(provider, "rollback", {
            owner = ownerKey,
            reference = reference,
            options = options,
            database = db,
            profileName = profileName,
            applyResult = applyResult,
            refreshResult = refreshResult,
            failure = refreshDetail or refreshResult,
        })
        local restored, rollbackCode, rollbackDetail = RestoreSnapshot(provider, snapshot, scopeIds, rollbackContext)
        self.busy[providerId] = nil
        if options.preparedToken ~= nil then
            self.preparedDataEvents[options.preparedToken] = nil
        end
        if not restored then
            InvalidateProfileState(providerId, db, profileName, "rollback-failed")
            return nil, "rollback_failed", rollbackDetail or rollbackCode
        end
        return nil, "refresh_failed", refreshDetail or refreshResult
    end

    local appliedReference = CopyReference(reference)
    self.activeReferences[providerId] = {
        database = db,
        profileName = profileName,
        reference = appliedReference,
    }
    local appliedConfigurationMode
    local previousModeActiveReference
    if provider.editableUserSets then
        local catalog, catalogCode, catalogDetail = GetCatalog(provider, true)
        if not catalog then
            self.busy[providerId] = nil
            if options.preparedToken ~= nil then
                self.preparedDataEvents[options.preparedToken] = nil
            end
            return nil, catalogCode, catalogDetail
        end
        PersistActiveReference(provider, catalog, profileName, appliedReference)
        if SupportsConfigurationModes(provider)
            and resolvedConfigurationMode then
            appliedConfigurationMode = resolvedConfigurationMode
            previousModeActiveReference = GetModeActiveReference(
                provider,
                catalog,
                profileName,
                appliedConfigurationMode
            )
            PersistModeActiveReference(
                provider,
                catalog,
                profileName,
                appliedConfigurationMode,
                appliedReference
            )
        end
    end
    if options.recordUndo == false then
        self.transactions[providerId] = nil
    else
        self.transactions[providerId] = {
            owner = ownerKey,
            database = db,
            profileName = profileName,
            snapshot = snapshot,
            scopeIds = CopyArray(scopeIds),
            reference = appliedReference,
            previousActiveReference = previousActiveReference,
            configurationMode = appliedConfigurationMode,
            previousModeActiveReference = CopyReference(
                previousModeActiveReference
            ),
            applyResult = applyResult,
            refreshResult = refreshResult,
        }
    end
    self.busy[providerId] = nil
    if options.preparedToken ~= nil then
        local pendingEvent = self.preparedDataEvents[options.preparedToken]
        self.preparedDataEvents[options.preparedToken] = nil
        if pendingEvent
            and pendingEvent.providerId == providerId
            and pendingEvent.setId == reference.id then
            Emit(
                "YUI_CONFIG_SETS_CHANGED",
                providerId,
                "data-update",
                pendingEvent.public
            )
        end
    end
    Emit(
        "YUI_CONFIG_SET_ACTIVE_CHANGED",
        providerId,
        CopyReference(appliedReference),
        options.reason or (options.automatic and "automatic" or "apply")
    )

    return {
        providerId = providerId,
        kind = reference.kind,
        id = reference.id,
        scopeIds = CopyArray(scopeIds),
        result = applyResult,
        refreshResult = refreshResult,
        source = source,
    }
end

function ConfigSets:CanUndo(providerId, owner)
    local provider = self.providers[providerId]
    if not provider then return false, "provider_not_found" end
    local transaction = self.transactions[providerId]
    if not transaction then return false, "no_undo" end
    local ownerKey = owner or provider
    if transaction.owner ~= ownerKey then return false, "owner_mismatch" end
    local db, profileName = GetProfileIdentity(provider)
    if db ~= transaction.database or profileName ~= transaction.profileName then
        return false, "profile_changed"
    end
    return true, {
        providerId = providerId,
        reference = {
            kind = transaction.reference.kind,
            id = transaction.reference.id,
        },
        scopeIds = CopyArray(transaction.scopeIds),
    }
end

function ConfigSets:UndoForReload(providerId, owner)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if self.busy[providerId] then return nil, "busy" end
    if type(provider.restoreForReload) ~= "function" then
        return nil, "reload_restore_unavailable"
    end
    local canUndo, code = self:CanUndo(providerId, owner)
    if not canUndo then return nil, code end

    local transaction = self.transactions[providerId]
    local ownerKey = owner or provider
    local context = BuildContext(provider, "reload_restore", {
        owner = ownerKey,
        reference = transaction.reference,
        database = transaction.database,
        profileName = transaction.profileName,
        applyResult = transaction.applyResult,
        refreshResult = transaction.refreshResult,
    })
    local catalog
    if provider.editableUserSets then
        catalog = GetCatalog(provider, true)
        if not catalog then
            return nil, "reload_restore_failed", "catalog_unavailable"
        end
    end
    self.busy[providerId] = true
    local ok, result, detail = SafeCallback(
        provider.restoreForReload,
        transaction.snapshot,
        CopyArray(transaction.scopeIds),
        context
    )
    if not ok or result == nil or result == false then
        self.busy[providerId] = nil
        return nil, "reload_restore_failed", detail or result
    end

    local previousReference = CopyReference(
        transaction.previousActiveReference
    )
    if previousReference then
        self.activeReferences[providerId] = {
            database = transaction.database,
            profileName = transaction.profileName,
            reference = previousReference,
        }
    else
        self.activeReferences[providerId] = nil
    end
    if provider.editableUserSets then
        PersistActiveReference(
            provider,
            catalog,
            transaction.profileName,
            previousReference
        )
        if transaction.configurationMode then
            PersistModeActiveReference(
                provider,
                catalog,
                transaction.profileName,
                transaction.configurationMode,
                transaction.previousModeActiveReference
            )
        end
    end
    self.transactions[providerId] = nil
    self.busy[providerId] = nil
    return {
        providerId = providerId,
        reference = previousReference,
        scopeIds = CopyArray(transaction.scopeIds),
        result = result,
    }
end

function ConfigSets:Undo(providerId, owner)
    local provider = self.providers[providerId]
    if not provider then return nil, "provider_not_found" end
    if self.busy[providerId] then return nil, "busy" end
    local canUndo, code = self:CanUndo(providerId, owner)
    if not canUndo then return nil, code end

    local transaction = self.transactions[providerId]
    local ownerKey = owner or provider
    local context = BuildContext(provider, "undo", {
        owner = ownerKey,
        reference = transaction.reference,
        database = transaction.database,
        profileName = transaction.profileName,
        applyResult = transaction.applyResult,
        refreshResult = transaction.refreshResult,
    })
    if type(provider.canApply) == "function" then
        local ok, allowed, detail = SafeCallback(provider.canApply, context)
        if not ok then return nil, allowed, detail end
        if allowed ~= true then return nil, "apply_failed", detail end
    end

    local current
    current, code = Capture(provider, transaction.scopeIds, BuildContext(provider, "undo_snapshot", {
        owner = ownerKey,
        database = transaction.database,
        profileName = transaction.profileName,
    }))
    if not current then return nil, code end

    self.busy[providerId] = true
    local restore = provider.restore or provider.apply
    local ok, undoResult, detail = SafeCallback(
        restore,
        transaction.snapshot,
        CopyArray(transaction.scopeIds),
        context
    )
    local refreshResult
    local failureCode = "apply_failed"
    local failureDetail = detail or undoResult
    if ok then
        ok, refreshResult, detail = RefreshProvider(provider, "config-set:undo", undoResult, context)
        if not ok then
            failureCode = "refresh_failed"
            failureDetail = detail or refreshResult
        end
    end
    if not ok then
        local rollbackContext = BuildContext(provider, "undo_rollback", {
            owner = ownerKey,
            database = transaction.database,
            profileName = transaction.profileName,
            failure = failureDetail,
        })
        local restored, rollbackCode, rollbackDetail = RestoreSnapshot(
            provider,
            current,
            transaction.scopeIds,
            rollbackContext
        )
        self.busy[providerId] = nil
        if not restored then
            InvalidateProfileState(
                providerId,
                transaction.database,
                transaction.profileName,
                "rollback-failed"
            )
            return nil, "rollback_failed", rollbackDetail or rollbackCode
        end
        return nil, failureCode, failureDetail
    end

    local previousReference = CopyReference(transaction.previousActiveReference)
    if previousReference then
        self.activeReferences[providerId] = {
            database = transaction.database,
            profileName = transaction.profileName,
            reference = previousReference,
        }
    else
        self.activeReferences[providerId] = nil
    end
    if provider.editableUserSets then
        local catalog = GetCatalog(provider, true)
        if catalog then
            PersistActiveReference(
                provider,
                catalog,
                transaction.profileName,
                previousReference
            )
            if transaction.configurationMode then
                PersistModeActiveReference(
                    provider,
                    catalog,
                    transaction.profileName,
                    transaction.configurationMode,
                    transaction.previousModeActiveReference
                )
            end
        end
    end
    self.transactions[providerId] = nil
    self.busy[providerId] = nil
    Emit("YUI_CONFIG_SET_ACTIVE_CHANGED", providerId, CopyReference(previousReference), "undo")
    return {
        providerId = providerId,
        reference = transaction.reference,
        scopeIds = CopyArray(transaction.scopeIds),
        result = undoResult,
        refreshResult = refreshResult,
    }
end

function ConfigSets:CancelOwner(owner)
    local removed = 0
    for providerId, transaction in pairs(self.transactions) do
        if owner == nil or transaction.owner == owner then
            self.transactions[providerId] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Internal integration surface for the profile ownership implementation. It
-- reuses this service's existing payload validation and builtin materialization.
ConfigSets._ProfileOwnershipContext = {
    getCatalog = GetCatalog,
    createFromBuiltin = CreateUserFromBuiltin,
    profileIdentity = GetProfileIdentity,
    persistActive = PersistActiveReference,
    validateCatalog = EnsureCurrentProviderSchemaCatalog,
    profileProviders = GetProductProfileProviders,
    ensureExportCatalog = EnsureEditableCatalogForExport,
    exportItem = PrepareStoredItemForExport,
    normalizeImportItem = NormalizeProfileImportedSet,
    denseArray = IsDenseArray,
    uniqueName = MakeUniqueName,
    nextId = NextUserId,
    now = CurrentTime,
    specKeys = CollectSpecializationKeySet,
    capture = Capture,
    buildContext = BuildContext,
    restoreSnapshot = RestoreSnapshot,
    emit = Emit,
}

function ConfigSets:InvalidateTransactions(database)
    local removed = 0
    for providerId, transaction in pairs(self.transactions) do
        if database == nil or transaction.database == database then
            self.transactions[providerId] = nil
            removed = removed + 1
        end
    end
    for providerId, active in pairs(self.activeReferences) do
        if database == nil or active.database == database then
            self.activeReferences[providerId] = nil
            Emit("YUI_CONFIG_SET_ACTIVE_CHANGED", providerId, nil, "profile-changed")
        end
    end
    local runtime = S.ConfigSetRuntime
    if runtime and type(runtime.OnTransactionsInvalidated) == "function" then
        runtime:OnTransactionsInvalidated(database)
    end
    return removed
end

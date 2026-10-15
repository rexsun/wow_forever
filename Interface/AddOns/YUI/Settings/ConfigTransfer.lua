local ADDON_NAME, YUI = ...
if not YUI then return end

local S = YUI.Settings or {}
YUI.Settings = S

local ConfigTransfer = S.ConfigTransfer or {}
S.ConfigTransfer = ConfigTransfer
YUI.ConfigTransfer = ConfigTransfer

local Serializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

local PREFIX = "!YUI-CFG:v1:"
local FORMAT_KIND = "YUI_CONFIG_PACKAGE"
local FORMAT_VERSION = 1
local MAX_PRINT_BYTES = 512 * 1024
local MAX_SERIALIZED_BYTES = 2 * 1024 * 1024
local MAX_MODULES = 128
local MAX_ID_BYTES = 96
local MAX_DEPTH = 12
local MAX_NODES = 4096
local MAX_LARGE_NODES = 131072
local MAX_PACKAGE_NODES = (MAX_LARGE_NODES * 2) + (MAX_MODULES * 16)
local MAX_STRING_BYTES = 4096
local MAX_DIAGNOSTIC_REASON_BYTES = 512
local PARSE_SLICE_MS = 4
local PREPARE_SLICE_MS = 4
local STANDARD_PAYLOAD_DEPTH_OVERHEAD = 2
local PERSONAL_DATA_WRAPPER_DEPTH = 1
local PROFILE_STATE_WRAPPER_DEPTH = 5
local PACKAGE_WRAPPER_DEPTH = 3
local COMPRESSION = { level = 6 }
local preparedImports = setmetatable({}, { __mode = "k" })

local PACKAGE_LIMITS = {
    maxNodes = MAX_PACKAGE_NODES,
    maxDepth = MAX_DEPTH + PACKAGE_WRAPPER_DEPTH
        + STANDARD_PAYLOAD_DEPTH_OVERHEAD + PROFILE_STATE_WRAPPER_DEPTH
        + PERSONAL_DATA_WRAPPER_DEPTH,
    maxStringBytes = MAX_STRING_BYTES,
}

local function ProfileNowMS()
    if debugprofilestop then return debugprofilestop() end
    if GetTime then return GetTime() * 1000 end
    return 0
end

local function BeginParseTrace(name, detail, options)
    local Trace = YUI.Trace
    if Trace and Trace.Begin then
        return Trace:Begin("Settings", name, detail, options)
    end
end

local function FinishParseTrace(record, status, err)
    local Trace = YUI.Trace
    if record and Trace and Trace.Finish then
        Trace:Finish(record, status or "ok", err)
    end
end

local function NormalizeDiagnosticReason(value)
    if type(value) == "table" then
        value = value.reason or value.detail or value.code
    end
    if value == nil then return nil end
    value = tostring(value):match("^[^\r\n]*") or ""
    value = value:gsub("%c", " "):match("^%s*(.-)%s*$") or ""
    if value == "" then return nil end
    if #value > MAX_DIAGNOSTIC_REASON_BYTES then
        value = value:sub(1, MAX_DIAGNOSTIC_REASON_BYTES - 3) .. "..."
    end
    return value
end

local function ImportFailureDetail(phase, moduleId, reason, extra)
    local detail = {}
    for key, value in pairs(type(extra) == "table" and extra or {}) do
        detail[key] = value
    end
    detail.phase = phase
    detail.moduleId = moduleId
    detail.reason = NormalizeDiagnosticReason(reason)
    return detail
end

ConfigTransfer.PREFIX = PREFIX
ConfigTransfer.modules = ConfigTransfer.modules or {}
ConfigTransfer.order = ConfigTransfer.order or {}
ConfigTransfer.owners = ConfigTransfer.owners or {}
ConfigTransfer.importAliasOwners = ConfigTransfer.importAliasOwners or {}
ConfigTransfer.generation = ConfigTransfer.generation or 0
ConfigTransfer.busy = ConfigTransfer.busy == true

local COMPONENT_LAYOUTS = {
    CharacterStatsPanel = { "ybar.stats.panel" },
    ChatBar = { "yui.component.chatbar" },
    FocusHelper = { "yui.component.focusHelper.interruptBar" },
    CombatEnhancement = {
        "yui.component.combat_enhancement.cast_sequence",
        "yui.component.combat_enhancement.combat_timer",
        "yui.component.combat_enhancement.focus_distance",
        "yui.component.combat_enhancement.target_distance",
    },
    MythicPlusTools = { "yui.component.mythicPlusTools.battleRes" },
    ClassExtraMonitor = {
        "yui.component.class_extra_monitor.brewmaster_elixir_icon",
        "yui.component.class_extra_monitor.devourer_transform",
    },
}

local PRODUCT_LAYOUTS = {
    ychat = { "ychat.main" },
    yactionbar = {
        "yactionbar.main",
        "yactionbar.bar2",
        "yactionbar.bar3",
        "yactionbar.bar4",
        "yactionbar.bar5",
        "yactionbar.bar6",
        "yactionbar.bar7",
        "yactionbar.bar8",
        "yactionbar.pet",
        "yactionbar.stance",
        "yactionbar.possess",
        "yactionbar.extraAction",
        "yactionbar.zoneAbility",
        "yactionbar.vehicleExit",
        "yactionbar.specialActionsGroup",
    },
    ymap = {
        "yui.product.ymap.minimap",
        "yui.product.ymap.belowWidget",
        "yui.product.ymap.buttonDrawer",
    },
}

local COMPONENT_EXTRA_KEYS = {
    MapPosition = { "MapPos" },
    RaidOptimization = { "RaidOpt_ElvUIPortraitState" },
}

local COMPONENT_FIELD_WHITELISTS = {
    UtilityTools = {
        UtilityTools_Config = {
            bonusRoll = true,
            macroFrame = true,
            hideErrors = true,
            routeGuide = true,
        },
    },
    WhisperManager = {
        WhisperManager_Config = {
            historyEnabled = true,
            sound = true,
            soundSelection = true,
            applyFilters = true,
            ignoreTags = true,
            receiveOnly = true,
            timestamp = true,
            showRealm = true,
            foreignOnly = true,
            gradient = true,
            window = true,
        },
    },
}

local function CurrentClient()
    if YUI.IsForever then return "forever" end
    if YUI.IsRetail then return "retail" end
    if YUI.IsMists then return "mists" end
    return "wrath"
end

local function IsInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function IsStableId(value)
    return type(value) == "string" and value ~= "" and #value <= MAX_ID_BYTES
        and value:match("^[%w%._%-]+$") ~= nil
end

local function HasForbiddenControl(value, allowWhitespace)
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 32 and not (allowWhitespace and (byte == 9 or byte == 10 or byte == 13)) then
            return true
        end
    end
    return false
end

local function ClonePortable(value, limits, state, depth)
    state = state or { seen = {}, nodes = 0 }
    depth = depth or 0
    state.processedItems = (state.processedItems or 0) + 1
    if state.yieldIfNeeded then state.yieldIfNeeded(state) end
    local valueType = type(value)
    if value == nil or valueType == "boolean" then return value end
    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "invalid_number"
        end
        return value
    end
    if valueType == "string" then
        if #value > (limits.maxStringBytes or MAX_STRING_BYTES)
            or HasForbiddenControl(value, true) then
            return nil, "invalid_string"
        end
        return value
    end
    if valueType ~= "table" or getmetatable(value) ~= nil then
        return nil, "invalid_type"
    end
    if state.seen[value] then return nil, "cyclic_table" end
    if depth >= (limits.maxDepth or MAX_DEPTH) then return nil, "payload_too_deep" end
    state.nodes = state.nodes + 1
    if state.nodes > (limits.maxNodes or MAX_NODES) then return nil, "payload_too_large" end
    state.seen[value] = true
    local result = {}
    for key, item in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then
            state.seen[value] = nil
            return nil, "invalid_key"
        end
        if keyType == "string" and (#key > MAX_STRING_BYTES or HasForbiddenControl(key, false)) then
            state.seen[value] = nil
            return nil, "invalid_key"
        end
        local cloned, code = ClonePortable(item, limits, state, depth + 1)
        if code then
            state.seen[value] = nil
            return nil, code
        end
        result[key] = cloned
    end
    state.seen[value] = nil
    return result
end

local function ValidatePortable(value, limits, state, depth)
    state = state or { seen = {}, nodes = 0 }
    depth = depth or 0
    state.processedItems = (state.processedItems or 0) + 1
    if state.yieldIfNeeded then state.yieldIfNeeded(state) end
    local valueType = type(value)
    if value == nil or valueType == "boolean" then return true end
    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "invalid_number"
        end
        return true
    end
    if valueType == "string" then
        if #value > (limits.maxStringBytes or MAX_STRING_BYTES)
            or HasForbiddenControl(value, true) then
            return nil, "invalid_string"
        end
        return true
    end
    if valueType ~= "table" or getmetatable(value) ~= nil then
        return nil, "invalid_type"
    end
    if state.seen[value] then return nil, "cyclic_table" end
    if depth >= (limits.maxDepth or MAX_DEPTH) then return nil, "payload_too_deep" end
    state.nodes = state.nodes + 1
    if state.nodes > (limits.maxNodes or MAX_NODES) then return nil, "payload_too_large" end
    state.seen[value] = true
    for key, item in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then
            state.seen[value] = nil
            return nil, "invalid_key"
        end
        if keyType == "string" and (#key > MAX_STRING_BYTES or HasForbiddenControl(key, false)) then
            state.seen[value] = nil
            return nil, "invalid_key"
        end
        local valid, code = ValidatePortable(item, limits, state, depth + 1)
        if not valid then
            state.seen[value] = nil
            return nil, code
        end
    end
    state.seen[value] = nil
    return true
end

local function IsDenseArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if not IsInteger(key) or key < 1 then return false end
        count = count + 1
    end
    return count == #value
end

local function CopyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do result[index] = value end
    return result
end

local function IsPersonalDataDefinition(value)
    return type(value) == "table"
        and IsInteger(value.schemaVersion or 1)
        and (value.schemaVersion or 1) >= 1
        and type(value.capture) == "function"
        and type(value.normalize) == "function"
        and type(value.snapshot) == "function"
        and type(value.apply) == "function"
        and type(value.restore) == "function"
end

local function PersonalDataSelected(context, field, moduleId)
    local selection = type(context) == "table" and context[field] or nil
    return type(selection) == "table" and selection[moduleId] == true
end

local function IsStandardPayloadDefinition(definition)
    return type(definition) == "table"
        and type(definition.capture) ~= "function"
        and type(definition.normalize) ~= "function"
        and type(definition.apply) ~= "function"
end

local function GetPayloadMaxDepth(definition)
    if not IsStandardPayloadDefinition(definition) then
        return MAX_DEPTH + (definition.payloadDepthOverhead or 0)
    end
    local overhead = STANDARD_PAYLOAD_DEPTH_OVERHEAD
    if definition.personalData then overhead = overhead + PERSONAL_DATA_WRAPPER_DEPTH end
    if #definition.providerIds > 0 then
        overhead = overhead + PROFILE_STATE_WRAPPER_DEPTH
    end
    return MAX_DEPTH + overhead
end

local function CurrentProfileIdentity(productId)
    local DB = YUI.DB
    local database = DB and DB.GetAceDB and DB:GetAceDB(productId)
    if type(database) ~= "table" or type(database.profile) ~= "table" then
        return nil, nil, "profile_unavailable"
    end
    local name = type(database.GetCurrentProfile) == "function" and database:GetCurrentProfile() or nil
    if type(name) ~= "string" or name == "" then return nil, nil, "profile_unavailable" end
    return database, name
end

local function GetPath(root, path)
    local current = root
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil end
        current = current[segment]
    end
    return current
end

local function SetPath(root, path, value)
    local current = root
    local previous
    local final
    for segment in path:gmatch("[^%.]+") do
        if previous then
            if type(current[previous]) ~= "table" then current[previous] = {} end
            current = current[previous]
        end
        previous = segment
        final = segment
    end
    if final then current[final] = value end
end

local function ResolveLabel(definition)
    if definition.kind == "component" and definition.featureKey
        and YUI.Components and YUI.Components.Get
        and YUI.Components.GetDisplayName then
        local component = YUI.Components:Get(definition.featureKey)
        if component then
            local value = YUI.Components:GetDisplayName(component)
            if type(value) == "string" and value ~= "" then return value end
        end
    end
    if definition.kind == "product" then
        local product = (YUI.Products and YUI.Products[definition.productId])
            or (YUI.DB and YUI.DB.products and YUI.DB.products[definition.productId])
        local settingsEntry = product and product.settings and product.settings.entry
        local settingsModule = settingsEntry and S.modulesById and S.modulesById[settingsEntry]
        if settingsModule and type(settingsModule.titleKey) == "string"
            and YUI.Locale and YUI.Locale.Get then
            local locale = YUI.Locale:Get(settingsModule.titleNamespace or "Core")
            local value = locale and locale[settingsModule.titleKey]
            if type(value) == "string" and value ~= "" and value ~= settingsModule.titleKey then
                return value
            end
        end
        if product and type(product.shortTitleKey) == "string"
            and YUI.Locale and YUI.Locale.Get then
            local locale = YUI.Locale:Get(product.shortTitleNamespace or product.titleNamespace or "Core")
            local value = locale and locale[product.shortTitleKey]
            if type(value) == "string" and value ~= "" and value ~= product.shortTitleKey then
                return value
            end
        end
        if product and YUI.GetProductTitle then
            local value = YUI:GetProductTitle(product)
            if type(value) == "string" and value ~= "" then return value end
        end
    end
    if type(definition.labelKey) == "string" and YUI.Locale and YUI.Locale.Get then
        local locale = YUI.Locale:Get(definition.labelNamespace or "Core")
        local value = locale and locale[definition.labelKey]
        if type(value) == "string" and value ~= "" and value ~= definition.labelKey then return value end
    end
    if type(definition.label) == "string" and definition.label ~= "" then
        return definition.label
    end
    return definition.id
end

local function StableSegment(value)
    value = tostring(value or "")
    value = value:gsub("(%u+)(%u%l)", "%1_%2")
    value = value:gsub("(%l)(%u)", "%1_%2")
    value = value:gsub("[^%w]+", "_")
    value = value:gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    return value:lower()
end

local function CollectOwnershipKeys(definition)
    local scope = type(definition.productId) == "string" and definition.productId
        or (type(definition.productId) == "function" and "@active")
        or "suite"
    local root = definition.kind == "component" and definition.dataRoot ~= "profile"
        and "components" or "profile"
    local result, seen = {}, {}
    local function Add(value)
        if seen[value] then return nil, "duplicate_ownership" end
        seen[value] = true
        result[#result + 1] = value
        return true
    end
    for _, path in ipairs(definition.dataPaths) do
        if type(path) ~= "string" or path == "" or #path > 256
            or path:find("^%.") or path:find("%.$") or path:find("%.%.")
            or HasForbiddenControl(path, false) then
            return nil, "invalid_data_path"
        end
        local ok, code = Add("data:" .. scope .. ":" .. root .. ":" .. path)
        if not ok then return nil, code end
    end
    for _, layoutId in ipairs(definition.layoutIds) do
        if not IsStableId(layoutId) then return nil, "invalid_layout_id" end
        local ok, code = Add("layout:" .. layoutId)
        if not ok then return nil, code end
    end
    for _, providerId in ipairs(definition.providerIds) do
        if not IsStableId(providerId) then return nil, "invalid_provider_id" end
        local ok, code = Add("provider:" .. providerId)
        if not ok then return nil, code end
    end
    if definition.kind == "component" then
        if not IsStableId(definition.featureKey) then return nil, "invalid_feature_key" end
        if definition.manageFeatureState ~= false then
            local ok, code = Add("enabled:" .. scope .. ":" .. definition.featureKey)
            if not ok then return nil, code end
        end
    end
    return result
end

function ConfigTransfer:RegisterModule(definition)
    if type(definition) ~= "table" or not IsStableId(definition.id)
        or (definition.kind ~= "core" and definition.kind ~= "product" and definition.kind ~= "component")
        or not IsInteger(definition.schemaVersion or 1) or (definition.schemaVersion or 1) < 1
        or (definition.beforeCapture ~= nil and type(definition.beforeCapture) ~= "function")
        or (definition.splitImport ~= nil and type(definition.splitImport) ~= "function")
        or (definition.validateSnapshot ~= nil and type(definition.validateSnapshot) ~= "function")
        or (definition.showCompletion ~= nil and type(definition.showCompletion) ~= "function")
        or (definition.exclusiveWith ~= nil and type(definition.exclusiveWith) ~= "table")
        or (definition.payloadDepthOverhead ~= nil and (not IsInteger(definition.payloadDepthOverhead)
            or definition.payloadDepthOverhead < 0 or definition.payloadDepthOverhead > PROFILE_STATE_WRAPPER_DEPTH))
        or (definition.prepareExportValue ~= nil
            and type(definition.prepareExportValue) ~= "function")
        or (definition.prepareStoredValue ~= nil
            and type(definition.prepareStoredValue) ~= "function")
        or (definition.manageFeatureState ~= nil
            and type(definition.manageFeatureState) ~= "boolean")
        or (definition.importAliases ~= nil and type(definition.importAliases) ~= "table")
        or (definition.mergeCanonicalImportAliases ~= nil
            and type(definition.mergeCanonicalImportAliases) ~= "boolean")
        or (definition.mergeImportAliases ~= nil
            and type(definition.mergeImportAliases) ~= "function")
        or (definition.personalData ~= nil and (not IsPersonalDataDefinition(definition.personalData)
            or not IsStandardPayloadDefinition(definition))) then
        return nil, "invalid_module"
    end
    if self.modules[definition.id] then return nil, "duplicate_module" end
    definition.schemaVersion = definition.schemaVersion or 1
    if definition.kind == "component" then
        definition.manageFeatureState = definition.manageFeatureState ~= false
    end
    definition.clients = type(definition.clients) == "table" and definition.clients
        or { retail = true, mists = true, wrath = true }
    definition.crossClient = definition.crossClient == true
    definition.dataPaths = CopyArray(definition.dataPaths)
    definition.layoutIds = CopyArray(definition.layoutIds)
    definition.providerIds = CopyArray(definition.providerIds)
    definition.importAliases = CopyArray(definition.importAliases)
    definition.exclusiveWith = CopyArray(definition.exclusiveWith)
    for _, id in ipairs(definition.exclusiveWith) do
        if not IsStableId(id) or id == definition.id then return nil, 'invalid_module' end
    end
    if (#definition.importAliases > 0) ~= (type(definition.mergeImportAliases) == "function") then
        return nil, "invalid_module"
    end
    local seenAliases = {}
    for _, aliasId in ipairs(definition.importAliases) do
        if not IsStableId(aliasId) or aliasId == definition.id or seenAliases[aliasId]
            or self.importAliasOwners[aliasId] then
            return nil, "invalid_import_alias"
        end
        seenAliases[aliasId] = true
    end
    if definition.personalData then
        definition.personalData.schemaVersion = definition.personalData.schemaVersion or 1
    end
    if definition.prepareStoredValue ~= nil
        and not IsStandardPayloadDefinition(definition) then
        return nil, "invalid_module"
    end
    local ownershipKeys, ownershipCode = CollectOwnershipKeys(definition)
    if not ownershipKeys then return nil, ownershipCode end
    for _, key in ipairs(ownershipKeys) do
        if self.owners[key] then return nil, "ownership_conflict", key, self.owners[key] end
    end
    self.modules[definition.id] = definition
    self.order[#self.order + 1] = definition.id
    for _, key in ipairs(ownershipKeys) do self.owners[key] = definition.id end
    for _, aliasId in ipairs(definition.importAliases) do
        self.importAliasOwners[aliasId] = definition.id
    end
    self.generation = self.generation + 1
    return definition
end

local function RegisterAutomaticModules(self)
    if YUI.AutoRepair and YUI.AutoRepair:GetOwnerProduct() and not self.modules["core.auto_repair"] then
        YUI.AutoRepair:GetConfig()
        self:RegisterModule({
            clients = { retail = true, mists = true, wrath = true, forever = true },
            id = "core.auto_repair", kind = "core", schemaVersion = 1,
            labelKey = "auto_repair.header",
            productId = function() return YUI.AutoRepair:GetOwnerProduct() end,
            dataPaths = { "AutoRepair" },
            refresh = function()
                YUI.AutoRepair:SetMode(YUI.AutoRepair:GetMode())
                return true
            end,
        })
    end
    if YUI.TeleportAnnouncement and YUI.TeleportAnnouncement:GetOwnerProduct() and not self.modules["core.teleport_announcement"] then
        YUI.TeleportAnnouncement:GetConfig()
        self:RegisterModule({
            clients = { retail = true, mists = true, wrath = true, forever = true },
            id = "core.teleport_announcement", kind = "core", schemaVersion = 1,
            labelKey = "teleports.settings.announce_header",
            productId = function() return YUI.TeleportAnnouncement:GetOwnerProduct() end,
            dataPaths = { "TeleportAnnouncement" },
            refresh = function()
                YUI.TeleportAnnouncement:Refresh()
                return true
            end,
        })
    end
    if not self.modules["core.appearance"] then
        self:RegisterModule({
            clients = { retail = true, mists = true, wrath = true, forever = true },
            id = "core.appearance", kind = "core", label = "主题外观", schemaVersion = 1,
            labelKey = "settings.config_transfer.module.core_appearance",
            productId = function() return YUI.DB and YUI.DB.activeProductId or "suite" end,
            dataPaths = { "Appearance" },
            refresh = function()
                local appearance = YUI.GUI2 and YUI.GUI2.Appearance
                if appearance and appearance.ApplyStoredPreset then appearance:ApplyStoredPreset() end
                return true
            end,
        })
    end

    local componentProductIds = {}
    for _, feature in pairs((YUI.Components and YUI.Components.features) or {}) do
        if type(feature.product) == "string" and feature.product ~= "" and feature.product ~= "suite" then
            componentProductIds[feature.product] = true
        end
    end
    for productId, product in pairs(YUI.Products or {}) do
        if productId ~= "suite" and product.db and product.db.enabled ~= false
            and not componentProductIds[productId]
            and type(product.db.storageKey) == "string" and product.db.storageKey ~= "" then
            local id = "product." .. productId
            if not self.modules[id] then
                local providerIds = {}
                local ConfigSets = S.ConfigSets
                if ConfigSets and ConfigSets.GetProvider and ConfigSets:GetProvider(productId) then
                    providerIds[1] = productId
                end
                self:RegisterModule({
                    id = id,
                    kind = "product",
                    clients = { retail = true, mists = true, wrath = true, forever = true },
                    label = product.shortTitle or product.title or productId,
                    schemaVersion = 1,
                    productId = productId,
                    dataPaths = { product.db.storageKey },
                    layoutIds = PRODUCT_LAYOUTS[productId] or {},
                    providerIds = providerIds,
                    beforeCapture = type(product.transfer) == "table"
                        and product.transfer.beforeCapture or nil,
                    prepareStoredValue = type(product.transfer) == "table"
                        and product.transfer.prepareStoredValue or nil,
                    prepareExportValue = type(product.transfer) == "table"
                        and product.transfer.prepareExportValue or nil,
                    splitImport = type(product.transfer) == 'table' and product.transfer.splitImport or nil,
                    maxPayloadNodes = #providerIds > 0 and MAX_LARGE_NODES or MAX_NODES,
                    requiresReload = true,
                })
            end
        end
    end

    for key, feature in pairs((YUI.Components and YUI.Components.features) or {}) do
        local id = "component." .. StableSegment(key)
        if not self.modules[id] then
            local transfer = type(feature.transfer) == "table" and feature.transfer or {}
            local dataPaths = CopyArray(transfer.dataPaths)
            if #dataPaths == 0 and transfer.configless ~= true then
                dataPaths[1] = key .. "_Config"
            end
            for _, extra in ipairs(COMPONENT_EXTRA_KEYS[key] or {}) do
                dataPaths[#dataPaths + 1] = extra
            end
            local registered = YUI.Components.registry and YUI.Components.registry[key]
            local versions = feature.versions
            if YUI.IsForever then
                versions = versions or feature.version or (registered and registered.versions)
            end
            local clients = { retail = true, mists = true, wrath = true, forever = true }
            if type(versions) == "table" then
                clients = { retail = false, mists = false, wrath = false }
                for _, version in ipairs(versions) do
                    if version == "mainline" then clients.retail = true else clients[version] = true end
                end
            end
            self:RegisterModule({
                id = id,
                kind = "component",
                label = feature.name or key,
                schemaVersion = transfer.schemaVersion or 1,
                clients = transfer.clients or clients,
                productId = feature.product or "suite",
                featureKey = key,
                dataRoot = transfer.dataRoot or "components",
                dataPaths = dataPaths,
                fieldWhitelists = transfer.fieldWhitelists or COMPONENT_FIELD_WHITELISTS[key],
                layoutIds = transfer.layoutIds or COMPONENT_LAYOUTS[key] or {},
                capture = transfer.capture,
                normalize = transfer.normalize,
                apply = transfer.apply,
                restore = transfer.restore,
                refresh = transfer.refresh,
                personalData = transfer.personalData,
                manageFeatureState = transfer.manageFeatureState,
                importAliases = transfer.importAliases,
                mergeImportAliases = transfer.mergeImportAliases,
                requiresReload = feature.requiresReload == true,
            })
        end
    end
end

-- 导入、导出共用显示规则；解析仍保留不兼容项供校验，不能绕过导入门禁。
function ConfigTransfer:IsModuleVisible(id)
    if not YUI.IsForever then return true end
    local definition = self.modules[id]
    return definition ~= nil and definition.clients.forever == true
end

function ConfigTransfer:ListModules(context)
    RegisterAutomaticModules(self)
    local result = {}
    local requested
    if type(context) == "table" and type(context.moduleIds) == "table" then
        requested = {}
        for _, id in ipairs(context.moduleIds) do requested[id] = true end
    end
    for _, id in ipairs(self.order) do
        local definition = self.modules[id]
        if definition and self:IsModuleVisible(id) and ((requested and requested[id])
            or (not requested and definition.hiddenFromProfile ~= true)) then
            result[#result + 1] = {
                id = id,
                kind = definition.kind,
                label = ResolveLabel(definition),
                schemaVersion = definition.schemaVersion,
                compatible = definition.clients[CurrentClient()] == true,
                requiresReload = definition.requiresReload == true,
                supportsPersonalData = definition.personalData ~= nil,
                selectedByDefault = definition.selectedByDefault ~= false,
            }
        end
    end
    table.sort(result, function(left, right)
        local kindOrder = { core = 1, product = 2, component = 3 }
        if left.kind ~= right.kind then
            return (kindOrder[left.kind] or 9) < (kindOrder[right.kind] or 9)
        end
        return left.label < right.label
    end)
    return result
end

local function ResolveProductId(definition)
    if type(definition.productId) == "function" then return definition.productId() end
    return definition.productId or "suite"
end

-- Background writers defer only while a participating database is being
-- imported. Keep the token private so an old/canceled owner cannot release a
-- later import; the synchronous commit busy flag has a different lifetime.
local importSession

function ConfigTransfer:BeginImportSession(moduleIds)
    if importSession or self.busy then return nil, "busy" end
    RegisterAutomaticModules(self)
    if type(moduleIds) ~= "table" or #moduleIds < 1 then return nil, "invalid_selection" end
    local databases = {}
    for _, id in ipairs(moduleIds) do
        local definition = self.modules[id]
        if not definition then return nil, "invalid_selection" end
        local database, _, code = CurrentProfileIdentity(ResolveProductId(definition))
        if not database then return nil, code or "profile_unavailable" end
        databases[database] = true
    end
    local token = {}
    importSession = { token = token, databases = databases }
    return token
end

function ConfigTransfer:IsImporting(productId)
    if not importSession then return false end
    if productId == nil then return true end
    local database = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(productId)
    return database ~= nil and importSession.databases[database] == true
end

function ConfigTransfer:EndImportSession(token)
    if not importSession or importSession.token ~= token then return false end
    importSession = nil
    if YUI.Event and YUI.Event.Emit then
        pcall(YUI.Event.Emit, YUI.Event, "YUI_CONFIG_TRANSFER_RELEASED")
    end
    return true
end

local function CaptureStandard(definition, context)
    local productId = ResolveProductId(definition)
    local database, profileName, code = CurrentProfileIdentity(productId)
    if not database then return nil, code end
    local payload = { data = {}, present = {}, layouts = {}, layoutPresent = {}, enabled = nil }
    local root = definition.kind == "component" and definition.dataRoot ~= "profile"
        and ((type(database.profile.Components) == "table" and database.profile.Components) or {})
        or database.profile
    for _, path in ipairs(definition.dataPaths) do
        local value = GetPath(root, path)
        payload.present[path] = value ~= nil
        local whitelist = definition.fieldWhitelists and definition.fieldWhitelists[path]
        local candidate
        if value ~= nil and whitelist then
            candidate = {}
            for key in pairs(whitelist) do candidate[key] = value[key] end
        elseif value ~= nil then
            candidate = value
        end
        if candidate ~= nil then
            local owned
            if type(definition.prepareStoredValue) == "function" then
                local ok, prepared, prepareCode, prepareDetail = pcall(
                    definition.prepareStoredValue,
                    path,
                    candidate,
                    {
                        action = "export",
                        moduleId = definition.id,
                        productId = productId,
                        profileName = profileName,
                        options = context,
                    }
                )
                if not ok then return nil, "capture_failed", prepared end
                if prepared == nil then
                    return nil, prepareCode or "capture_failed", prepareDetail
                end
                owned = prepared
            else
                local cloneCode
                owned, cloneCode = ClonePortable(candidate, {
                    maxNodes = definition.maxPayloadNodes or MAX_NODES,
                    maxDepth = MAX_DEPTH,
                })
                if not owned then return nil, cloneCode end
            end
            candidate = owned
        end
        if candidate ~= nil and type(definition.prepareExportValue) == "function" then
            local ok, prepared, prepareCode, prepareDetail = pcall(
                definition.prepareExportValue,
                path,
                candidate,
                {
                    action = "export",
                    moduleId = definition.id,
                    productId = productId,
                    profileName = profileName,
                    options = context,
                }
            )
            if not ok then return nil, "capture_failed", prepared end
            if prepared == nil then
                return nil, prepareCode or "capture_failed", prepareDetail
            end
            candidate = prepared
        end
        if candidate ~= nil and (type(definition.prepareStoredValue) == "function"
            or type(definition.prepareExportValue) == "function") then
            local cloneCode
            candidate, cloneCode = ClonePortable(candidate, {
                maxNodes = definition.maxPayloadNodes or MAX_NODES,
                maxDepth = MAX_DEPTH,
            })
            if not candidate then return nil, cloneCode end
        end
        if candidate ~= nil then payload.data[path] = candidate end
    end
    if definition.kind == "component" and definition.manageFeatureState ~= false then
        local Components = YUI.Components
        local feature = Components and Components.features and Components.features[definition.featureKey]
        local store = Components and Components.GetStore and Components:GetStore(feature and feature.product)
        local stored = store and store[definition.featureKey]
        payload.enabled = stored == nil and feature and feature.default == true or stored == true
    end
    local Layout = YUI.Layout
    for _, layoutId in ipairs(definition.layoutIds) do
        if Layout and Layout.GetPlacement then
            local placement = Layout:GetPlacement(layoutId)
            if not placement and Layout._private and Layout._private.GetSavedPlacement then
                placement = Layout._private.GetSavedPlacement(layoutId)
            end
            local present = Layout.HasPlacement
                and Layout:HasPlacement(layoutId) == true
                or (not Layout.HasPlacement and placement ~= nil)
            payload.layoutPresent[layoutId] = present
            if present and placement then payload.layouts[layoutId] = placement end
        end
    end
    local ConfigSets = S.ConfigSets
    if #definition.providerIds > 0 and ConfigSets and ConfigSets.ExportProfileState then
        local state, stateCode, stateDetail = ConfigSets:ExportProfileState(productId, profileName, definition.providerIds)
        if not state then return nil, stateCode, stateDetail end
        payload.configSets = state
    end
    if definition.personalData
        and PersonalDataSelected(context, "includePersonalData", definition.id) then
        local personal = definition.personalData
        local ok, data, dataCode, dataDetail = pcall(
            personal.capture,
            personal,
            definition,
            context
        )
        if not ok or data == nil then return nil, dataCode or "personal_data_capture_failed", dataDetail end
        payload.personalData = {
            schemaVersion = personal.schemaVersion,
            data = data,
        }
    end
    return payload
end

local function ValidateStandardPayload(definition, payload)
    if type(payload) ~= "table" or type(payload.data) ~= "table"
        or type(payload.present) ~= "table"
        or type(payload.layouts) ~= "table" or type(payload.layoutPresent) ~= "table" then
        return nil, "invalid_module_payload"
    end
    if definition.kind == "component" then
        if definition.manageFeatureState ~= false
            and type(payload.enabled) ~= "boolean" then
            return nil, "invalid_module_payload"
        end
        if definition.manageFeatureState == false and payload.enabled ~= nil
            and type(payload.enabled) ~= "boolean" then
            return nil, "invalid_module_payload"
        end
    end
    local allowedData = {}
    for _, path in ipairs(definition.dataPaths) do allowedData[path] = true end
    for path in pairs(allowedData) do
        if type(payload.present[path]) ~= "boolean" then return nil, "unexpected_data_path" end
    end
    for path, present in pairs(payload.present) do
        if not allowedData[path] or type(present) ~= "boolean" then
            return nil, "unexpected_data_path"
        end
    end
    for path in pairs(payload.data) do
        if not allowedData[path] or payload.present[path] ~= true then return nil, "unexpected_data_path" end
        local whitelist = definition.fieldWhitelists and definition.fieldWhitelists[path]
        if whitelist and type(payload.data[path]) == "table" then
            for key in pairs(payload.data[path]) do
                if not whitelist[key] then return nil, "unexpected_data_field" end
            end
            if definition.featureKey == "WhisperManager" and path == "WhisperManager_Config"
                and payload.data[path].soundSelection ~= nil then
                local service = YUI.NotificationSound
                local selection = service and service:NormalizeSelection(payload.data[path].soundSelection)
                if not selection then return nil, "invalid_sound_selection" end
                -- Validate portable intent, never the receiver's installed providers.
                payload.data[path].soundSelection = selection
            end
        end
    end
    local allowedLayouts = {}
    for _, layoutId in ipairs(definition.layoutIds) do allowedLayouts[layoutId] = true end
    for layoutId in pairs(allowedLayouts) do
        if type(payload.layoutPresent[layoutId]) ~= "boolean" then
            return nil, "unexpected_layout"
        end
    end
    for layoutId, present in pairs(payload.layoutPresent) do
        if not allowedLayouts[layoutId] or type(present) ~= "boolean" then
            return nil, "unexpected_layout"
        end
    end
    for layoutId in pairs(payload.layouts) do
        if not allowedLayouts[layoutId] or payload.layoutPresent[layoutId] == nil then
            return nil, "unexpected_layout"
        end
    end
    if payload.configSets ~= nil and #definition.providerIds == 0 then
        return nil, "unexpected_config_sets"
    end
    if payload.personalData ~= nil then
        local personal = definition.personalData
        if not personal or type(payload.personalData) ~= "table"
            or payload.personalData.schemaVersion ~= personal.schemaVersion
            or payload.personalData.data == nil then
            return nil, "unexpected_personal_data"
        end
        for key in pairs(payload.personalData) do
            if key ~= "schemaVersion" and key ~= "data" then
                return nil, "unexpected_personal_data"
            end
        end
    end
    return payload
end

local function DiscardLegacyUnpersistedLayouts(definition, payload)
    if type(definition) ~= "table" or type(payload) ~= "table"
        or type(payload.layouts) ~= "table" or type(payload.layoutPresent) ~= "table" then
        return payload
    end
    for _, layoutId in ipairs(definition.layoutIds) do
        if payload.layoutPresent[layoutId] == false then
            payload.layouts[layoutId] = nil
        end
    end
    return payload
end

local function BuildPackage(self, moduleIds, context, payloads)
    RegisterAutomaticModules(self)
    if type(moduleIds) ~= "table" or #moduleIds < 1 or #moduleIds > MAX_MODULES then
        return nil, "invalid_selection"
    end
    local package = {
        kind = FORMAT_KIND,
        formatVersion = FORMAT_VERSION,
        source = { addonVersion = tostring(YUI.Version or "unknown"), client = CurrentClient() },
        modules = {},
    }
    local seen = {}
    for _, id in ipairs(moduleIds) do
        local definition = self.modules[id]
        if not definition or seen[id] or definition.clients[CurrentClient()] ~= true then
            return nil, "invalid_selection", id
        end
        seen[id] = true
        if not payloads and type(definition.beforeCapture) == "function" then
            local ok, synced, syncCode, syncDetail = pcall(
                definition.beforeCapture,
                definition,
                context
            )
            if not ok or synced == false or synced == nil then
                return nil, syncCode or "before_capture_failed", id, syncDetail
            end
        end
        local payload, code, detail
        if payloads then
            payload = payloads[id]
        elseif type(definition.capture) == "function" then
            local ok
            ok, payload, code, detail = pcall(definition.capture, definition, context)
            if not ok then return nil, "capture_failed", id end
        else
            payload, code, detail = CaptureStandard(definition, context)
        end
        if not payload then return nil, code or "capture_failed", id, detail end
        local cloned
        cloned, code = ClonePortable(payload, {
            maxNodes = definition.maxPayloadNodes or MAX_NODES,
            maxDepth = GetPayloadMaxDepth(definition),
        })
        if not cloned then return nil, code, id end
        package.modules[#package.modules + 1] = {
            id = id, schemaVersion = definition.schemaVersion, payload = cloned,
        }
    end
    table.sort(package.modules, function(left, right) return left.id < right.id end)
    local packageDepth = MAX_DEPTH
    for _, id in ipairs(moduleIds) do
        local limit = GetPayloadMaxDepth(self.modules[id])
        if limit > packageDepth then packageDepth = limit end
    end
    packageDepth = packageDepth + PACKAGE_WRAPPER_DEPTH
    local validatedPackage, packageCode = ClonePortable(package, {
        maxNodes = MAX_PACKAGE_NODES,
        maxDepth = packageDepth,
        maxStringBytes = MAX_STRING_BYTES,
    })
    if not validatedPackage then return nil, packageCode or "package_too_large" end
    package = validatedPackage
    local serialized = Serializer:Serialize(package)
    if #serialized > MAX_SERIALIZED_BYTES then return nil, "package_too_large" end
    local compressed = LibDeflate:CompressDeflate(serialized, COMPRESSION)
    local result = PREFIX .. LibDeflate:EncodeForPrint(compressed)
    if #result > MAX_PRINT_BYTES then return nil, "package_too_large" end
    return result, { moduleCount = #package.modules, characterCount = #result }
end

function ConfigTransfer:BuildExport(moduleIds, context)
    return BuildPackage(self, moduleIds, context)
end

-- Legacy adapters only translate data here. The resulting string still passes
-- the normal parser, module preflight, player selection and transaction.
function ConfigTransfer:BuildImportString(payloads)
    if type(payloads) ~= 'table' then return nil, 'invalid_selection' end
    local ids = {}
    for id in pairs(payloads) do ids[#ids + 1] = id end
    return BuildPackage(self, ids, nil, payloads)
end

local PARSED_KIND_ORDER = { core = 1, product = 2, component = 3, unknown = 4 }

local function ValidatePackageShape(package)
    if package.kind ~= FORMAT_KIND or package.formatVersion ~= FORMAT_VERSION
        or type(package.source) ~= "table" or not IsDenseArray(package.modules)
        or (package.source.client ~= "retail" and package.source.client ~= "mists" and package.source.client ~= "wrath" and package.source.client ~= "forever")
        or #package.modules < 1 or #package.modules > MAX_MODULES then
        return nil, "invalid_package"
    end
    local seen = {}
    for _, entry in ipairs(package.modules) do
        if type(entry) ~= "table" or not IsStableId(entry.id) or seen[entry.id]
            or not IsInteger(entry.schemaVersion) or entry.schemaVersion < 1 then
            return nil, "invalid_package"
        end
        seen[entry.id] = true
    end
    return true
end

local function NewParsedPackage(package, input, generation)
    return {
        source = { addonVersion = tostring(package.source.addonVersion or "?"), client = package.source.client },
        modules = {}, byId = {}, registryGeneration = generation,
        input = input,
    }
end

local function BuildParsedItem(service, package, entry, portable)
    local definition = service.modules[entry.id]
    local status = "ready"
    if not definition then
        status = "unknown"
    elseif definition.clients[CurrentClient()] ~= true then
        status = "client_incompatible"
    elseif package.source.client ~= CurrentClient() and definition.crossClient ~= true then
        status = "client_incompatible"
    elseif entry.schemaVersion > definition.schemaVersion then
        status = "schema_newer"
    elseif entry.schemaVersion < definition.schemaVersion and type(definition.migrate) ~= "function" then
        status = "schema_unsupported"
    end
    if portable == nil then
        status = "invalid_payload"
    elseif definition and status == "ready" then
        portable = DiscardLegacyUnpersistedLayouts(definition, portable)
        if not definition.normalize and not definition.apply then
            local valid = ValidateStandardPayload(definition, portable)
            if not valid then status = "invalid_payload" end
        end
    end
    return {
        id = entry.id,
        label = definition and ResolveLabel(definition) or entry.id,
        kind = definition and definition.kind or "unknown",
        status = status,
        selectedByDefault = status == "ready" and (not definition or definition.selectedByDefault ~= false),
        schemaVersion = entry.schemaVersion,
        definition = definition,
        rawPayload = portable,
        hasPersonalData = type(portable) == "table" and portable.personalData ~= nil,
    }
end

local function FinishParsedPackage(parsed)
    table.sort(parsed.modules, function(left, right)
        if left.kind ~= right.kind then
            return (PARSED_KIND_ORDER[left.kind] or 9) < (PARSED_KIND_ORDER[right.kind] or 9)
        end
        return left.label < right.label
    end)
    return parsed
end

local MISSING_PORTABLE_PAYLOAD = {}

local function BuildClassificationInputs(service, package, portablePayloads)
    local companions, splitIndices, occupied = {}, {}, {}
    for _, entry in ipairs(package.modules) do occupied[entry.id] = true end
    for index, entry in ipairs(package.modules) do
        local definition = service.modules[entry.id]
        if definition and definition.splitImport and portablePayloads[index]
            and definition.clients[CurrentClient()] and package.source.client == CurrentClient()
            and entry.schemaVersion <= definition.schemaVersion then
            splitIndices[#splitIndices+1] = index
            local called, base, extra = pcall(definition.splitImport, portablePayloads[index], package.source)
            local staged, valid = {}, called and type(base)=='table' and (extra==nil or type(extra)=='table')
            if valid then
                base = ClonePortable(base,{maxNodes=definition.maxPayloadNodes or MAX_NODES,maxDepth=GetPayloadMaxDepth(definition)})
                valid = base ~= nil
            end
            if valid then
                for id, payload in pairs(extra or {}) do
                    local target = service.modules[id]
                    if not IsStableId(id) or occupied[id] or not target then valid=false; break end
                    local copy = ClonePortable(payload,{maxNodes=target.maxPayloadNodes or MAX_NODES,maxDepth=GetPayloadMaxDepth(target)})
                    if not copy then valid=false; break end
                    staged[#staged+1]={entry={id=id,schemaVersion=target.schemaVersion},payload=copy}
                end
            end
            if #package.modules+#companions+#staged>MAX_MODULES then valid=false end
            portablePayloads[index]=valid and base or nil
            if valid then for _, item in ipairs(staged) do companions[#companions+1]=item; occupied[item.entry.id]=true end end
        end
    end
    if #splitIndices>0 then
        local expanded={kind=package.kind,formatVersion=package.formatVersion,source=package.source,modules={}}
        for index,entry in ipairs(package.modules) do expanded.modules[#expanded.modules+1]={id=entry.id,
            schemaVersion=entry.schemaVersion,payload=portablePayloads[index]} end
        for _,item in ipairs(companions) do expanded.modules[#expanded.modules+1]={id=item.entry.id,
            schemaVersion=item.entry.schemaVersion,payload=item.payload} end
        if not ValidatePortable(expanded,PACKAGE_LIMITS) then
            for _,index in ipairs(splitIndices) do portablePayloads[index]=nil end
            companions={}
        end
    end
    local sourceById = {}
    for index, entry in ipairs(package.modules) do
        sourceById[entry.id] = {
            entry = entry,
            payload = portablePayloads[index],
        }
    end

    local consumed = {}
    local synthesized = {}
    for _, targetId in ipairs(service.order) do
        local definition = service.modules[targetId]
        if definition and #definition.importAliases > 0 then
            local canonical = sourceById[targetId]
            if canonical and not definition.mergeCanonicalImportAliases then
                for _, aliasId in ipairs(definition.importAliases) do
                    if sourceById[aliasId] then consumed[aliasId] = true end
                end
            else
                local aliases = {}
                local hasAlias = false
                for _, aliasId in ipairs(definition.importAliases) do
                    local source = sourceById[aliasId]
                    if source then
                        aliases[aliasId] = {
                            schemaVersion = source.entry.schemaVersion,
                            payload = source.payload,
                        }
                        hasAlias = true
                    end
                end
                if hasAlias then
                    local ok, merged = pcall(
                        definition.mergeImportAliases,
                        aliases,
                        {
                            action = "import_alias",
                            moduleId = targetId,
                            source = package.source,
                            canonical = canonical,
                        }
                    )
                    if ok and merged ~= nil then
                        local portable = ClonePortable(merged, {
                            maxNodes = definition.maxPayloadNodes or MAX_NODES,
                            maxDepth = GetPayloadMaxDepth(definition),
                        })
                        if portable then
                            if canonical then consumed[targetId] = true end
                            synthesized[#synthesized + 1] = {
                                entry = {
                                    id = targetId,
                                    schemaVersion = definition.schemaVersion,
                                },
                                payload = portable,
                            }
                            for aliasId in pairs(aliases) do consumed[aliasId] = true end
                        end
                    end
                    if canonical and not consumed[targetId] then
                        -- An opted-in canonical merge must not silently discard failed aliases.
                        for index, entry in ipairs(package.modules) do
                            if entry.id == targetId then portablePayloads[index] = nil end
                        end
                    end
                end
            end
        end
    end

    local entries, payloads = {}, {}
    for index, entry in ipairs(package.modules) do
        if not consumed[entry.id] then
            entries[#entries + 1] = entry
            payloads[#entries] = portablePayloads[index] == nil
                and MISSING_PORTABLE_PAYLOAD or portablePayloads[index]
        end
    end
    for _, item in ipairs(synthesized) do
        entries[#entries + 1] = item.entry
        payloads[#entries] = item.payload
    end
    for _, item in ipairs(companions) do entries[#entries+1]=item.entry; payloads[#entries]=item.payload end
    return entries, payloads
end

local function ParseValidatedPackage(service, package, input)
    local parsed = {
        source = { addonVersion = tostring(package.source.addonVersion or "?"), client = package.source.client },
        modules = {}, byId = {}, registryGeneration = service.generation,
        input = input,
    }
    local portablePayloads = {}
    for index, entry in ipairs(package.modules) do
        portablePayloads[index] = ClonePortable(entry.payload, {
            maxNodes = service.modules[entry.id] and service.modules[entry.id].maxPayloadNodes or MAX_NODES,
            maxDepth = service.modules[entry.id] and GetPayloadMaxDepth(service.modules[entry.id]) or MAX_DEPTH,
        })
    end
    local entries
    entries, portablePayloads = BuildClassificationInputs(service, package, portablePayloads)
    for index, entry in ipairs(entries) do
        local portable = portablePayloads[index]
        if portable == MISSING_PORTABLE_PAYLOAD then portable = nil end
        local item = BuildParsedItem(service, package, entry, portable)
        parsed.modules[#parsed.modules + 1] = item
        parsed.byId[item.id] = item
    end
    return FinishParsedPackage(parsed)
end

function ConfigTransfer:ParseImportString(value, context)
    RegisterAutomaticModules(self)
    if type(value) ~= "string" then return nil, "empty_input" end
    value = value:match("^%s*(.-)%s*$") or ""
    if value == "" then return nil, "empty_input" end
    if #value > MAX_PRINT_BYTES then return nil, "input_too_large" end
    if value:sub(1, #PREFIX) ~= PREFIX then return nil, "unsupported_prefix" end
    local compressed = LibDeflate:DecodeForPrint(value:sub(#PREFIX + 1))
    if not compressed then return nil, "decode_failed" end
    local serialized = LibDeflate:DecompressDeflate(compressed, MAX_SERIALIZED_BYTES)
    if not serialized then return nil, "decompress_failed" end
    local ok, package = Serializer:Deserialize(serialized)
    if not ok or type(package) ~= "table" then return nil, "deserialize_failed" end
    local valid, code = ValidatePortable(package, PACKAGE_LIMITS)
    if not valid then return nil, code or "invalid_package" end
    valid, code = ValidatePackageShape(package)
    if not valid then return nil, code end
    return ParseValidatedPackage(self, package, value)
end

local ParseJob = {}
ParseJob.__index = ParseJob

function ParseJob:EmitProgress(phase, progress, extra)
    if self.finished then return end
    progress = math.max(self.progress or 0, math.min(tonumber(progress) or 0, 1))
    self.progress = progress
    local detail = {
        phase = phase,
        progress = progress,
        processedNodes = extra and extra.processedNodes or nil,
        moduleIndex = extra and extra.moduleIndex or nil,
        moduleCount = extra and extra.moduleCount or nil,
    }
    local callback = self.callbacks and self.callbacks.onProgress
    if type(callback) == "function" then pcall(callback, detail) end
end

function ParseJob:Cleanup()
    if self.timer and self.timer.Cancel then self.timer:Cancel() end
    self.timer = nil
    self.compressed = nil
    self.serialized = nil
    self.package = nil
    self.validationCoroutine = nil
    self.validationState = nil
    self.copyCoroutine = nil
    self.copyState = nil
    self.copyLimits = nil
    self.safePayloads = nil
    self.classificationEntries = nil
    self.parsed = nil
    self.value = nil
    self.context = nil
    self.callbacks = nil
    self.service = nil
end

function ParseJob:Finish(parsed, code, status, err)
    if self.finished or self.finishing then return false end
    self.finishing = true
    if parsed then self:EmitProgress("complete", 1) end
    self.finished = true
    self.finishing = nil
    local traceStatus = status == "cancelled" and "skip" or status
    FinishParseTrace(self.stageTrace, traceStatus or (parsed and "ok" or "error"), err or code)
    self.stageTrace = nil
    FinishParseTrace(self.overallTrace, traceStatus or (parsed and "ok" or "error"), err or code)
    self.overallTrace = nil
    local callback = self.callbacks and self.callbacks.onComplete
    self:Cleanup()
    if type(callback) == "function" and status ~= "cancelled" then
        pcall(callback, parsed, code)
    end
    return true
end

function ParseJob:Cancel()
    if self.finished then return false end
    return self:Finish(nil, nil, "cancelled")
end

function ParseJob:BeginStage(name, async)
    FinishParseTrace(self.stageTrace, "ok")
    self.stageTrace = BeginParseTrace("ConfigTransfer:parse:" .. name, nil, {
        durationKind = async and "async" or "sync",
        blocking = async ~= true,
    })
end

function ParseJob:Schedule()
    if self.finished or self.synchronous or self.timer then return end
    local timerAPI = C_Timer
    if not (timerAPI and timerAPI.NewTimer) then
        self.synchronous = true
        while not self.finished do self:RunStep() end
        return
    end
    self.timer = timerAPI.NewTimer(0, function()
        self.timer = nil
        if self.finished then return end
        local ok, err = pcall(self.RunStep, self)
        if not ok then self:Finish(nil, "invalid_package", "error", err) end
    end)
end

function ParseJob:StartValidation()
    self:BeginStage("portable-validation", true)
    self.validationState = { seen = {}, nodes = 0 }
    self.validationState.yieldIfNeeded = function(state)
        if ProfileNowMS() >= self.sliceDeadline then
            coroutine.yield(state.nodes)
        end
    end
    self.validationCoroutine = coroutine.create(function()
        return ValidatePortable(self.package, PACKAGE_LIMITS, self.validationState)
    end)
    self.stage = "portable-validation"
end

function ParseJob:ResumeValidation()
    self.sliceDeadline = ProfileNowMS() + PARSE_SLICE_MS
    local resumed, valid, code = coroutine.resume(self.validationCoroutine)
    if not resumed then
        self:Finish(nil, "invalid_package", "error", valid)
        return
    end
    local state = self.validationState
    self:EmitProgress("portable-validation", 0.46 + (0.14 * math.min((state.nodes or 0) / MAX_PACKAGE_NODES, 0.99)), {
        processedNodes = state.nodes,
    })
    if coroutine.status(self.validationCoroutine) ~= "dead" then
        self:Schedule()
        return
    end
    FinishParseTrace(self.stageTrace, valid and "ok" or "error", code)
    self.stageTrace = nil
    if not valid then
        self:Finish(nil, code or "invalid_package")
        return
    end
    valid, code = ValidatePackageShape(self.package)
    if not valid then
        self:Finish(nil, code)
        return
    end
    self.validationCoroutine = nil
    self.validationState = nil
    self.safePayloads = {}
    self.moduleIndex = 1
    self.moduleCount = #self.package.modules
    self:BeginStage("portable-copy", true)
    self.stage = "portable-copy"
    self:EmitProgress("portable-copy", 0.60, { moduleIndex = 0, moduleCount = self.moduleCount })
    self:Schedule()
end

function ParseJob:StartPayloadCopy(entry)
    local definition = self.service.modules[entry.id]
    local limits = {
        maxNodes = definition and definition.maxPayloadNodes or MAX_NODES,
        maxDepth = definition and GetPayloadMaxDepth(definition) or MAX_DEPTH,
    }
    self.copyLimits = limits
    self.copyState = { seen = {}, nodes = 0 }
    self.copyState.yieldIfNeeded = function(state)
        if ProfileNowMS() >= self.sliceDeadline then
            coroutine.yield(state.nodes)
        end
    end
    self.copyCoroutine = coroutine.create(function()
        return ClonePortable(entry.payload, limits, self.copyState)
    end)
end

function ParseJob:ResumePayloadCopy()
    local entry = self.package.modules[self.moduleIndex]
    if not entry then
        FinishParseTrace(self.stageTrace, "ok")
        self.stageTrace = nil
        self.parsed = NewParsedPackage(self.package, self.value, self.service.generation)
        self.classificationEntries, self.safePayloads = BuildClassificationInputs(
            self.service,
            self.package,
            self.safePayloads
        )
        self.moduleIndex = 1
        self.moduleCount = #self.classificationEntries
        self:BeginStage("classify", true)
        self.stage = "classify"
        self:EmitProgress("classify", 0.90, { moduleIndex = 0, moduleCount = self.moduleCount })
        self:Schedule()
        return
    end
    if not self.copyCoroutine then self:StartPayloadCopy(entry) end
    self.sliceDeadline = ProfileNowMS() + PARSE_SLICE_MS
    local resumed, portable = coroutine.resume(self.copyCoroutine)
    if not resumed then
        self:Finish(nil, "invalid_package", "error", portable)
        return
    end
    local state = self.copyState
    local currentRatio = math.min((state.nodes or 0) / math.max(self.copyLimits.maxNodes or MAX_NODES, 1), 0.99)
    local completed = (self.moduleIndex - 1) + currentRatio
    self:EmitProgress("portable-copy", 0.60 + (0.30 * completed / self.moduleCount), {
        processedNodes = state.nodes,
        moduleIndex = self.moduleIndex,
        moduleCount = self.moduleCount,
    })
    if coroutine.status(self.copyCoroutine) ~= "dead" then
        self:Schedule()
        return
    end
    self.safePayloads[self.moduleIndex] = portable
    self.copyCoroutine = nil
    self.copyState = nil
    self.copyLimits = nil
    self.moduleIndex = self.moduleIndex + 1
    self:Schedule()
end

function ParseJob:ResumeClassification()
    local deadline = ProfileNowMS() + PARSE_SLICE_MS
    repeat
        local entry = self.classificationEntries[self.moduleIndex]
        if not entry then
            local parsed = FinishParsedPackage(self.parsed)
            self.parsed = nil
            self:Finish(parsed)
            return
        end
        local portable = self.safePayloads[self.moduleIndex]
        if portable == MISSING_PORTABLE_PAYLOAD then portable = nil end
        local item = BuildParsedItem(self.service, self.package, entry, portable)
        self.parsed.modules[#self.parsed.modules + 1] = item
        self.parsed.byId[item.id] = item
        self.moduleIndex = self.moduleIndex + 1
        self:EmitProgress("classify", 0.90 + (0.09 * (self.moduleIndex - 1) / self.moduleCount), {
            moduleIndex = self.moduleIndex - 1,
            moduleCount = self.moduleCount,
        })
    until ProfileNowMS() >= deadline
    self:Schedule()
end

function ParseJob:RunStep()
    if self.finished then return end
    if self.stage == "decode" then
        self:BeginStage("decode", false)
        self:EmitProgress("decode", 0.03)
        local ok, compressed = pcall(LibDeflate.DecodeForPrint, LibDeflate, self.value:sub(#PREFIX + 1))
        FinishParseTrace(self.stageTrace, ok and compressed and "ok" or "error", ok and nil or compressed)
        self.stageTrace = nil
        if not ok or not compressed then self:Finish(nil, "decode_failed", "error", ok and nil or compressed); return end
        self.compressed = compressed
        self.stage = "decompress"
        self:EmitProgress("decode", 0.12)
        self:Schedule()
    elseif self.stage == "decompress" then
        self:BeginStage("decompress", false)
        self:EmitProgress("decompress", 0.12)
        local ok, serialized = pcall(LibDeflate.DecompressDeflate, LibDeflate, self.compressed, MAX_SERIALIZED_BYTES)
        FinishParseTrace(self.stageTrace, ok and serialized and "ok" or "error", ok and nil or serialized)
        self.stageTrace = nil
        self.compressed = nil
        if not ok or not serialized then self:Finish(nil, "decompress_failed", "error", ok and nil or serialized); return end
        self.serialized = serialized
        self.stage = "deserialize"
        self:EmitProgress("decompress", 0.28)
        self:Schedule()
    elseif self.stage == "deserialize" then
        self:BeginStage("deserialize", false)
        self:EmitProgress("deserialize", 0.28)
        local callOK, deserializeOK, package = pcall(Serializer.Deserialize, Serializer, self.serialized)
        FinishParseTrace(self.stageTrace, callOK and deserializeOK and type(package) == "table" and "ok" or "error", callOK and nil or deserializeOK)
        self.stageTrace = nil
        self.serialized = nil
        if not callOK or not deserializeOK or type(package) ~= "table" then
            self:Finish(nil, "deserialize_failed", "error", callOK and nil or deserializeOK)
            return
        end
        self.package = package
        self:EmitProgress("deserialize", 0.46)
        self:StartValidation()
        self:Schedule()
    elseif self.stage == "portable-validation" then
        self:ResumeValidation()
    elseif self.stage == "portable-copy" then
        self:ResumePayloadCopy()
    elseif self.stage == "classify" then
        self:ResumeClassification()
    else
        self:Finish(nil, "invalid_package")
    end
end

function ConfigTransfer:StartParseImportString(value, context, callbacks)
    RegisterAutomaticModules(self)
    callbacks = type(callbacks) == "table" and callbacks or {}
    local job = setmetatable({
        service = self,
        callbacks = callbacks,
        context = context,
        stage = "decode",
        progress = 0,
    }, ParseJob)
    job.overallTrace = BeginParseTrace("ConfigTransfer:parse", nil, {
        durationKind = "async",
        blocking = false,
    })
    if type(value) ~= "string" then
        job:Finish(nil, "empty_input")
        return job
    end
    value = value:match("^%s*(.-)%s*$") or ""
    if value == "" then job:Finish(nil, "empty_input"); return job end
    if #value > MAX_PRINT_BYTES then job:Finish(nil, "input_too_large"); return job end
    if value:sub(1, #PREFIX) ~= PREFIX then job:Finish(nil, "unsupported_prefix"); return job end
    job.value = value
    job:EmitProgress("input", 0.03)
    job:Schedule()
    return job
end

local function PrepareCheckpoint(work, phase, progress, extra)
    if type(work) == "table" and type(work.checkpoint) == "function" then
        work.checkpoint(phase, progress, extra)
    end
end

local function NewPortableCloneState(work, phase, baseProgress, progressSpan, maxNodes)
    local state = { seen = {}, nodes = 0 }
    if type(work) == "table" then
        state.yieldIfNeeded = function(current)
            local ratio = math.min((current.nodes or 0) / math.max(maxNodes or MAX_NODES, 1), 0.99)
            PrepareCheckpoint(work, phase, baseProgress + (progressSpan * ratio), {
                processedNodes = current.nodes,
            })
        end
    end
    return state
end

local function SnapshotStandard(definition, payload, includePersonalData, context, work)
    local productId = ResolveProductId(definition)
    local database, profileName, code = CurrentProfileIdentity(productId)
    if not database then return nil, code end
    local root = definition.kind == "component" and definition.dataRoot ~= "profile"
        and ((type(database.profile.Components) == "table" and database.profile.Components) or {})
        or database.profile
    local snapshot = {
        database = database,
        profileName = profileName,
        data = {},
        layouts = {},
        layoutPresent = {},
        enabled = nil,
    }
    for _, path in ipairs(definition.dataPaths) do
        local value = GetPath(root, path)
        if value ~= nil and type(definition.prepareStoredValue) == "function" then
            local ok, prepared, prepareCode, prepareDetail = pcall(
                definition.prepareStoredValue,
                path,
                value,
                {
                    action = "snapshot",
                    moduleId = definition.id,
                    productId = productId,
                    profileName = profileName,
                    options = context,
                }
            )
            if not ok then return nil, "snapshot_failed", prepared end
            if prepared == nil then
                return nil, prepareCode or "snapshot_failed", prepareDetail
            end
            snapshot.data[path] = prepared
        else
            local maxNodes = definition.maxPayloadNodes or MAX_NODES
            local cloned, cloneCode = ClonePortable(value, {
                maxNodes = maxNodes,
                maxDepth = MAX_DEPTH,
            }, NewPortableCloneState(work, "prepare-snapshot", 0.52, 0.18, maxNodes))
            if cloneCode then return nil, cloneCode end
            snapshot.data[path] = cloned
        end
    end
    local Layout = YUI.Layout
    for _, layoutId in ipairs(definition.layoutIds) do
        -- Runtime defaults may initialize profile data while calculating geometry.
        -- Snapshot only persisted placements, and own a copy for stale checks/rollback.
        local placement
        if Layout and Layout._private and Layout._private.GetSavedPlacement then
            placement = Layout._private.GetSavedPlacement(layoutId)
        elseif Layout and Layout.HasPlacement and Layout:HasPlacement(layoutId) then
            placement = Layout.GetPlacement and Layout:GetPlacement(layoutId) or nil
        end
        snapshot.layoutPresent[layoutId] = placement ~= nil
        local cloned, cloneCode = ClonePortable(placement, { maxNodes = MAX_NODES, maxDepth = MAX_DEPTH })
        if cloneCode then return nil, cloneCode end
        snapshot.layouts[layoutId] = cloned
    end
    if definition.kind == "component" and definition.manageFeatureState ~= false then
        local feature = YUI.Components and YUI.Components.features and YUI.Components.features[definition.featureKey]
        local store = YUI.Components and YUI.Components.GetStore and YUI.Components:GetStore(feature and feature.product)
        local stored = store and store[definition.featureKey]
        snapshot.enabled = stored == nil and feature and feature.default == true or stored == true
    end
    if includePersonalData then
        local personal = definition.personalData
        local ok, value, personalCode = pcall(
            personal.snapshot,
            personal,
            definition,
            context
        )
        if not ok or value == nil then return nil, personalCode or "personal_data_snapshot_failed" end
        snapshot.personalData = value
    end
    return snapshot
end

local function SameSnapshotValue(left, right, seen)
    if left == right then return true end
    if type(left) ~= 'table' or type(right) ~= 'table' then return false end
    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not SameSnapshotValue(value, right[key], seen) then return false end
    end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function CopyPreparedValue(value, work, state)
    if type(value) ~= "table" then return value end
    state = state or { seen = {}, count = 0 }
    if state.seen[value] then return state.seen[value] end
    local result = {}
    state.seen[value] = result
    for key, child in pairs(value) do
        state.count = state.count + 1
        if state.count % 256 == 0 then PrepareCheckpoint(work, "prepare-payload", 0.90) end
        result[key] = CopyPreparedValue(child, work, state)
    end
    return result
end

local function WriteLayoutPlacement(layoutId, placement, present)
    local Layout = YUI.Layout
    if not Layout then return nil, "layout_unavailable" end
    local private = Layout._private
    if present == false then
        if not (private and private.ClearSavedPlacement and private.ClearSavedPlacement(layoutId)) then
            return nil, "layout_clear_failed"
        end
        if Layout.frames and Layout.frames[layoutId] and Layout.RefreshFrame then
            Layout:RefreshFrame(layoutId)
        end
        return true
    end
    if type(placement) ~= "table" then return nil, "layout_apply_failed" end
    if Layout.frames and Layout.frames[layoutId] and Layout.SetPlacement then
        local ok, code = Layout:SetPlacement(layoutId, placement, true)
        if ok == false then return nil, code or "layout_apply_failed" end
        return true
    end
    if private and private.SavePlacement then
        private.SavePlacement(layoutId, placement)
        return true
    end
    return nil, "layout_apply_failed"
end

function ConfigTransfer:PrepareImport(parsed, moduleIds, context, work)
    RegisterAutomaticModules(self)
    if self.busy then
        return nil, "busy", ImportFailureDetail("prepare", nil, "busy")
    end
    if type(parsed) ~= "table" or parsed.registryGeneration ~= self.generation
        or type(moduleIds) ~= "table" or #moduleIds < 1 then
        local reason = type(parsed) == "table" and parsed.registryGeneration ~= self.generation
            and "registry_changed" or "invalid_plan_or_selection"
        return nil, "stale_preview", ImportFailureDetail("prepare", nil, reason, { writesStarted = false })
    end
    local prepared = { entries = {}, registryGeneration = self.generation, parsed = parsed }
    local previewProfile = type(context) == 'table' and context.previewNewProfile or nil
    if previewProfile ~= nil and (type(previewProfile) ~= 'string' or previewProfile == '') then
        return nil, 'invalid-profile-preview'
    end
    local seal = { entries = {}, previewOnly = previewProfile ~= nil }
    local selected = {}
    for _, id in ipairs(moduleIds) do selected[id] = true end
    for _, id in ipairs(moduleIds) do
        local definition = self.modules[id]
        for _, excluded in ipairs(definition and definition.exclusiveWith or {}) do
            if selected[excluded] then return nil, 'conflicting_selection',
                ImportFailureDetail('prepare', id, excluded) end
        end
    end
    local seen = {}
    local moduleCount = #moduleIds
    for moduleIndex, id in ipairs(moduleIds) do
        if type(work) == "table" then
            work.moduleIndex = moduleIndex
            work.moduleCount = moduleCount
        end
        PrepareCheckpoint(work, "prepare-payload", 0.02)
        local item = parsed.byId and parsed.byId[id]
        if not item or item.status ~= "ready" or seen[id] then
            return nil, "invalid_selection", ImportFailureDetail("prepare", id, "invalid_selection")
        end
        seen[id] = true
        local definition = item.definition
        local maxPayloadNodes = definition.maxPayloadNodes or MAX_NODES
        local payload, code = ClonePortable(item.rawPayload, {
            maxNodes = maxPayloadNodes,
            maxDepth = GetPayloadMaxDepth(definition),
        }, NewPortableCloneState(
            work,
            "prepare-payload",
            0.02,
            0.28,
            maxPayloadNodes
        ))
        if not payload then
            return nil, code, ImportFailureDetail("prepare", id, code)
        end
        PrepareCheckpoint(work, "prepare-normalize", 0.32)
        if item.schemaVersion < definition.schemaVersion then
            local callOK, migrated, migrateCode, migrateDetail = pcall(
                definition.migrate,
                payload,
                item.schemaVersion,
                definition.schemaVersion,
                context
            )
            if not callOK then
                return nil, "migration_failed", ImportFailureDetail("prepare", id, migrated)
            end
            payload, code = migrated, migrateCode
            if not payload then
                return nil, code or "migration_failed", ImportFailureDetail(
                    "prepare",
                    id,
                    migrateDetail or code
                )
            end
        end
        if type(definition.normalize) == "function" then
            local callOK, normalized, normalizeCode, normalizeDetail = pcall(
                definition.normalize,
                payload,
                context
            )
            if not callOK then
                return nil, "normalize_failed", ImportFailureDetail("prepare", id, normalized)
            end
            payload, code = normalized, normalizeCode
            if not payload then
                return nil, code or "normalize_failed", ImportFailureDetail(
                    "prepare",
                    id,
                    normalizeDetail or code
                )
            end
        elseif type(definition.apply) ~= "function" then
            payload, code = ValidateStandardPayload(definition, payload)
            if not payload then
                return nil, code or "invalid_module_payload", ImportFailureDetail("prepare", id, code)
            end
        end
        if type(definition.prepareStoredValue) == "function" then
            local productId = ResolveProductId(definition)
            local _, profileName = CurrentProfileIdentity(productId)
            for _, path in ipairs(definition.dataPaths) do
                if payload.present[path] == true and payload.data[path] ~= nil then
                    local callOK, preparedValue, prepareCode, prepareDetail = pcall(
                        definition.prepareStoredValue,
                        path,
                        payload.data[path],
                        {
                            action = "import",
                            moduleId = id,
                            productId = productId,
                            profileName = profileName,
                            options = context,
                        }
                    )
                    if not callOK then
                        return nil, "prepare_stored_failed", ImportFailureDetail(
                            "prepare",
                            id,
                            preparedValue
                        )
                    end
                    if preparedValue == nil then
                        return nil, prepareCode or "prepare_stored_failed",
                            ImportFailureDetail(
                                "prepare",
                                id,
                                prepareDetail or prepareCode
                            )
                    end
                    payload.data[path] = preparedValue
                end
            end
        end
        PrepareCheckpoint(work, "prepare-normalize", 0.50)
        local includePersonalData = payload.personalData ~= nil
            and PersonalDataSelected(context, "importPersonalData", id)
        if payload.personalData ~= nil then
            local personal = definition.personalData
            local callOK, normalized, normalizeCode, normalizeDetail = pcall(
                personal.normalize,
                payload.personalData.data,
                personal,
                definition,
                context
            )
            if not callOK then
                return nil, "personal_data_normalize_failed", ImportFailureDetail(
                    "prepare",
                    id,
                    normalized
                )
            end
            payload.personalData.data, code = normalized, normalizeCode
            if payload.personalData.data == nil then
                return nil, code or "personal_data_normalize_failed", ImportFailureDetail(
                    "prepare",
                    id,
                    normalizeDetail or code
                )
            end
        end
        local snapshot
        PrepareCheckpoint(work, "prepare-snapshot", 0.52)
        if type(definition.snapshot) == "function" then
            local callOK, captured, snapshotCode, snapshotDetail = pcall(
                definition.snapshot,
                definition,
                context,
                payload
            )
            if not callOK then
                return nil, "snapshot_failed", ImportFailureDetail("prepare", id, captured)
            end
            snapshot, code = captured, snapshotCode
            if not snapshot then
                return nil, code or "snapshot_failed", ImportFailureDetail(
                    "prepare",
                    id,
                    snapshotDetail or code
                )
            end
        elseif previewProfile then
            snapshot = { profileName = previewProfile }
        else
            snapshot, code = SnapshotStandard(
                definition,
                payload,
                includePersonalData,
                context,
                work
            )
        end
        if not snapshot then
            return nil, code or "snapshot_failed", ImportFailureDetail("prepare", id, code)
        end
        if previewProfile then snapshot.profileName = previewProfile end
        local configSetsPrepared
        PrepareCheckpoint(work, "prepare-config-sets", 0.72)
        if payload.configSets ~= nil and #definition.providerIds > 0 then
            local ConfigSets = S.ConfigSets
            if not (ConfigSets and ConfigSets.PrepareProfileStateImport) then
                return nil, "config_sets_unavailable", ImportFailureDetail(
                    "prepare",
                    id,
                    "config_sets_unavailable"
                )
            end
            local configSetsDetail
            configSetsPrepared, code, configSetsDetail = ConfigSets:PrepareProfileStateImport(
                ResolveProductId(definition),
                snapshot.profileName,
                payload.configSets,
                definition.providerIds,
                work
            )
            if not configSetsPrepared then
                return nil, code or "config_sets_prepare_failed", ImportFailureDetail(
                    "prepare",
                    id,
                    configSetsDetail or code
                )
            end
        end
        prepared.entries[#prepared.entries + 1] = {
            id = id, definition = definition, payload = payload, snapshot = snapshot,
            includePersonalData = includePersonalData,
            snapshotContext = context,
            configSetsPrepared = configSetsPrepared,
        }
        -- The provider may have converted validated portable data into binary
        -- storage strings. Seal that prepared representation without decoding it.
        local sealedPayload = CopyPreparedValue(payload, work)
        local snapshotFields = {}
        for key, value in pairs(snapshot) do snapshotFields[key] = value end
        seal.entries[id] = { entry = prepared.entries[#prepared.entries], payload = sealedPayload,
            definition = definition, snapshot = snapshot, snapshotFields = snapshotFields,
            configSetsPrepared = configSetsPrepared, includePersonalData = includePersonalData }
        PrepareCheckpoint(work, "prepare-module", 1)
    end
    table.sort(prepared.entries, function(left, right) return left.id < right.id end)
    seal.count = #prepared.entries
    preparedImports[prepared] = seal
    return prepared
end

local PrepareJob = {}
PrepareJob.__index = PrepareJob

function PrepareJob:EmitProgress(phase, progress, extra)
    if self.finished then return end
    local moduleIndex = self.work and self.work.moduleIndex or 1
    local moduleCount = math.max(self.work and self.work.moduleCount or 1, 1)
    local moduleProgress = math.max(0, math.min(tonumber(progress) or 0, 1))
    local overall = math.min(((moduleIndex - 1) + moduleProgress) / moduleCount, 1)
    overall = math.max(self.progress or 0, overall)
    self.progress = overall
    local detail = {
        phase = phase or "prepare-payload",
        progress = overall,
        processedNodes = extra and extra.processedNodes or nil,
        moduleIndex = moduleIndex,
        moduleCount = moduleCount,
    }
    local callback = self.callbacks and self.callbacks.onProgress
    if type(callback) == "function" then pcall(callback, detail) end
end

function PrepareJob:Cleanup()
    if self.timer and self.timer.Cancel then self.timer:Cancel() end
    self.timer = nil
    self.coroutine = nil
    self.work = nil
    self.parsed = nil
    self.moduleIds = nil
    self.context = nil
    self.service = nil
    self.callbacks = nil
end

function PrepareJob:Finish(prepared, code, diagnostic, status, err)
    if self.finished or self.finishing then return false end
    self.finishing = true
    if prepared then self:EmitProgress("prepare-complete", 1) end
    self.finished = true
    self.finishing = nil
    local traceStatus = status == "cancelled" and "skip" or status
    FinishParseTrace(
        self.trace,
        traceStatus or (prepared and "ok" or "error"),
        err or code
    )
    self.trace = nil
    local callback = self.callbacks and self.callbacks.onComplete
    self:Cleanup()
    if type(callback) == "function" and status ~= "cancelled" then
        pcall(callback, prepared, code, diagnostic)
    end
    return true
end

function PrepareJob:Cancel()
    if self.finished then return false end
    return self:Finish(nil, nil, nil, "cancelled")
end

function PrepareJob:Schedule()
    if self.finished or self.timer then return end
    if not (C_Timer and C_Timer.NewTimer) then
        self.synchronous = true
        while not self.finished do self:Resume() end
        return
    end
    self.timer = C_Timer.NewTimer(0, function()
        self.timer = nil
        if self.finished then return end
        local ok, err = pcall(self.Resume, self)
        if not ok then
            self:Finish(
                nil,
                "prepare_failed",
                ImportFailureDetail("prepare", nil, err),
                "error",
                err
            )
        end
    end)
end

function PrepareJob:Resume()
    if self.finished then return end
    self.deadline = ProfileNowMS() + PREPARE_SLICE_MS
    local resumed, first, second, third = coroutine.resume(self.coroutine)
    if not resumed then
        self:Finish(
            nil,
            "prepare_failed",
            ImportFailureDetail("prepare", nil, first),
            "error",
            first
        )
        return
    end
    if coroutine.status(self.coroutine) == "dead" then
        self:Finish(first, second, third)
        return
    end
    local detail = type(first) == "table" and first or {}
    self:EmitProgress(detail.phase, detail.progress, detail)
    self:Schedule()
end

function ConfigTransfer:StartPrepareImport(parsed, moduleIds, context, callbacks)
    RegisterAutomaticModules(self)
    callbacks = type(callbacks) == "table" and callbacks or {}
    local job = setmetatable({
        service = self,
        parsed = parsed,
        moduleIds = moduleIds,
        context = context,
        callbacks = callbacks,
        progress = 0,
    }, PrepareJob)
    job.trace = BeginParseTrace("ConfigTransfer:prepare", nil, {
        durationKind = "async",
        blocking = false,
    })
    job.work = {
        moduleIndex = 1,
        moduleCount = type(moduleIds) == "table" and #moduleIds or 1,
    }
    job.work.checkpoint = function(phase, progress, extra)
        if job.finished then return end
        if ProfileNowMS() >= (job.deadline or 0) then
            coroutine.yield({
                phase = phase,
                progress = progress,
                processedNodes = extra and extra.processedNodes or nil,
            })
        end
    end
    job.coroutine = coroutine.create(function()
        return self:PrepareImport(parsed, moduleIds, context, job.work)
    end)
    job:EmitProgress("prepare-payload", 0)
    job:Schedule()
    return job
end

local function ApplyStandard(entry)
    local definition, payload, snapshot = entry.definition, entry.payload, entry.snapshot
    local database, profileName = CurrentProfileIdentity(ResolveProductId(definition))
    if database ~= snapshot.database or profileName ~= snapshot.profileName then return nil, "profile_changed" end
    local root
    if definition.kind == "component" and definition.dataRoot ~= "profile" then
        database.profile.Components = type(database.profile.Components) == "table" and database.profile.Components or {}
        root = database.profile.Components
    else
        root = database.profile
    end
    for _, path in ipairs(definition.dataPaths) do
        if payload.present[path] == true then
            SetPath(root, path, payload.data[path])
        else
            SetPath(root, path, nil)
        end
    end
    local Layout = YUI.Layout
    for _, layoutId in ipairs(definition.layoutIds) do
        local placement = payload.layouts and payload.layouts[layoutId]
        local ok, code = WriteLayoutPlacement(layoutId, placement, payload.layoutPresent[layoutId])
        if not ok then return nil, code end
    end
    if entry.configSetsPrepared then
        local ok, code = S.ConfigSets:CommitProfileStateImport(entry.configSetsPrepared)
        if not ok then return nil, code or "config_sets_commit_failed" end
    end
    if entry.includePersonalData then
        local personal = definition.personalData
        local ok, code = personal.apply(payload.personalData.data, snapshot.personalData, entry)
        if not ok then return nil, code or "personal_data_apply_failed" end
    end
    return true
end

local function RestoreStandard(entry)
    local definition, snapshot = entry.definition, entry.snapshot
    local database = snapshot.database
    if type(database) ~= "table" or type(database.profile) ~= "table" then return nil, "profile_changed" end
    local root
    if definition.kind == "component" and definition.dataRoot ~= "profile" then
        database.profile.Components = type(database.profile.Components) == "table" and database.profile.Components or {}
        root = database.profile.Components
    else
        root = database.profile
    end
    for _, path in ipairs(definition.dataPaths) do SetPath(root, path, snapshot.data[path]) end
    for _, layoutId in ipairs(definition.layoutIds) do
        local placement = snapshot.layouts[layoutId]
        local ok = WriteLayoutPlacement(layoutId, placement, snapshot.layoutPresent[layoutId])
        if not ok then return nil, "layout_restore_failed" end
    end
    if entry.configSetsPrepared and entry.configSetsPrepared.committed == true
        and S.ConfigSets and S.ConfigSets.RestoreProfileStateImport then
        local ok = S.ConfigSets:RestoreProfileStateImport(entry.configSetsPrepared)
        if not ok then return nil, "config_sets_restore_failed" end
    end
    if entry.includePersonalData then
        local ok, code = definition.personalData.restore(snapshot.personalData, entry)
        if not ok then return nil, code or "personal_data_restore_failed" end
    end
    return true
end

function ConfigTransfer:MatchesNewProfilePreview(preview, prepared)
    local reviewed, actual = preparedImports[preview], preparedImports[prepared]
    if not reviewed or not reviewed.previewOnly or not actual or actual.previewOnly
        or reviewed.count ~= actual.count or preview.registryGeneration ~= self.generation then
        return false, ImportFailureDetail("prepare", nil, "preview_changed", { writesStarted = false })
    end
    for id, entry in pairs(reviewed.entries) do
        local other = actual.entries[id]
        if not other or entry.definition ~= other.definition
            or entry.includePersonalData ~= other.includePersonalData
            or entry.snapshotFields.mode ~= other.snapshotFields.mode
            or not SameSnapshotValue(entry.payload, other.payload) then
            return false, ImportFailureDetail("prepare", id, "preview_payload_changed", { writesStarted = false })
        end
    end
    return true
end

local function RejectImportCommit(code, moduleId, reason, changedField)
    return nil, code, ImportFailureDetail("commit", moduleId, reason or code, {
        writesStarted = false,
        changedField = changedField,
    })
end

function ConfigTransfer:CommitImport(prepared, owner)
    if self.busy then
        return RejectImportCommit("busy")
    end
    if type(prepared) ~= "table" or prepared.registryGeneration ~= self.generation
        or type(prepared.entries) ~= "table" or #prepared.entries < 1 then
        local reason = type(prepared) == "table" and prepared.registryGeneration ~= self.generation
            and "registry_changed" or "prepared_plan_changed"
        return RejectImportCommit("stale_preview", nil, reason)
    end
    if InCombatLockdown and InCombatLockdown() then
        return RejectImportCommit("combat_lockdown")
    end
    local seal = preparedImports[prepared]
    if seal and seal.previewOnly then return RejectImportCommit("preview-only") end
    if not seal or seal.consumed or seal.count ~= #prepared.entries then
        return RejectImportCommit("stale_preview", nil, "prepared_plan_changed")
    end
    local seenEntries = {}
    for _, entry in ipairs(prepared.entries) do
        local original = seal.entries[entry.id]
        if not original or seenEntries[entry.id] or original.entry ~= entry
            or original.definition ~= entry.definition or original.snapshot ~= entry.snapshot
            or original.configSetsPrepared ~= entry.configSetsPrepared
            or original.includePersonalData ~= entry.includePersonalData
            or not SameSnapshotValue(original.payload, entry.payload) then
            return RejectImportCommit("stale_preview", entry.id, "prepared_entry_changed")
        end
        seenEntries[entry.id] = true
        for key, value in pairs(original.snapshotFields) do
            if entry.snapshot[key] ~= value then return RejectImportCommit("stale_preview", entry.id, "prepared_snapshot_changed", key) end
        end
        for key in pairs(entry.snapshot) do
            if original.snapshotFields[key] == nil then return RejectImportCommit("stale_preview", entry.id, "prepared_snapshot_changed", key) end
        end
    end
    -- Validate every selected participant before the first write. Individual
    -- apply callbacks validate again if preceding participants changed state.
    for _,entry in ipairs(prepared.entries) do
        local database, profileName = CurrentProfileIdentity(ResolveProductId(entry.definition))
        if database ~= entry.snapshot.database or profileName ~= entry.snapshot.profileName then
            return RejectImportCommit('profile_changed', entry.id)
        end
        if type(entry.definition.validateSnapshot)=='function' then
            local called,valid,code=pcall(entry.definition.validateSnapshot,entry.snapshot,entry)
            if not called or valid~=true then
                return RejectImportCommit('stale_preview', entry.id, called and code or valid)
            end
        elseif type(entry.definition.snapshot)~='function' then
            local called,current,code=pcall(SnapshotStandard,entry.definition,entry.payload,
                entry.includePersonalData,entry.snapshotContext)
            if not called or not current then
                return RejectImportCommit('stale_preview', entry.id, called and code or current or 'snapshot_failed')
            end
            for _,key in ipairs({'data','layouts','layoutPresent','enabled','personalData'}) do
                if not SameSnapshotValue(current[key],entry.snapshot[key]) then
                    return RejectImportCommit('stale_preview', entry.id, 'target_changed', key)
                end
            end
        end
        if entry.configSetsPrepared and S.ConfigSets.ValidateProfileStateImport then
            local valid,code=S.ConfigSets:ValidateProfileStateImport(entry.configSetsPrepared)
            if not valid then return RejectImportCommit('stale_preview', entry.id, code) end
        end
    end
    local overallTrace = BeginParseTrace("ConfigTransfer:commit", nil, {
        durationKind = "sync",
        blocking = true,
    })
    local function BeginCommitStage(name, moduleId)
        return BeginParseTrace("ConfigTransfer:commit:" .. name, nil, {
            moduleId = moduleId,
            durationKind = "sync",
            blocking = true,
        })
    end
    local function FinishCommit(status, err)
        FinishParseTrace(overallTrace, status, err)
        overallTrace = nil
    end
    seal.consumed = true
    self.busy = true
    local applied = {}
    local function Rollback(code, moduleId, reason)
        local rollbackTrace = BeginCommitStage("rollback", moduleId)
        local restored = true
        local rollbackModuleId
        local rollbackReason
        local function RecordRollbackFailure(entry, value)
            restored = false
            if not rollbackModuleId then
                rollbackModuleId = entry and entry.id or moduleId
                rollbackReason = NormalizeDiagnosticReason(value) or "rollback_failed"
            end
        end
        for index = #applied, 1, -1 do
            local entry = applied[index]
            local callOK, result, restoreCode, restoreDetail
            if type(entry.definition.restore) == "function" then
                callOK, result, restoreCode, restoreDetail = pcall(
                    entry.definition.restore,
                    entry.snapshot,
                    entry
                )
            else
                callOK, result, restoreCode, restoreDetail = pcall(RestoreStandard, entry)
            end
            if not callOK then
                RecordRollbackFailure(entry, result)
            elseif result == false or result == nil then
                RecordRollbackFailure(entry, restoreDetail or restoreCode)
            end
        end
        for index = #applied, 1, -1 do
            local entry = applied[index]
            if entry.definition.kind == "component"
                and entry.definition.manageFeatureState ~= false then
                local Components = YUI.Components
                local callOK, result = pcall(function()
                    return Components and Components.SetFeatureEnabled
                        and Components:SetFeatureEnabled(entry.definition.featureKey, entry.snapshot.enabled == true, {
                        suppressReload = true,
                    })
                end)
                local componentReason = not callOK and result
                    or (Components and Components.initializedFeatureErrors
                        and Components.initializedFeatureErrors[entry.definition.featureKey])
                if not callOK or result == false or result == nil
                    or componentReason then
                    RecordRollbackFailure(entry, componentReason or "component_lifecycle_restore_failed")
                end
            end
        end
        for index = #applied, 1, -1 do
            local entry = applied[index]
            if type(entry.definition.refresh) == "function" then
                local callOK, result, refreshCode, refreshDetail = pcall(
                    entry.definition.refresh,
                    entry,
                    owner,
                    "rollback"
                )
                if not callOK then
                    RecordRollbackFailure(entry, result)
                elseif result == false then
                    RecordRollbackFailure(entry, refreshDetail or refreshCode)
                end
            end
        end
        self.busy = false
        FinishParseTrace(
            rollbackTrace,
            restored and "ok" or "error",
            restored and nil or rollbackReason
        )
        FinishCommit("error", reason or code)
        if restored then
            return nil, code, ImportFailureDetail("commit", moduleId, reason, {
                rollbackRestored = true,
            })
        end
        return nil, "rollback_failed", ImportFailureDetail(
            "rollback",
            rollbackModuleId or moduleId,
            rollbackReason,
            {
                rollbackRestored = false,
                originalCode = code,
                originalPhase = "commit",
                originalModuleId = moduleId,
                originalReason = NormalizeDiagnosticReason(reason),
            }
        )
    end
    for _, entry in ipairs(prepared.entries) do
        local database, profileName = CurrentProfileIdentity(ResolveProductId(entry.definition))
        if database ~= entry.snapshot.database or profileName ~= entry.snapshot.profileName then
            return Rollback("profile_changed", entry.id, "profile_changed")
        end
        applied[#applied + 1] = entry
        local stageTrace = BeginCommitStage("apply", entry.id)
        local callOK, result, code, detail
        if type(entry.definition.apply) == "function" then
            callOK, result, code, detail = pcall(entry.definition.apply, entry.payload, entry)
        else
            callOK, result, code, detail = pcall(ApplyStandard, entry)
        end
        FinishParseTrace(
            stageTrace,
            callOK and result ~= false and result ~= nil and "ok" or "error",
            callOK and (detail or code) or result
        )
        if not callOK then
            return Rollback("apply_failed", entry.id, result)
        end
        if result == false or result == nil then
            return Rollback(code or "apply_failed", entry.id, detail or code)
        end
    end
    for _, entry in ipairs(prepared.entries) do
        if entry.definition.kind == "component"
            and entry.definition.manageFeatureState ~= false then
            local stageTrace = BeginCommitStage("lifecycle", entry.id)
            local Components = YUI.Components
            local enabled = entry.payload.enabled == true
            local callOK, result = pcall(function()
                return Components and Components.SetFeatureEnabled
                    and Components:SetFeatureEnabled(entry.definition.featureKey, enabled, { suppressReload = true })
            end)
            local componentReason = not callOK and result
                or (Components and Components.initializedFeatureErrors
                    and Components.initializedFeatureErrors[entry.definition.featureKey])
            FinishParseTrace(
                stageTrace,
                callOK and result ~= false and result ~= nil
                    and not componentReason and "ok" or "error",
                componentReason
            )
            if not callOK or result == false or result == nil
                or componentReason then
                return Rollback(
                    "component_lifecycle_failed",
                    entry.id,
                    componentReason or "component_lifecycle_failed"
                )
            end
        end
    end
    for _, entry in ipairs(prepared.entries) do
        if type(entry.definition.refresh) == "function" then
            local stageTrace = BeginCommitStage("refresh", entry.id)
            local callOK, result, refreshCode, refreshDetail = pcall(
                entry.definition.refresh,
                entry,
                owner
            )
            FinishParseTrace(
                stageTrace,
                callOK and result ~= false and "ok" or "error",
                callOK and (refreshDetail or refreshCode) or result
            )
            if not callOK then
                return Rollback("refresh_failed", entry.id, result)
            end
            if result == false then
                return Rollback("refresh_failed", entry.id, refreshDetail or refreshCode)
            end
        end
    end
    if YUI.Event and YUI.Event.Emit then
        local stageTrace = BeginCommitStage("broadcast")
        local ids = {}
        local requiresReload = false
        for _, entry in ipairs(prepared.entries) do
            ids[#ids + 1] = entry.id
            requiresReload = requiresReload or entry.definition.requiresReload == true
        end
        local callOK, result = pcall(YUI.Event.Emit, YUI.Event, "YUI_CONFIG_TRANSFER_COMPLETED", ids, {
            requiresReload = requiresReload,
        })
        FinishParseTrace(stageTrace, callOK and "ok" or "error", callOK and nil or result)
        if not callOK then return Rollback("broadcast_failed", nil, result) end
    end
    self.busy = false
    local requiresReload = false
    for _, entry in ipairs(prepared.entries) do requiresReload = requiresReload or entry.definition.requiresReload == true end
    local result = { moduleCount = #prepared.entries, requiresReload = requiresReload }
    local completions = {}
    for _, entry in ipairs(prepared.entries) do
        if type(entry.definition.showCompletion) == "function" then
            completions[#completions + 1] = entry
        end
    end
    if #completions > 0 then
        result.showCompletion = function()
            local pending = completions
            completions = nil
            if not pending then return false end
            for _, participant in ipairs(pending) do
                local ok, shown = pcall(participant.definition.showCompletion, participant, owner)
                if ok and shown == true then return true end
            end
            return false
        end
    end
    FinishCommit("ok")
    return true, result
end

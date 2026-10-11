local YUI = _G.YUI
if not YUI then return end

local YHUD = YUI.YHUD
if not YHUD then return end

local Catalog = YHUD.ResourceCatalog or {}
YHUD.ResourceCatalog = Catalog

local UnitAPI = YUI.API and YUI.API.Unit or {}
local TalentAPI = YUI.API and YUI.API.Talent or {}
local SpellAPI = YUI.API and YUI.API.Spell or {}
local DEFINITIONS = YHUD.ResourceDefinitions or {}
local DEFINITION_IDS = YHUD.ResourceDefinitionIds or {}

local PRESETS = {}
local CLASS_CONTEXTS = {}

local function ResourceConfig(profile)
    if type(profile) == "table" and type(profile.resources) ~= "table" then
        profile.resources = {}
    end
    return YHUD:GetResourceConfig(profile)
end

local function NormalizeClassFile(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    return string.upper(classFile)
end

local function NormalizeSpecID(specID)
    specID = tonumber(specID)
    if not specID or specID <= 0 then return nil end
    return math.floor(specID)
end

function Catalog:RegisterClassPack(classFile, specs, context)
    classFile = NormalizeClassFile(classFile)
    if not classFile or type(specs) ~= "table" then
        return nil, "invalid-class-pack"
    end
    if PRESETS[classFile] ~= nil then
        return nil, "duplicate-class-pack"
    end

    local normalized = {}
    for rawSpecID, resourceIds in pairs(specs) do
        local specID = NormalizeSpecID(rawSpecID)
        if not specID or type(resourceIds) ~= "table" then
            return nil, "invalid-class-pack"
        end
        local registered = {}
        local seen = {}
        for index = 1, #resourceIds do
            local resourceId = resourceIds[index]
            if not DEFINITIONS[resourceId] or seen[resourceId] then
                return nil, "invalid-class-pack"
            end
            seen[resourceId] = true
            registered[index] = resourceId
        end
        for _, resourceId in ipairs(YHUD.ResourceCommonCandidateIds or {}) do
            if not seen[resourceId] then registered[#registered + 1] = resourceId end
        end
        normalized[specID] = registered
    end

    if context ~= nil and type(context) ~= "table" then
        return nil, "invalid-class-context"
    end
    PRESETS[classFile] = normalized
    if context and context.specs then
        for _, forms in pairs(context.specs) do
            for _, form in pairs(forms) do
                for _, resourceId in ipairs(YHUD.ResourceCommonCandidateIds or {}) do
                    local found = false
                    for _, candidate in ipairs(form.candidates) do
                        if candidate == resourceId then found = true break end
                    end
                    if not found then form.candidates[#form.candidates + 1] = resourceId end
                end
            end
        end
    end
    CLASS_CONTEXTS[classFile] = context
    return true
end

local function GetSpecSelection(profile, classFile, specID)
    local resources = ResourceConfig(profile)
    local bySpec = type(resources) == "table" and resources.bySpec or nil
    local classSelection = type(bySpec) == "table" and bySpec[classFile] or nil
    if type(classSelection) ~= "table" then return nil end
    return classSelection[tostring(specID)] or classSelection[specID]
end

local function GetSpecOrder(profile, classFile, specID)
    local resources = ResourceConfig(profile)
    local bySpec = type(resources) == "table" and resources.orderBySpec or nil
    local classOrder = type(bySpec) == "table" and bySpec[classFile] or nil
    if type(classOrder) ~= "table" then return nil end
    return classOrder[tostring(specID)] or classOrder[specID]
end

local function HasPresetResource(classFile, specID, resourceId)
    local classPresets = PRESETS[classFile]
    local presetIds = classPresets and classPresets[specID]
    if not presetIds then return false end
    for index = 1, #presetIds do
        if presetIds[index] == resourceId then return true end
    end
    return false
end

local function CopyDefinition(definition, classFile, specID, enabled)
    local sourceProvider = definition.provider
    local provider = {
        kind = sourceProvider and sourceProvider.kind or "unit-power",
    }
    if sourceProvider then
        for key, value in pairs(sourceProvider) do provider[key] = value end
    end
    local specProvider = type(definition.providerBySpec) == "table"
        and definition.providerBySpec[specID] or nil
    if specProvider then
        for key, value in pairs(specProvider) do provider[key] = value end
    end
    return {
        id = definition.id,
        sourceKey = Catalog:BuildSourceKey(classFile, specID, definition.id),
        classFile = classFile,
        specID = specID,
        powerType = definition.powerType,
        powerToken = definition.powerToken,
        nameKey = definition.nameKey,
        descriptionKey = definition.descriptionKey,
        provider = provider,
        valueKind = definition.valueKind,
        previewMax = definition.previewMax,
        previewValueMax = definition.previewValueMax,
        appearanceExtension = definition.appearanceExtension,
        segmentCountFallback = definition.segmentCountFallback,
        defaultValueText = definition.defaultValueText ~= false,
        defaultValueFormat = definition.defaultValueFormat,
        color = {
            definition.color[1],
            definition.color[2],
            definition.color[3],
            definition.color[4],
        },
        enabled = enabled == true,
    }
end

local function CopyInitialDefinition(definition, classFile)
    local copied = CopyDefinition(definition, classFile, nil, true)
    copied.specID = nil
    copied.sourceKey = string.format(
        "resource-initial:%s:%s",
        classFile,
        definition.id
    )
    return copied
end

function Catalog:IsDefinitionAvailable(definition)
    local provider = definition and definition.provider
    local spellID = provider and provider.requiresKnownSpellID
    if not spellID then return true end
    if not SpellAPI.IsKnownOrInSpellBook then return false end
    return SpellAPI.IsKnownOrInSpellBook(spellID) == true
end

function Catalog:BuildSourceKey(classFile, specID, resourceId)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    if not classFile or not specID or not DEFINITIONS[resourceId] then return nil end
    local provider = DEFINITIONS[resourceId].provider
    if provider and provider.kind == "swing-timer" then
        return "swing:player:" .. provider.swingHand
    end
    return string.format("resource:%s:%d:%s", classFile, specID, resourceId)
end

function Catalog:GetDefinition(resourceId)
    return DEFINITIONS[resourceId]
end

function Catalog:GetDefinitionIds(target)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end
    for index = 1, #DEFINITION_IDS do
        target[index] = DEFINITION_IDS[index]
    end
    return target
end

function Catalog:GetPresetIds(classFile, specID)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local classPresets = classFile and PRESETS[classFile]
    return classPresets and classPresets[specID] or nil
end

local function BuildOrderedPresetIds(presetIds, custom, target)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end
    if type(presetIds) ~= "table" then return target end

    local allowed = {}
    for index = 1, #presetIds do allowed[presetIds[index]] = true end
    local seen = {}
    if type(custom) == "table" then
        for index = 1, #custom do
            local resourceId = custom[index]
            if allowed[resourceId] and not seen[resourceId] then
                seen[resourceId] = true
                target[#target + 1] = resourceId
            end
        end
    end
    for index = 1, #presetIds do
        local resourceId = presetIds[index]
        if not seen[resourceId] then
            seen[resourceId] = true
            target[#target + 1] = resourceId
        end
    end
    return target
end

local function PairEnabled(profile)
    return YUI.IsForever == true and profile and profile._yhudHandPairMode == "split"
end

local function ExpandHandOrder(order)
    local expanded = {}
    for _, id in ipairs(order) do
        if id == "swingHands" then
            expanded[#expanded + 1] = "swingMainHand"
            expanded[#expanded + 1] = "swingOffHand"
        else
            expanded[#expanded + 1] = id
        end
    end
    return expanded
end

local function FoldHandOrder(order)
    local folded, found = {}, false
    for _, id in ipairs(order) do
        if id == "swingMainHand" or id == "swingOffHand" then
            if not found then folded[#folded + 1], found = "swingHands", true end
        else
            folded[#folded + 1] = id
        end
    end
    return folded
end

local function CanonicalHandOrder(profile, order)
    if not PairEnabled(profile) then return order end
    return ExpandHandOrder(FoldHandOrder(order))
end

-- Settings rows collapse the two logical sources; runtime presets stay separate.
function Catalog:GetDisplayPresets(profile, presets)
    if not PairEnabled(profile) then return presets end
    local rows, pair = {}, nil
    for _, preset in ipairs(presets) do
        if preset.id == "swingMainHand" or preset.id == "swingOffHand" then
            if not pair then
                pair = YHUD:CopyValue(preset)
                pair.id, pair.nameKey, pair.styleResourceId = "swingHands", "resource.swing_hands", "swingMainHand"
                pair.enabled = false
                rows[#rows + 1] = pair
            end
            pair.enabled = pair.enabled or preset.enabled == true
        else
            rows[#rows + 1] = preset
        end
    end
    return rows
end

function Catalog:GetOrderedPresetIds(profile, classFile, specID, target)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local presetIds = self:GetPresetIds(classFile, specID)
    return CanonicalHandOrder(profile, BuildOrderedPresetIds(
        presetIds,
        GetSpecOrder(profile, classFile, specID),
        target
    ))
end

local function OrdersEqual(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function GetFormDefinition(classFile, specID, formKey)
    local context = CLASS_CONTEXTS[classFile]
    local specForms = context and context.specs and context.specs[specID]
    return specForms and specForms[formKey] or nil, context
end

local function BuildDefaultEnabled(formDefinition)
    local enabled = {}
    for index = 1, #(formDefinition and formDefinition.defaults or {}) do
        enabled[formDefinition.defaults[index]] = true
    end
    return enabled
end

local function GetFormOverride(profile, classFile, specID, formKey)
    local resources = ResourceConfig(profile)
    local byClass = resources and type(resources.formOverrides) == "table"
        and resources.formOverrides[classFile] or nil
    local bySpec = type(byClass) == "table"
        and (byClass[tostring(specID)] or byClass[specID]) or nil
    return type(bySpec) == "table" and bySpec[formKey] or nil
end

local function BuildFormState(profile, classFile, specID, formKey)
    local definition = GetFormDefinition(classFile, specID, formKey)
    if not definition then return nil end
    local override = GetFormOverride(profile, classFile, specID, formKey)
    local order = CanonicalHandOrder(profile, BuildOrderedPresetIds(
        definition.candidates,
        type(override) == "table" and override.order or nil
    ))
    local defaultEnabled = BuildDefaultEnabled(definition)
    local enabled = {}
    local customEnabled = type(override) == "table"
        and type(override.enabled) == "table" and override.enabled or nil
    for index = 1, #definition.candidates do
        local resourceId = definition.candidates[index]
        local explicit = customEnabled and customEnabled[resourceId]
        if type(explicit) == "boolean" then
            enabled[resourceId] = explicit
        else
            enabled[resourceId] = ResourceConfig(profile).selectionDefault ~= "none"
                and defaultEnabled[resourceId] == true
        end
    end
    return {
        definition = definition,
        order = order,
        enabled = enabled,
        customized = type(override) == "table",
        selectionDefault = ResourceConfig(profile).selectionDefault,
    }
end

local function FormStateIsDefault(state)
    if not state or not OrdersEqual(state.order, state.definition.candidates) then
        return false
    end
    local defaults = state.selectionDefault == "none" and {}
        or BuildDefaultEnabled(state.definition)
    for index = 1, #state.definition.candidates do
        local resourceId = state.definition.candidates[index]
        if state.enabled[resourceId] ~= (defaults[resourceId] == true) then
            return false
        end
    end
    return true
end

local function PruneFormOverride(resources, classFile, specID, formKey)
    local all = resources and resources.formOverrides
    local byClass = type(all) == "table" and all[classFile] or nil
    local specKey = tostring(specID)
    local bySpec = type(byClass) == "table" and byClass[specKey] or nil
    if type(bySpec) ~= "table" then return end
    bySpec[formKey] = nil
    if next(bySpec) == nil then byClass[specKey] = nil end
    if next(byClass) == nil then all[classFile] = nil end
end

local function StoreFormState(profile, classFile, specID, formKey, state)
    local resources = ResourceConfig(profile)
    resources.formOverrides = type(resources.formOverrides) == "table"
        and resources.formOverrides or {}
    if FormStateIsDefault(state) then
        PruneFormOverride(resources, classFile, specID, formKey)
        return state
    end
    local byClass = type(resources.formOverrides[classFile]) == "table"
        and resources.formOverrides[classFile] or {}
    resources.formOverrides[classFile] = byClass
    local specKey = tostring(specID)
    local bySpec = type(byClass[specKey]) == "table" and byClass[specKey] or {}
    byClass[specKey] = bySpec
    local enabled = {}
    for index = 1, #state.definition.candidates do
        local resourceId = state.definition.candidates[index]
        enabled[resourceId] = state.enabled[resourceId] == true
    end
    local order = {}
    for index = 1, #state.order do order[index] = state.order[index] end
    bySpec[formKey] = { enabled = enabled, order = order }
    return state
end

function Catalog:GetFormOptions(classFile, specID, target)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end
    local context = classFile and CLASS_CONTEXTS[classFile]
    local forms = context and context.specs and context.specs[specID]
    if not forms then return target end
    for index = 1, #(context.formOrder or {}) do
        local formKey = context.formOrder[index]
        if forms[formKey] then
            target[#target + 1] = {
                key = formKey,
                nameKey = context.formNameKeys and context.formNameKeys[formKey],
            }
        end
    end
    return target
end

function Catalog:GetDefaultFormKey(classFile, specID)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local context = classFile and CLASS_CONTEXTS[classFile]
    return context and context.defaultFormBySpec
        and context.defaultFormBySpec[specID] or nil
end

function Catalog:ResolveFormKey(classFile, specID, formID, powerType)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local context = classFile and CLASS_CONTEXTS[classFile]
    if not context then return nil end
    local formKey = context.resolveForm
        and context.resolveForm(formID, powerType) or nil
    local definition = formKey and GetFormDefinition(classFile, specID, formKey)
    if definition then return formKey end
    return self:GetDefaultFormKey(classFile, specID)
end

function Catalog:GetCurrentFormKey(classFile, specID)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local formID = UnitAPI.GetPlayerShapeshiftFormID
        and UnitAPI.GetPlayerShapeshiftFormID() or nil
    local powerType = UnitAPI.GetPowerType and UnitAPI.GetPowerType("player") or nil
    return self:ResolveFormKey(classFile, specID, formID, powerType)
end

function Catalog:GetFormPresets(profile, classFile, specID, formKey, target)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end
    local state = BuildFormState(profile, classFile, specID, formKey)
    if not state then return target end
    for index = 1, #state.order do
        local resourceId = state.order[index]
        target[#target + 1] = CopyDefinition(
            DEFINITIONS[resourceId],
            classFile,
            specID,
            state.enabled[resourceId] == true
        )
    end
    return target
end

function Catalog:GetEnabledFormPresets(profile, classFile, specID, formKey, target)
    local presets = self:GetFormPresets(profile, classFile, specID, formKey, target)
    local writeIndex = 1
    for readIndex = 1, #presets do
        if presets[readIndex].enabled then
            presets[writeIndex] = presets[readIndex]
            writeIndex = writeIndex + 1
        end
    end
    for index = #presets, writeIndex, -1 do presets[index] = nil end
    return presets
end

function Catalog:GetPreviewPresets(profile, classFile, specID, formKey, target)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    if CLASS_CONTEXTS[classFile] then
        formKey = GetFormDefinition(classFile, specID, formKey)
            and formKey or self:GetDefaultFormKey(classFile, specID)
        return self:GetEnabledFormPresets(
            profile,
            classFile,
            specID,
            formKey,
            target
        )
    end
    return self:GetEnabledPresets(profile, classFile, specID, target)
end

function Catalog:GetEligiblePresets(profile, classFile, specID, target)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local presets
    if not CLASS_CONTEXTS[classFile] then
        presets = self:GetEnabledPresets(profile, classFile, specID, target)
    else
        target = type(target) == "table" and target or {}
        for index = #target, 1, -1 do target[index] = nil end
        local enabled = {}
        for _, form in ipairs(self:GetFormOptions(classFile, specID)) do
            local state = BuildFormState(profile, classFile, specID, form.key)
            if state then
                for id, selected in pairs(state.enabled) do
                    if selected then enabled[id] = true end
                end
            end
        end
        local presetIds = self:GetOrderedPresetIds(profile, classFile, specID)
        for index = 1, #presetIds do
            local resourceId = presetIds[index]
            if enabled[resourceId] then target[#target + 1] = CopyDefinition(
                DEFINITIONS[resourceId],
                classFile,
                specID,
                true
            ) end
        end
        presets = target
    end
    local writeIndex = 1
    for readIndex = 1, #presets do
        if self:IsDefinitionAvailable(presets[readIndex]) then
            presets[writeIndex] = presets[readIndex]
            writeIndex = writeIndex + 1
        end
    end
    for index = #presets, writeIndex, -1 do presets[index] = nil end
    return presets
end

function Catalog:IsFormCustomized(profile, classFile, specID, formKey)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    return type(GetFormOverride(profile, classFile, specID, formKey)) == "table"
end

function Catalog:SetFormPresetEnabled(
    profile,
    classFile,
    specID,
    formKey,
    resourceId,
    enabled
)
    if resourceId == "swingHands" and PairEnabled(profile) then
        local ok, code = self:SetFormPresetEnabled(profile, classFile, specID, formKey, "swingMainHand", enabled)
        if not ok then return nil, code end
        return self:SetFormPresetEnabled(profile, classFile, specID, formKey, "swingOffHand", enabled)
    end
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local state = BuildFormState(profile, classFile, specID, formKey)
    if type(profile) ~= "table" or not state
        or state.enabled[resourceId] == nil or type(enabled) ~= "boolean" then
        return nil, "unknown-form-resource-preset"
    end
    state.enabled[resourceId] = enabled
    StoreFormState(profile, classFile, specID, formKey, state)
    return true
end

function Catalog:MoveFormPreset(
    profile,
    classFile,
    specID,
    formKey,
    resourceId,
    targetIndex,
    enabledOnly
)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local state = BuildFormState(profile, classFile, specID, formKey)
    if type(profile) ~= "table" or not state then
        return nil, "unknown-form-resource-preset"
    end
    if PairEnabled(profile) then
        state.order = FoldHandOrder(state.order)
        if resourceId == "swingMainHand" or resourceId == "swingOffHand" then resourceId = "swingHands" end
    end
    local sourceIndex
    for index = 1, #state.order do
        if state.order[index] == resourceId then sourceIndex = index break end
    end
    if not sourceIndex then return nil, "unknown-form-resource-preset" end
    table.remove(state.order, sourceIndex)
    if enabledOnly == true then
        local selected = {}
        for _, id in ipairs(state.order) do
            if state.enabled[id] == true or (id == "swingHands"
                and (state.enabled.swingMainHand or state.enabled.swingOffHand)) then
                selected[#selected + 1] = id
            end
        end
        local position = math.max(1, math.min(#selected + 1, math.floor(tonumber(targetIndex) or 1)))
        local beforeId, afterId = selected[position], selected[#selected]
        targetIndex = #state.order + 1
        for index, id in ipairs(state.order) do
            if beforeId and id == beforeId then targetIndex = index break end
            if not beforeId and id == afterId then targetIndex = index + 1 end
        end
    end
    targetIndex = math.max(
        1,
        math.min(#state.order + 1, math.floor(tonumber(targetIndex) or sourceIndex))
    )
    table.insert(state.order, targetIndex, resourceId)
    if PairEnabled(profile) then state.order = ExpandHandOrder(state.order) end
    StoreFormState(profile, classFile, specID, formKey, state)
    return state.order
end

function Catalog:ResetFormOverride(profile, classFile, specID, formKey)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    if type(profile) ~= "table" or not GetFormDefinition(classFile, specID, formKey) then
        return nil, "unknown-resource-form"
    end
    local resources = ResourceConfig(profile)
    resources.formOverrides = type(resources.formOverrides) == "table"
        and resources.formOverrides or {}
    PruneFormOverride(resources, classFile, specID, formKey)
    return true
end

local function PruneOrderStorage(resources, classFile, specKey)
    local orderBySpec = resources.orderBySpec
    local classOrder = orderBySpec and orderBySpec[classFile]
    if type(classOrder) ~= "table" then return end
    classOrder[specKey] = nil
    if next(classOrder) == nil then orderBySpec[classFile] = nil end
end

function Catalog:SetPresetOrder(profile, classFile, specID, order)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local defaults = self:GetPresetIds(classFile, specID)
    if not defaults or type(profile) ~= "table" or type(order) ~= "table" then
        return nil, "invalid-resource-order"
    end

    local normalized = CanonicalHandOrder(profile, BuildOrderedPresetIds(defaults, ExpandHandOrder(order)))
    local resources = ResourceConfig(profile)
    resources.orderBySpec = type(resources.orderBySpec) == "table"
        and resources.orderBySpec or {}
    local specKey = tostring(specID)
    if OrdersEqual(normalized, defaults) then
        PruneOrderStorage(resources, classFile, specKey)
        return normalized
    end
    local classOrder = type(resources.orderBySpec[classFile]) == "table"
        and resources.orderBySpec[classFile] or {}
    resources.orderBySpec[classFile] = classOrder
    classOrder[specKey] = normalized
    return normalized
end

function Catalog:MovePreset(
    profile,
    classFile,
    specID,
    resourceId,
    targetIndex,
    enabledOnly
)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    local paired = PairEnabled(profile)
    if paired and (resourceId == "swingMainHand" or resourceId == "swingOffHand") then resourceId = "swingHands" end
    if not classFile or not specID
        or not (HasPresetResource(classFile, specID, resourceId)
            or (paired and resourceId == "swingHands" and HasPresetResource(classFile, specID, "swingMainHand"))) then
        return nil, "unknown-resource-preset"
    end
    local order = self:GetOrderedPresetIds(profile, classFile, specID)
    if paired then order = FoldHandOrder(order) end
    local sourceIndex
    for index = 1, #order do
        if order[index] == resourceId then
            sourceIndex = index
            break
        end
    end
    if not sourceIndex then return nil, "unknown-resource-preset" end

    table.remove(order, sourceIndex)
    local insertIndex
    if enabledOnly == true then
        local enabled = {}
        for index = 1, #order do
            if self:IsPresetEnabled(profile, classFile, specID, order[index]) then
                enabled[#enabled + 1] = order[index]
            end
        end
        targetIndex = math.max(
            1,
            math.min(#enabled + 1, math.floor(tonumber(targetIndex) or 1))
        )
        local beforeId = enabled[targetIndex]
        if beforeId then
            for index = 1, #order do
                if order[index] == beforeId then
                    insertIndex = index
                    break
                end
            end
        elseif #enabled > 0 then
            local afterId = enabled[#enabled]
            for index = #order, 1, -1 do
                if order[index] == afterId then
                    insertIndex = index + 1
                    break
                end
            end
        end
    else
        insertIndex = math.max(
            1,
            math.min(#order + 1, math.floor(tonumber(targetIndex) or sourceIndex))
        )
    end
    table.insert(order, insertIndex or math.min(sourceIndex, #order + 1), resourceId)
    return self:SetPresetOrder(profile, classFile, specID, order)
end

function Catalog:IsPresetEnabled(profile, classFile, specID, resourceId)
    if resourceId == "swingHands" and PairEnabled(profile) then
        return self:IsPresetEnabled(profile, classFile, specID, "swingMainHand")
            or self:IsPresetEnabled(profile, classFile, specID, "swingOffHand")
    end
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    if not classFile or not specID
        or not HasPresetResource(classFile, specID, resourceId) then
        return false
    end

    local selection = GetSpecSelection(profile, classFile, specID)
    local explicit
    if type(selection) == "table" then
        explicit = selection[resourceId]
    end
    if type(explicit) == "boolean" then return explicit end
    return ResourceConfig(profile).selectionDefault ~= "none"
        and DEFINITIONS[resourceId].defaultEnabled ~= false
end

function Catalog:SetPresetEnabled(profile, classFile, specID, resourceId, enabled)
    if resourceId == "swingHands" and PairEnabled(profile) then
        local ok, code = self:SetPresetEnabled(profile, classFile, specID, "swingMainHand", enabled)
        if not ok then return nil, code end
        return self:SetPresetEnabled(profile, classFile, specID, "swingOffHand", enabled)
    end
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    if not classFile or not specID
        or not HasPresetResource(classFile, specID, resourceId) then
        return false, "unknown-resource-preset"
    end

    local resources = ResourceConfig(profile)
    local bySpec = type(resources.bySpec) == "table"
        and resources.bySpec or {}
    resources.bySpec = bySpec
    local classSelection = type(bySpec[classFile]) == "table"
        and bySpec[classFile] or {}
    bySpec[classFile] = classSelection
    local specKey = tostring(specID)
    local specSelection = type(classSelection[specKey]) == "table"
        and classSelection[specKey] or {}
    classSelection[specKey] = specSelection
    specSelection[resourceId] = enabled == true
    return true
end

function Catalog:GetPresets(profile, classFile, specID, target)
    classFile = NormalizeClassFile(classFile)
    specID = NormalizeSpecID(specID)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end

    local presetIds = self:GetOrderedPresetIds(profile, classFile, specID)
    if not presetIds then return target end
    for index = 1, #presetIds do
        local resourceId = presetIds[index]
        local definition = DEFINITIONS[resourceId]
        target[#target + 1] = CopyDefinition(
            definition,
            classFile,
            specID,
            self:IsPresetEnabled(profile, classFile, specID, resourceId)
        )
    end
    return target
end

function Catalog:GetEnabledPresets(profile, classFile, specID, target)
    local presets = self:GetPresets(profile, classFile, specID, target)
    local writeIndex = 1
    for readIndex = 1, #presets do
        local preset = presets[readIndex]
        if preset.enabled then
            presets[writeIndex] = preset
            writeIndex = writeIndex + 1
        end
    end
    for index = #presets, writeIndex, -1 do presets[index] = nil end
    return presets
end

function Catalog:GetCurrentContext()
    local classFile = UnitAPI.GetClassToken and UnitAPI.GetClassToken("player")
    local spec = (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)
        and (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)() or nil
    classFile = NormalizeClassFile(classFile or (spec and spec.classFile))
    local specID = NormalizeSpecID(spec and spec.specID)
    return classFile, specID, spec
end

function Catalog:GetCurrentPresets(profile, target)
    if type(profile) == "table" and profile._yhudInitialResourceOnly == true then
        return self:GetInitialPresets(profile, target)
    end
    local classFile, specID = self:GetCurrentContext()
    local presets
    if CLASS_CONTEXTS[classFile] then
        presets = self:GetEnabledFormPresets(
            profile,
            classFile,
            specID,
            self:GetCurrentFormKey(classFile, specID),
            target
        )
    else
        presets = self:GetEnabledPresets(profile, classFile, specID, target)
    end
    local writeIndex = 1
    for readIndex = 1, #presets do
        local preset = presets[readIndex]
        if self:IsDefinitionAvailable(preset) then
            presets[writeIndex] = preset
            writeIndex = writeIndex + 1
        end
    end
    for index = #presets, writeIndex, -1 do presets[index] = nil end
    return presets, classFile, specID
end

local function InitialDefinitionAvailable(definition)
    local provider = definition and definition.provider or {}
    if definition and type(definition.powerType) == "number"
        and UnitAPI.ReadPowerDisplay then
        local state = UnitAPI.ReadPowerDisplay(
            "player",
            definition.powerType,
            {}
        )
        return state and state.available == true
            and (state.secret == true
                or (tonumber(state.maxValue) or 0) > 0)
    end
    local spellID = provider.requiresKnownSpellID or provider.spellID
    if spellID and SpellAPI.IsKnownOrInSpellBook then
        return SpellAPI.IsKnownOrInSpellBook(spellID) == true
    end
    return false
end

function Catalog:GetInitialPresets(profile, target)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end
    if ResourceConfig(profile).selectionDefault == "none" then return target end
    local classFile = UnitAPI.GetClassToken
        and UnitAPI.GetClassToken("player") or nil
    classFile = NormalizeClassFile(classFile)
    local classPresets = classFile and PRESETS[classFile] or nil
    if not classPresets then return target, classFile, nil end

    local candidates = {}
    local specs = (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)
        and (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)(classFile) or {}
    if #specs > 0 then
        for index = 1, #specs do
            local presetIds = classPresets[tonumber(specs[index].specID)] or {}
            for presetIndex = 1, #presetIds do
                candidates[presetIds[presetIndex]] = true
            end
        end
    else
        for _, presetIds in pairs(classPresets) do
            for index = 1, #presetIds do candidates[presetIds[index]] = true end
        end
    end
    for index = 1, #DEFINITION_IDS do
        local resourceId = DEFINITION_IDS[index]
        local definition = candidates[resourceId] and DEFINITIONS[resourceId]
        if definition and definition.defaultEnabled ~= false and InitialDefinitionAvailable(definition) then
            target[#target + 1] = CopyInitialDefinition(definition, classFile)
        end
    end
    return target, classFile, nil
end

function Catalog:GetClasses()
    if UnitAPI.GetClassInfos then
        return UnitAPI.GetClassInfos()
    end
    return {}
end

-- Runtime source subscriptions are the union of enabled groups. Projection
-- identities include the group, even when this source union is unchanged.
function Catalog:GetGroupPresets(profile, groupId, eligible, target)
    local scoped = YHUD:GetResourceProfile(profile, groupId)
    if eligible and scoped._yhudInitialResourceOnly ~= true then
        local classFile, specID = self:GetCurrentContext()
        return self:GetEligiblePresets(scoped, classFile, specID, target)
    end
    return self:GetCurrentPresets(scoped, target)
end

function Catalog:GetResourceUnion(profile, target, eligible, projection)
    target = type(target) == "table" and target or {}
    for index = #target, 1, -1 do target[index] = nil end
    if projection then for index = #projection, 1, -1 do projection[index] = nil end end
    local seen = {}
    for _, groupId in ipairs(profile.groups and profile.groups.order or {}) do
        local group = profile.groups.items[groupId]
        if group.layout == "resource" and group.enabled == true then
            local presets = self:GetGroupPresets(profile, groupId, eligible)
            for index = 1, #presets do
                local preset = presets[index]
                if projection then projection[#projection + 1] = groupId .. ":" .. preset.sourceKey end
                if not seen[preset.sourceKey] then
                    seen[preset.sourceKey] = true
                    target[#target + 1] = preset
                end
            end
        end
    end
    return target
end

function Catalog:GetSpecializations(classFile)
    if (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations) then
        return (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)(classFile)
    end
    return {}
end

function Catalog:NormalizeSelections(bySpec)
    if type(bySpec) ~= "table" then return {} end
    local normalized = {}
    for classFile, classSelection in pairs(bySpec) do
        classFile = NormalizeClassFile(classFile)
        if classFile and PRESETS[classFile]
            and type(classSelection) == "table" then
            local normalizedClass = {}
            for specID, specSelection in pairs(classSelection) do
                specID = NormalizeSpecID(specID)
                if specID and PRESETS[classFile][specID]
                    and type(specSelection) == "table" then
                    local normalizedSpec = {}
                    for resourceId, enabled in pairs(specSelection) do
                        if HasPresetResource(classFile, specID, resourceId)
                            and type(enabled) == "boolean" then
                            normalizedSpec[resourceId] = enabled
                        end
                    end
                    normalizedClass[tostring(specID)] = normalizedSpec
                end
            end
            normalized[classFile] = normalizedClass
        end
    end
    return normalized
end

function Catalog:NormalizeOrders(orderBySpec)
    if type(orderBySpec) ~= "table" then return {} end
    local normalized = {}
    for classFile, classOrder in pairs(orderBySpec) do
        classFile = NormalizeClassFile(classFile)
        if classFile and PRESETS[classFile] and type(classOrder) == "table" then
            local normalizedClass = {}
            for specID, order in pairs(classOrder) do
                specID = NormalizeSpecID(specID)
                local defaults = specID and PRESETS[classFile][specID]
                if defaults and type(order) == "table" then
                    local resolved = BuildOrderedPresetIds(defaults, order)
                    if not OrdersEqual(resolved, defaults) then
                        normalizedClass[tostring(specID)] = resolved
                    end
                end
            end
            if next(normalizedClass) ~= nil then
                normalized[classFile] = normalizedClass
            end
        end
    end
    return normalized
end

function Catalog:NormalizeFormOverrides(formOverrides)
    local temp = { resources = { formOverrides = {} } }
    if type(formOverrides) ~= "table" then
        return temp.resources.formOverrides
    end
    for classFile, classOverrides in pairs(formOverrides) do
        classFile = NormalizeClassFile(classFile)
        local context = classFile and CLASS_CONTEXTS[classFile]
        if context and type(classOverrides) == "table" then
            for rawSpecID, specOverrides in pairs(classOverrides) do
                local specID = NormalizeSpecID(rawSpecID)
                if specID and context.specs and context.specs[specID]
                    and type(specOverrides) == "table" then
                    for formKey, override in pairs(specOverrides) do
                        local state = BuildFormState(nil, classFile, specID, formKey)
                        if state and type(override) == "table" then
                            state.order = BuildOrderedPresetIds(
                                state.definition.candidates,
                                override.order
                            )
                            local explicit = type(override.enabled) == "table"
                                and override.enabled or nil
                            if explicit then
                                for index = 1, #state.definition.candidates do
                                    local resourceId = state.definition.candidates[index]
                                    if type(explicit[resourceId]) == "boolean" then
                                        state.enabled[resourceId] = explicit[resourceId]
                                    end
                                end
                            end
                            StoreFormState(
                                temp,
                                classFile,
                                specID,
                                formKey,
                                state
                            )
                        end
                    end
                end
            end
        end
    end
    return temp.resources.formOverrides
end

function Catalog:MigrateLegacyFormOverrides(resources)
    if type(resources) ~= "table" then return {} end
    resources.formOverrides = type(resources.formOverrides) == "table"
        and resources.formOverrides or {}
    local legacySelections = type(resources.bySpec) == "table"
        and resources.bySpec.DRUID or nil
    local legacyOrders = type(resources.orderBySpec) == "table"
        and resources.orderBySpec.DRUID or nil
    local context = CLASS_CONTEXTS.DRUID
    if context then
        for specID, forms in pairs(context.specs or {}) do
            local specKey = tostring(specID)
            local selection = type(legacySelections) == "table"
                and (legacySelections[specKey] or legacySelections[specID]) or nil
            local legacyOrder = type(legacyOrders) == "table"
                and (legacyOrders[specKey] or legacyOrders[specID]) or nil
            if type(selection) == "table" or type(legacyOrder) == "table" then
                for index = 1, #(context.formOrder or {}) do
                    local formKey = context.formOrder[index]
                    if forms[formKey]
                        and not GetFormOverride(
                            { resources = resources },
                            "DRUID",
                            specID,
                            formKey
                        ) then
                        local state = BuildFormState(nil, "DRUID", specID, formKey)
                        if type(selection) == "table" then
                            for candidateIndex = 1, #state.definition.candidates do
                                local resourceId = state.definition.candidates[candidateIndex]
                                if state.enabled[resourceId] == true
                                    and type(selection[resourceId]) == "boolean" then
                                    state.enabled[resourceId] = selection[resourceId]
                                end
                            end
                        end
                        if type(legacyOrder) == "table" then
                            local activeOrder = BuildOrderedPresetIds(
                                state.definition.defaults,
                                legacyOrder
                            )
                            local seen = {}
                            local order = {}
                            for orderIndex = 1, #activeOrder do
                                local resourceId = activeOrder[orderIndex]
                                seen[resourceId] = true
                                order[#order + 1] = resourceId
                            end
                            for candidateIndex = 1, #state.definition.candidates do
                                local resourceId = state.definition.candidates[candidateIndex]
                                if not seen[resourceId] then
                                    order[#order + 1] = resourceId
                                end
                            end
                            state.order = order
                        end
                        StoreFormState(
                            { resources = resources },
                            "DRUID",
                            specID,
                            formKey,
                            state
                        )
                    end
                end
            end
        end
    end
    if type(resources.bySpec) == "table" then
        resources.bySpec.DRUID = nil
    end
    if type(resources.orderBySpec) == "table" then
        resources.orderBySpec.DRUID = nil
    end
    return resources.formOverrides
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

-- Membership is independent of enabled state and of ordinary monitor ownership.
-- Unedited contexts continue to read the frozen legacy resource selections.
local Manager = { LIMIT = 64 }
YHUD.ResourceManager = Manager
local BAR = { view = "bar" }
local CUSTOM_COLOR = { 0.65, 0.35, 0.90, 1 }
local function Copy(value) return YHUD:CopyValue(value) end
local function BoundedText(value, limit)
    if #value <= limit then return value end
    while limit > 0 do
        local byte = value:byte(limit + 1)
        if byte < 128 or byte >= 192 then break end
        limit = limit - 1
    end
    return value:sub(1, limit)
end
local function PublicNumber(value)
    if _G.issecretvalue and _G.issecretvalue(value) then return nil end
    return type(value) == "number" and value == value and value or nil
end
local function Context(classFile, specID, formKey)
    return tostring(classFile) .. ":" .. tostring(specID) .. ":" .. (formKey or "")
end
Manager.ContextKey = Context

local function HandPair(profile)
    return YUI.IsForever == true and profile and profile._yhudHandPairMode == "split"
end
local function DisplayId(profile, id)
    if HandPair(profile) and (id == "swingMainHand" or id == "swingOffHand") then return "swingHands" end
    return id
end
-- Snapshot membership, not adjacent pairs: reordering/removing a member must
-- preserve all surviving members of its original row.
local function BuildRows(items)
    local rows, row = {}, nil
    for _, item in ipairs(items) do
        if not row or item.joinPrevious ~= true then row = { key = item.id, count = 0 } end
        row.count = row.count + 1
        rows[item.id] = row
    end
    return rows
end
local function RebuildLinks(items, rows)
    local previous
    for _, item in ipairs(items) do
        local row = rows[item.id]
        item.joinPrevious = row ~= nil and row == previous and true or nil
        previous = row
    end
end

-- Reverse complete rows, keeping their left-to-right member order intact.
-- Applying this twice restores the saved growth order without a migration.
local function ReverseRows(items)
    local starts, result = {}, {}
    for index, item in ipairs(items) do
        if index == 1 or item.joinPrevious ~= true then starts[#starts+1] = index end
    end
    for row = #starts, 1, -1 do
        for index = starts[row], (starts[row+1] or (#items+1))-1 do result[#result+1] = items[index] end
    end
    return result
end

function Manager:GetEditorPresets(profile, items, direction)
    local displayed = YHUD.ResourceCatalog:GetDisplayPresets(profile,items)
    return direction == "up" and ReverseRows(displayed) or displayed
end

function Manager:GetMoveInfo(items, id, step)
    local rows, index = BuildRows(items)
    for i, item in ipairs(items) do if item.id == id then index = i break end end
    if not index then return nil end
    local row, first, last = rows[id], index, index
    while first > 1 and rows[items[first-1].id] == row do first = first-1 end
    while last < #items and rows[items[last+1].id] == row do last = last+1 end
    local target = items[index+step]
    return {
        linked = row.count > 1,
        detaches = target ~= nil and row.count > 1 and rows[target.id] ~= row,
        rowCanMove = step < 0 and first > 1 or step > 0 and last < #items,
    }
end

-- Bulk removal also visits saved contexts outside the currently selected spec.
-- Keep physical weapon switches independent while treating split hands as one
-- external row member, just as the settings list does.
function Manager:RemoveItems(profile, items, ids)
    local rows = BuildRows(YHUD.ResourceCatalog:GetDisplayPresets(profile, items))
    local paired, mainKept = HandPair(profile), false
    if paired and not ids.swingMainHand then
        for _, item in ipairs(items) do
            if item.id == "swingMainHand" then mainKept = true break end
        end
    end
    local kept, previous, removed = {}, nil, false
    for _, item in ipairs(items) do
        if ids[item.id] then removed = true else
            local copy = Copy(item)
            local row = rows[DisplayId(profile, item.id)]
            copy.joinPrevious = row == previous and true or nil
            -- Without a main hand, the off hand owns the external row link.
            if paired and mainKept and item.id == "swingOffHand" then copy.joinPrevious = nil end
            kept[#kept + 1], previous = copy, row
        end
    end
    return kept, removed
end

function Manager:HasCustom(profile)
    for _, config in pairs(profile and profile.resources and profile.resources.byGroup or {}) do
        if next(config.customById or {}) then return true end
    end
    return false
end

function Manager:IsCustom(id)
    if type(id) ~= "string" then return false end
    local serial = id:match("^custom%-resource:(%d+)$")
    return serial ~= nil and #serial <= 9 and tonumber(serial) > 0
end

function Manager:GetCustom(profile, groupId, id)
    local config = YHUD:GetResourceConfig(profile, groupId)
    return config.customById and config.customById[id]
end

function Manager:GetDefinition(id, profile, groupId)
    if not self:IsCustom(id) then return nil end
    local custom = profile and self:GetCustom(profile, groupId, id)
    local progress = custom and custom.progress
    local time = not progress or progress.source == "time"
    return {
        id = id, name = custom and custom.name, nameKey = "designer.resource.custom",
        valueKind = time and "continuous" or "discrete", defaultEnabled = false,
        defaultValueText = true, defaultValueFormat = time and "duration" or "value",
        color = CUSTOM_COLOR, provider = { kind = time and "monitor-time" or "monitor-value" },
    }
end

function Manager:RefreshCatalog(profile)
    if profile then
        local needed = false
        for _, config in pairs(profile.resources and profile.resources.byGroup or {}) do
            for _, custom in pairs(config.customById or {}) do
                if custom.entry.origin == "official-cdm" then needed = true break end
            end
        end
        if not needed then return end
    end
    self.catalogSpecKey = YHUD:GetCurrentSpecKey()
    local rows = YHUD.CDMCatalog and YHUD.CDMCatalog.Read
        and YHUD.CDMCatalog:Read({ includeHidden = true, allowUnlearned = true })
    self.catalogById = nil
    if type(rows) == "table" then
        self.catalogById = {}
        for _, row in ipairs(rows) do
            if row.cooldownID then self.catalogById[row.cooldownID] = row end
        end
    end
end

function Manager:ResolveEntry(custom, classFile, specID)
    local entry = custom.entry
    if classFile and YHUD:GetCurrentSpecKey() ~= classFile .. ":" .. specID then return entry, "source" end
    if entry.origin ~= "official-cdm" then return entry end
    if classFile and self.catalogSpecKey ~= classFile .. ":" .. specID then return entry, "source" end
    local row = self.catalogById and self.catalogById[entry.cooldownId]
    if not row then return entry, "source" end
    return YHUD.CDMImport:CreateEntry(row, entry) or entry
end

function Manager:Capabilities(entry)
    if type(entry) ~= "table" or entry.bundleKind or entry.itemId or entry.itemID or entry.equipSlot
        or entry.slotId or entry.sourceType == "item-cooldown" then return nil end
    local spellID = PublicNumber(entry.overrideSpellId or entry.spellId)
    if not spellID or spellID < 1 then return nil end
    if YHUD:CanUseSkillDurationSource(entry, BAR) then
        local spellID = entry.overrideSpellId or entry.spellId
        local api = YUI.API and YUI.API.Spell
        local charge = api and api.ReadChargeResourceDisplay and api.ReadChargeResourceDisplay(spellID, {})
        local maximum = charge and charge.available and PublicNumber(charge.maxValue)
        if charge then charge.valueRaw, charge.rechargeDurationRaw = nil, nil end
        return { time = true, ["spell-charges"] = entry.charges == true or maximum and maximum > 1 or false }
    end
    if YHUD:CanUseBarAuraProgress(entry, BAR) then
        return { time = true, ["aura-stacks"] = true }
    end
    if entry.sourceType == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE
        or entry.sourceType == YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE then
        return { time = true }
    end
end

function Manager:NormalizeEntry(entry)
    local result = {}
    for _, key in ipairs({ "entryKey", "sourceKey", "sourceType", "sourceIdentity", "name", "nameKey", "origin",
        "semantic", "officialCategory", "sourceCategory", "displayCategory", "filteredAuraScope", "presetId" }) do
        if type(entry[key]) == "string" then result[key] = BoundedText(entry[key], 256) end
    end
    for _, key in ipairs({ "spellId", "overrideSpellId", "overrideTooltipSpellId", "runtimeSpellId", "chargeSpellId", "cooldownId", "icon" }) do
        local value = PublicNumber(entry[key])
        if value and value > 0 and value < 2147483647 and value == math.floor(value) then result[key] = value end
    end
    if type(entry.icon) == "string" then result.icon = BoundedText(entry.icon, 256) end
    for _, key in ipairs({ "charges", "selfAura", "hasAura", "canUseAuraForCooldown" }) do
        if type(entry[key]) == "boolean" then result[key] = entry[key] end
    end
    local duration = PublicNumber(entry.durationSeconds)
    if duration and duration >= 0.1 and duration <= 3600 then result.durationSeconds = duration end
    for _, key in ipairs({ "spellIds", "linkedSpellIds", "triggerSpellIds" }) do
        if type(entry[key]) == "table" then
            local values, seen = {}, {}
            for _, value in ipairs(entry[key]) do
                value = PublicNumber(value)
                if value and value > 0 and value < 2147483647 and value == math.floor(value) and not seen[value] and #values < 32 then
                    values[#values + 1], seen[value] = value, true
                end
            end
            result[key] = values
        end
    end
    return result
end

function Manager:Issue(custom, enabled, unresolved)
    if enabled == false then return nil end
    if unresolved then return unresolved end
    local entry = custom and custom.entry
    local capabilities = self:Capabilities(entry)
    if not capabilities then return "source" end
    if entry.origin == "official-cdm" and entry.nativeVisible == false then return "tracking" end
    local api = YUI.API and YUI.API.Spell
    if YHUD:CanUseSkillDurationSource(entry, BAR) and api and api.IsKnownOrInSpellBook
        and api.IsKnownOrInSpellBook(entry.overrideSpellId or entry.spellId) == false then return "unlearned" end
    if entry.isKnown == false then return "unlearned" end
    local progress = YHUD:NormalizeBarProgress(custom.progress)
    if not capabilities[progress.source] then return "progress" end
    if progress.source == "aura-stacks" and progress.maximumMode == "auto" then
        local max = api and api.ReadMaxCumulativeAuraApplications
            and api.ReadMaxCumulativeAuraApplications(entry.overrideSpellId or entry.spellId)
        if not PublicNumber(max) or max < 1 then return "maximum" end
    end
end

function Manager:GetItems(profile, classFile, specID, formKey)
    local config = YHUD:GetResourceConfig(profile)
    local saved = config.itemsByContext and config.itemsByContext[Context(classFile, specID, formKey)]
    if saved then return Copy(saved) end
    local catalog = YHUD.ResourceCatalog
    local presets = formKey and catalog:GetFormPresets(profile, classFile, specID, formKey)
        or catalog:GetPresets(profile, classFile, specID)
    local result = {}
    for _, preset in ipairs(presets) do
        if preset.enabled or config.legacyCandidates == true and preset.id ~= "gcd" then
            local definition = catalog:GetDefinition(preset.id)
            local previous = result[#result]
            result[#result + 1] = { id = preset.id, enabled = preset.enabled == true,
                joinPrevious = previous and definition and definition.defaultLinkPrevious == previous.id and true or nil }
        end
    end
    return result
end

function Manager:StoreItems(profile, classFile, specID, formKey, items)
    local config = YHUD:GetResourceConfig(profile)
    config.itemsByContext = config.itemsByContext or {}
    config.itemsByContext[Context(classFile, specID, formKey)] = Copy(items)
end

function Manager:GetAuraSpellIDs(entry)
    local ids, seen = {}, {}
    local function Add(value)
        value = PublicNumber(value)
        if value and value > 0 and not seen[value] then
            seen[value], ids[#ids + 1] = true, value
        end
    end
    Add(entry.overrideTooltipSpellId)
    Add(entry.runtimeSpellId)
    Add(entry.overrideSpellId)
    Add(entry.spellId)
    for _, id in ipairs(entry.spellIds or {}) do Add(id) end
    for _, id in ipairs(entry.linkedSpellIds or {}) do Add(id) end
    table.sort(ids)
    return ids
end

function Manager:BuildCustomPreset(profile, custom, classFile, specID, enabled)
    local definition = self:GetDefinition(custom.id, profile)
    local entry, unresolved = self:ResolveEntry(custom, classFile, specID)
    local progress = YHUD:NormalizeBarProgress(custom.progress)
    local api = YUI.API and YUI.API.Spell
    local spellID = entry.runtimeSpellId or entry.overrideSpellId or entry.spellId
    local maximum
    if progress.source == "aura-stacks" then
        maximum = progress.maximumMode == "custom" and progress.maximum
            or api and api.ReadMaxCumulativeAuraApplications and api.ReadMaxCumulativeAuraApplications(spellID)
    elseif progress.source == "spell-charges" then
        local charge = api and api.ReadChargeResourceDisplay and api.ReadChargeResourceDisplay(spellID, {})
        maximum = charge and charge.available and PublicNumber(charge.maxValue)
        if charge then charge.valueRaw, charge.rechargeDurationRaw = nil, nil end
    end
    maximum = PublicNumber(maximum)
    local aura = YHUD:CanUseBarAuraProgress(entry, BAR) == true
    local scope = YHUD.GetFilteredAuraScopeKey and YHUD:GetFilteredAuraScopeKey(entry)
    local target = scope == YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL
    local provider = {
        kind = progress.source == "spell-charges" and "spell-charges"
            or progress.source == "aura-stacks" and "unit-aura-stacks"
            or aura and "aura-duration" or "monitor-time",
        spellID = spellID, fallbackMax = maximum, maxApplicationsSpellID = progress.source == "aura-stacks"
            and progress.maximumMode == "auto" and spellID or nil,
        unit = target and "target" or "player", filter = target and "HARMFUL"
            or scope == YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL_CDM_EXTENDED and "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY" or "HELPFUL",
        requirePlayerSource = target, auraBackend = aura and "filtered-only" or nil,
        bridgeCategory = entry.displayCategory or entry.officialCategory, bridgeCooldownID = entry.cooldownId,
        spellIDs = aura and self:GetAuraSpellIDs(entry) or nil,
    }
    definition.classFile, definition.specID = classFile, specID
    definition.enabled, definition.name = enabled == true, custom.name
    definition.customEntry, definition.progress, definition.provider = entry, progress, provider
    definition.previewMax = progress.source == "time" and (entry.durationSeconds or 10) or maximum
    definition.segmentCountFallback = maximum
    definition.issue = self:Issue({ entry = entry, progress = progress }, enabled, unresolved)
    definition.sourceKey = provider.kind == "monitor-time" and YHUD:GetMonitorRuntimeSourceKey(entry, {
        view = "bar", sourceKey = entry.sourceKey,
    }) or ("resource-custom:" .. tostring(entry.entryKey or entry.sourceKey or spellID) .. ":" .. progress.source
        .. ":" .. tostring(maximum) .. ":" .. tostring(target))
    if not definition.sourceKey then
        definition.sourceKey, definition.issue = "resource-pending:" .. custom.id, "source"
    end
    return definition
end

function Manager:GetPresets(profile, classFile, specID, formKey, enabledOnly)
    local catalog, byId = YHUD.ResourceCatalog, {}
    local available = formKey and catalog:GetFormPresets(profile, classFile, specID, formKey)
        or catalog:GetPresets(profile, classFile, specID)
    for _, preset in ipairs(available) do byId[preset.id] = preset end
    local config, result = YHUD:GetResourceConfig(profile), {}
    local items = self:GetItems(profile, classFile, specID, formKey)
    local rows = BuildRows(catalog:GetDisplayPresets(profile, items))
    local handKey
    for _, item in ipairs(items) do
        if DisplayId(profile, item.id) == "swingHands" then handKey = handKey or item.id end
    end
    for _, item in ipairs(items) do
        local custom = config.customById and config.customById[item.id]
        local preset = custom and self:BuildCustomPreset(profile, custom, classFile, specID, item.enabled)
            or byId[item.id]
        if preset and (not enabledOnly or item.enabled) then
            preset.enabled = item.enabled
            preset.joinPrevious = item.joinPrevious == true or nil
            local row = rows[DisplayId(profile, item.id)]
            preset.resourceRowKey = row and row.count > 1 and (row.key == "swingHands" and handKey or row.key) or nil
            result[#result + 1] = preset
        end
    end
    return result
end

-- A group's style list includes memberships from every specialization/form.
-- Use saved identities here; resolving live sources belongs to the selected preview.
function Manager:GetStylePresets(profile, classFile, specID, formKey)
    local catalog, config = YHUD.ResourceCatalog, YHUD:GetResourceConfig(profile)
    local result, seen, contexts = {}, {}, {}
    local function Append(class, spec, form)
        if not class or not spec then return end
        local key = Context(class, spec, form)
        if contexts[key] then return end
        contexts[key] = true
        local items = catalog:GetDisplayPresets(profile, self:GetItems(profile, class, spec, form))
        for _, item in ipairs(items) do
            local id = item.styleResourceId or item.id
            if not seen[id] then
                local definition = self:GetDefinition(id, profile) or catalog:GetDefinition(id)
                if definition then
                    local preset = Copy(definition)
                    preset.id, preset.enabled = id, item.enabled
                    preset.classFile, preset.specID, preset.formKey = class, spec, form
                    preset.nameKey = item.nameKey or preset.nameKey
                    result[#result + 1], seen[id] = preset, true
                end
            end
        end
    end
    Append(classFile, specID, formKey)
    for _, class in ipairs(catalog:GetClasses()) do
        for _, spec in ipairs(catalog:GetSpecializations(class.classFile)) do
            local forms = catalog:GetFormOptions(class.classFile, spec.specID)
            if #forms == 0 then Append(class.classFile, spec.specID) end
            for _, form in ipairs(forms) do Append(class.classFile, spec.specID, form.key) end
        end
    end
    local savedKeys = {}
    for key in pairs(config.itemsByContext or {}) do savedKeys[#savedKeys + 1] = key end
    table.sort(savedKeys)
    for _, key in ipairs(savedKeys) do
        local class, spec, form = key:match("^([A-Z]+):(%d+):(.*)$")
        Append(class, tonumber(spec), form ~= "" and form or nil)
    end
    return result
end

function Manager:GetStylePreviewPreset(profile, id, classFile, specID, formKey)
    for _, item in ipairs(self:GetStylePresets(profile, classFile, specID, formKey)) do
        if item.id == id then
            for _, preset in ipairs(self:GetPresets(profile, item.classFile, item.specID, item.formKey, false)) do
                if preset.id == id then return preset end
            end
            return nil
        end
    end
end

-- Normalize only public saved configuration. Never persist availability or raw
-- game values; these are resolved again for the current character context.
function Manager:NormalizeConfig(config, sourceVersion)
    config.legacyCandidates = config.legacyCandidates == true or config.legacyCandidates ~= false and sourceVersion < 50
        and config.selectionDefault ~= "none" or nil
    local customs, nextId = {}, 1
    for id, custom in pairs(type(config.customById) == "table" and config.customById or {}) do
        if self:IsCustom(id) and type(custom) == "table" and type(custom.entry) == "table"
            then
            local entry = self:NormalizeEntry(custom.entry)
            customs[id] = { id = id, name = type(custom.name) == "string" and BoundedText(custom.name, 160)
                or entry.name or id, entry = entry, progress = YHUD:NormalizeBarProgress(custom.progress) }
            nextId = math.max(nextId, tonumber(id:match("(%d+)$")) + 1)
        end
    end
    local savedNext = PublicNumber(config.nextCustomId)
    config.customById, config.nextCustomId = customs, math.max(nextId,
        savedNext and savedNext >= 1 and savedNext < 1000000000 and math.floor(savedNext) or 1)
    local contexts = {}
    for key, list in pairs(type(config.itemsByContext) == "table" and config.itemsByContext or {}) do
        if type(key) == "string" and key:match("^[A-Z]+:%d+:.*$") and type(list) == "table" then
            local result, seen, rows, row = {}, {}, {}, nil
            for _, item in ipairs(list) do
                local id = type(item) == "table" and item.id
                if not row or type(item) ~= "table" or item.joinPrevious ~= true then row = {} end
                if id and not seen[id] and (customs[id] or not self:IsCustom(id) and YHUD.ResourceCatalog:GetDefinition(id))
                    and #result < self.LIMIT then
                    result[#result + 1] = { id = id, enabled = item.enabled ~= false }
                    seen[id], rows[id] = true, row
                end
            end
            RebuildLinks(result, rows)
            contexts[key] = result
        end
    end
    config.itemsByContext = contexts
    self:MigrateBalanceEclipses(config)
end

-- One-time conversion of compatible existing Balance aura timers. Explicit
-- membership, row order and styles survive; unrelated specs keep their copies.
function Manager:MigrateBalanceEclipses(config)
    if not YUI.IsRetail or (tonumber(config.balanceEclipseVersion) or 0) >= 1 then return end
    config.balanceEclipseVersion = 1
    local membership, occupied, candidates = {}, {}, {}
    for context, items in pairs(config.itemsByContext) do
        if context:match("^DRUID:102:") then
            for _, item in ipairs(items) do membership[item.id] = true end
        end
    end
    local function ResolvePreset(entry)
        local preset
        for _, spellID in ipairs(self:GetAuraSpellIDs(entry)) do
            local matched = spellID == 48517 and "solarEclipse" or spellID == 48518 and "lunarEclipse" or nil
            -- The shared base identity belongs to the old CDM descriptors.
            -- Any other aura, or both eclipses, cannot be represented by one preset.
            if matched then
                if preset and preset ~= matched then return nil end
                preset = matched
            elseif spellID ~= 1239669 then return nil end
        end
        return preset
    end
    for _, id in ipairs({ "solarEclipse", "lunarEclipse" }) do occupied[id] = membership[id] end
    for id, custom in pairs(config.customById) do
        local entry = custom.entry
        if membership[id] and custom.progress.source == "time" and custom.progress.ticks.mode == "off" and entry.selfAura == true
            and YHUD:CanUseBarAuraProgress(entry, BAR)
            and YHUD:GetFilteredAuraScopeKey(entry) ~= YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL then
            local preset = ResolvePreset(entry)
            if preset then
                local list = candidates[preset] or {}
                candidates[preset] = list
                list[#list + 1] = id
            end
        end
    end
    local replacements = {}
    for preset, ids in pairs(candidates) do
        -- Multiple custom copies, or an existing preset, may have intentionally
        -- different styles. Leave those configurations alone rather than merge.
        if #ids == 1 and not occupied[preset] then
            local id = ids[1]
            replacements[id] = preset
            config.settingsByResource = config.settingsByResource or {}
            local setting = config.settingsByResource[id]
            if setting then config.settingsByResource[preset] = YHUD:NormalizeResourceSetting(setting,preset) end
        end
    end
    local retained = {}
    for context, items in pairs(config.itemsByContext) do
        for _, item in ipairs(items) do
            if context:match("^DRUID:102:") then item.id = replacements[item.id] or item.id end
            retained[item.id] = true
        end
    end
    for id in pairs(replacements) do
        if not retained[id] then
            config.customById[id] = nil
            config.settingsByResource[id] = nil
        end
    end
end

local function InsertPreset(items, id)
    local definition = YHUD.ResourceCatalog:GetDefinition(id)
    local previous = definition and definition.defaultLinkPrevious
    local following = definition and definition.defaultLinkNext
    local added = { id = id, enabled = true }
    for index, item in ipairs(items) do
        if item.id == previous then
            added.joinPrevious = true
            table.insert(items,index + 1,added)
            return
        elseif item.id == following then
            added.joinPrevious, item.joinPrevious = item.joinPrevious, true
            table.insert(items,index,added)
            return
        end
    end
    table.insert(items,1,added)
end

-- Copy one complete row within this specialization. Prepare every target before
-- committing, so a full form cannot leave a partially copied draft.
function Manager:CopyRowToForms(profile, classFile, specID, formKey, id)
    local catalog = YHUD.ResourceCatalog
    local forms = catalog:GetFormOptions(classFile, specID)
    local validForm = false
    for _, form in ipairs(forms) do if form.key == formKey then validForm = true end end
    if not validForm or #forms < 2 then return nil, "resource-context-unavailable" end
    local source = self:GetItems(profile, classFile, specID, formKey)
    local rows = BuildRows(catalog:GetDisplayPresets(profile, source))
    local row = rows[DisplayId(profile, id)]
    if not row then return nil, "resource-not-found" end
    local pending = {}
    for _, form in ipairs(forms) do
        if form.key ~= formKey then
            local allowed, copies, copied, sourceFirst, sourceLast = {}, {}, {}
            for _, preset in ipairs(catalog:GetFormPresets(profile, classFile, specID, form.key)) do allowed[preset.id] = true end
            for sourceIndex, item in ipairs(source) do
                if rows[DisplayId(profile, item.id)] == row and (self:IsCustom(item.id) or allowed[item.id]) then
                    sourceFirst, sourceLast = sourceFirst or sourceIndex, sourceIndex
                    copied[item.id] = true
                    copies[#copies + 1] = { id = item.id, enabled = item.enabled,
                        joinPrevious = #copies > 0 and not (HandPair(profile)
                            and item.id == "swingOffHand" and copied.swingMainHand) and true or nil }
                end
            end
            if #copies > 0 then
                local target = self:GetItems(profile, classFile, specID, form.key)
                local kept = self:RemoveItems(profile, target, copied)
                local positions, insertAt, after = {}, nil, false
                for index, item in ipairs(kept) do positions[item.id] = index end
                -- Keep the copied row on the same side of shared resources.
                -- Appending it reverses its apparent position in upward stacks.
                for index = sourceFirst - 1, 1, -1 do
                    if positions[source[index].id] then insertAt, after = positions[source[index].id] + 1, true break end
                end
                if not insertAt then
                    for index = sourceLast + 1, #source do
                        if positions[source[index].id] then insertAt = positions[source[index].id] break end
                    end
                end
                insertAt = insertAt or math.min(sourceFirst, #kept + 1)
                -- Insert at a surviving row boundary, never inside that row.
                if after then
                    while kept[insertAt] and kept[insertAt].joinPrevious do insertAt = insertAt + 1 end
                else
                    while insertAt > 1 and kept[insertAt] and kept[insertAt].joinPrevious do insertAt = insertAt - 1 end
                end
                for index = #copies, 1, -1 do table.insert(kept, insertAt, copies[index]) end
                if #catalog:GetDisplayPresets(profile, kept) > self.LIMIT then return nil, "resource-limit" end
                local changed = #target ~= #kept
                for index, item in ipairs(kept) do
                    local old = target[index]
                    if not old or old.id ~= item.id or old.enabled ~= item.enabled
                        or (old.joinPrevious == true) ~= (item.joinPrevious == true) then changed = true break end
                end
                if changed then pending[form.key] = kept end
            end
        end
    end
    local changed = false
    for form, items in pairs(pending) do
        self:StoreItems(profile, classFile, specID, form, items)
        changed = true
    end
    return true, changed
end

-- Run the same configuration helpers on a private copy for an exact cold-path
-- confirmation summary. No live source resolution or draft writes occur here.
function Manager:PreviewOperation(profile, classFile, specID, formKey, action, id)
    local catalog = YHUD.ResourceCatalog
    local source = self:GetItems(profile, classFile, specID, formKey)
    local displayed = catalog:GetDisplayPresets(profile, source)
    local selected
    for _, item in ipairs(displayed) do if item.id == id then selected = item break end end
    if not selected then return nil, "resource-not-found" end
    local working = {resources=Copy(profile.resources),_yhudHandPairMode=profile._yhudHandPairMode}
    local report = {action=action,id=id,selectedEnabled=selected.enabled,contexts={},resourceIds={id},added=0,removed=0,enabled=0,disabled=0,adjusted=0}
    local ok, code
    if action == "copy-forms" then
        ok, code = self:CopyRowToForms(working,classFile,specID,formKey,id)
        report.resourceIds = {}
        local rows = BuildRows(displayed)
        for _, item in ipairs(displayed) do
            if rows[item.id] == rows[id] then report.resourceIds[#report.resourceIds+1] = item.id end
        end
    elseif action == "copy-all" then
        ok, code = catalog:SetPresetEnabledForAllSpecializations(working,id,selected.enabled == true)
    elseif action == "remove-all" then
        ok, code = catalog:RemoveResourceForAllSpecializations(working,id)
    elseif action == "remove" then
        local ids = id == "swingHands" and {swingMainHand=true,swingOffHand=true} or {[id]=true}
        local kept = self:RemoveItems(working,source,ids)
        self:StoreItems(working,classFile,specID,formKey,kept)
        ok = true
    else return nil, "invalid-resource-action" end
    if not ok then return nil, code end
    local keys = {}
    for key in pairs(working.resources.itemsByContext or {}) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local class, spec, form = key:match("^([A-Z]+):(%d+):(.*)$")
        if class then
            form = form ~= "" and form or nil
            local before = catalog:GetDisplayPresets(profile,self:GetItems(profile,class,tonumber(spec),form))
            local after = catalog:GetDisplayPresets(working,working.resources.itemsByContext[key])
            local old, new, changed = {}, {}, false
            for index, item in ipairs(before) do old[item.id] = {item=item,index=index} end
            for index, item in ipairs(after) do
                new[item.id] = true
                local previous = old[item.id]
                if not previous then report.added, changed = report.added+1, true
                else
                    if previous.item.enabled ~= item.enabled then
                        local field = item.enabled and "enabled" or "disabled"
                        report[field], changed = report[field]+1, true
                    end
                    if previous.index ~= index or (previous.item.joinPrevious == true) ~= (item.joinPrevious == true) then
                        report.adjusted, changed = report.adjusted+1, true
                    end
                end
            end
            for resourceId in pairs(old) do
                if not new[resourceId] then report.removed, changed = report.removed+1, true end
            end
            if changed then report.contexts[#report.contexts+1] = {classFile=class,specID=tonumber(spec),formKey=form} end
        end
    end
    if self:IsCustom(id) and (action == "remove" or action == "remove-all") then
        report.removesDefinition = true
        for _, items in pairs(working.resources.itemsByContext or {}) do
            for _, item in ipairs(items) do if item.id == id then report.removesDefinition = false end end
        end
    end
    return report
end

function Manager:Mutate(draft, groupId, classFile, specID, formKey, action, id, value, editorDirection)
    local model = YHUD.ProfileModel
    if not model:IsDraft(draft) or draft.closed or draft.combat then return nil, "invalid-draft" end
    if type(classFile) ~= "string" or not classFile:match("^[A-Z]+$")
        or type(specID) ~= "number" or specID < 1 or specID ~= math.floor(specID)
        or formKey ~= nil and type(formKey) ~= "string" then return nil, "resource-context-unavailable" end
    local group = draft.profile.groups.items[groupId]
    if not group or group.contentPolicy ~= "resource-only" then return nil, "resource-group-required" end
    local scoped = YHUD:GetResourceProfile(draft.profile, groupId)
    local config = scoped.resources
    local items = self:GetEditorPresets(scoped,self:GetItems(scoped,classFile,specID,formKey),editorDirection)
    local index
    for i, item in ipairs(items) do if item.id == id then index = i break end end
    if action == "add" or action == "custom" then
        if #items >= self.LIMIT then return nil, "resource-limit" end
        if action == "custom" then
            local entry = value and value.entry
            local caps = self:Capabilities(entry)
            local progress = YHUD:NormalizeBarProgress(value and value.progress)
            if not caps or not caps[progress.source] then return nil, "unsupported-resource-source" end
            config.customById = config.customById or {}
            local serial = config.nextCustomId or 1
            if serial >= 1000000000 then return nil, "resource-limit" end
            repeat id = "custom-resource:" .. serial; serial = serial + 1 until not config.customById[id]
            config.nextCustomId = serial
            config.customById[id] = { id = id, name = BoundedText(type(value.name) == "string" and value.name or entry.name or id, 160),
                entry = self:NormalizeEntry(entry), progress = progress }
        elseif index then return id end
        if not self:IsCustom(id) then
            local allowed = false
            for _, preset in ipairs(formKey and YHUD.ResourceCatalog:GetFormPresets(scoped, classFile, specID, formKey)
                or YHUD.ResourceCatalog:GetPresets(scoped, classFile, specID)) do
                if preset.id == id or id == "swingHands" and scoped._yhudHandPairMode == "split"
                    and preset.id == "swingMainHand" then allowed = true break end
            end
            if not allowed then return nil, "unknown-resource" end
        end
        local definition = YHUD.ResourceCatalog:GetDefinition(id)
        if definition and (definition.defaultLinkPrevious or definition.defaultLinkNext) then
            local used = false
            for _, preset in ipairs(self:GetStylePresets(scoped,classFile,specID,formKey)) do
                if preset.id == id then used = true break end
            end
            -- Styles are shared by a resource's other forms in this group.
            if not used then config.settingsByResource[id] = YHUD:NormalizeResourceSetting(nil,id) end
        end
        InsertPreset(items,id)
    elseif not index then return nil, "resource-not-found"
    elseif action == "copy-forms" then
        local ok, changed = self:CopyRowToForms(scoped, classFile, specID, formKey, id)
        if not ok then return nil, changed end
        if changed then model:MarkResourceGroupChanged(draft, groupId) end
        return id, items, index
    elseif action == "remove-all" then
        local working = { resources = Copy(config), _yhudHandPairMode = scoped._yhudHandPairMode }
        local ok, code = YHUD.ResourceCatalog:RemoveResourceForAllSpecializations(working, id)
        if not ok then return nil, code end
        if self:IsCustom(id) then
            working.resources.customById[id] = nil
            working.resources.settingsByResource[id] = nil
        end
        draft.root.resources.byGroup[groupId] = working.resources
        model:MarkResourceGroupChanged(draft, groupId)
        return id, self:GetEditorPresets(working,
            self:GetItems(working, classFile, specID, formKey),editorDirection), index
    elseif action == "enabled" then items[index].enabled = value == true
    elseif action == "link" then
        if index == 1 or type(value) ~= "boolean" then return nil, "invalid-resource-link" end
        if (items[index].joinPrevious == true) == value then return id, items, index end
        items[index].joinPrevious = value and true or nil
    elseif action == "move-row" then
        if value ~= -1 and value ~= 1 then return nil, "invalid-resource-order" end
        local rows, groups, rowIndex = BuildRows(items), {}, nil
        for _, item in ipairs(items) do
            if #groups == 0 or item.joinPrevious ~= true then groups[#groups+1] = {} end
            local members = groups[#groups]
            members[#members+1] = item
            if item.id == id then rowIndex = #groups end
        end
        local target = math.max(1,math.min(#groups,rowIndex+value))
        if target == rowIndex then return id, items, index end
        table.insert(groups,target,table.remove(groups,rowIndex))
        items = {}
        for _, members in ipairs(groups) do
            for _, item in ipairs(members) do items[#items+1] = item end
        end
        RebuildLinks(items,rows)
    elseif action == "move" then
        if not PublicNumber(value) or value ~= math.floor(value) then return nil, "invalid-resource-order" end
        local rows = BuildRows(items)
        local target = math.max(1, math.min(#items, index + value))
        if rows[items[target].id] ~= rows[id] then
            local targetRow = rows[items[target].id]
            -- A member crossing rows lands outside the destination row, never
            -- between its existing linked members.
            if target > index then
                while target < #items and rows[items[target + 1].id] == targetRow do target = target + 1 end
            else
                while target > 1 and rows[items[target - 1].id] == targetRow do target = target - 1 end
            end
            rows[id] = {}
        end
        table.insert(items, target, table.remove(items, index))
        RebuildLinks(items, rows)
    elseif action == "remove" then
        local rows = BuildRows(items)
        table.remove(items, index)
        RebuildLinks(items, rows)
    elseif action == "progress" or action == "edit" then
        local custom = config.customById and config.customById[id]
        local progress = YHUD:NormalizeBarProgress(action == "edit" and value.progress or value)
        local caps = custom and self:Capabilities(custom.entry)
        if not custom or (not caps or not caps[progress.source]) and progress.source ~= custom.progress.source then
            return nil, "unsupported-resource-source"
        end
        custom.progress = progress
        if action == "edit" and type(value.name) == "string" then custom.name = BoundedText(value.name, 160) end
        config.settingsByResource[id] = YHUD:NormalizeResourceSetting(config.settingsByResource[id], id,
            nil, nil, nil, self:GetDefinition(id, scoped))
    else return nil, "invalid-resource-action" end
    local stored = {}
    for _, item in ipairs(editorDirection == "up" and ReverseRows(items) or items) do
        if item.id == "swingHands" then
            stored[#stored + 1] = { id = "swingMainHand", enabled = item.enabled, joinPrevious = item.joinPrevious }
            stored[#stored + 1] = { id = "swingOffHand", enabled = item.enabled }
        else stored[#stored + 1] = item end
    end
    self:StoreItems(scoped, classFile, specID, formKey, stored)
    -- Deleting the final membership releases its private source and styles.
    if action == "remove" and self:IsCustom(id) then
        local used = false
        for _, list in pairs(config.itemsByContext) do
            for _, item in ipairs(list) do if item.id == id then used = true end end
        end
        if not used then config.customById[id] = nil; config.settingsByResource[id] = nil end
    end
    model:MarkResourceGroupChanged(draft, groupId)
    return id, items, index
end

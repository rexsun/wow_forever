local _, YUI = ...
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Service = YHUD.KeybindText or {}
YHUD.KeybindText = Service

local UPDATED_EVENT = "YUI_YHUD_KEYBINDS_UPDATED"
local MAX_CHARACTERS = 16

local function PositiveInteger(value)
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return math.floor(value)
end

local function SanitizeText(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%z\1-\31\127]", "")
    local count = 0
    local last = 0
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 128 or byte >= 194 then
            count = count + 1
            if count > MAX_CHARACTERS then break end
        end
        last = index
    end
    return value:sub(1, last)
end

local function DisplayText(value)
    value = SanitizeText(value)
    if not value or value == "" then return nil end
    return (value:gsub("|", "||"))
end

local function IsSpellEntry(entry)
    if type(entry) ~= "table" then return false end
    if YHUD:GetEntrySemantic(entry) ~= "cooldown" then return false end
    local sourceType = entry.sourceType
    return sourceType ~= "item-cooldown"
        and sourceType ~= "yhud.inventory-slot-cooldown"
        and not entry.itemId
        and not entry.itemID
        and not entry.slotId
end

local function Identity(monitor, entry, binding)
    if binding then
        if binding.keybindSpellEligible == false then return nil, nil end
        local stable = PositiveInteger(binding.baseSpellId)
            or PositiveInteger(binding.spellId)
            or PositiveInteger(binding.overrideSpellId)
        local runtime = PositiveInteger(binding.spellId)
            or PositiveInteger(binding.overrideSpellId)
            or stable
        return stable, runtime
    end
    if not IsSpellEntry(entry) then return nil, nil end
    local stable = PositiveInteger(monitor and monitor._yhudBundleSpellID)
        or PositiveInteger(entry.spellId)
        or PositiveInteger(entry.spellID)
        or PositiveInteger(entry.baseSpellId)
        or PositiveInteger(entry.overrideSpellId)
        or PositiveInteger(entry.runtimeSpellId)
    local runtime = PositiveInteger(monitor and monitor._yhudRuntimeSpellID)
        or PositiveInteger(entry.runtimeSpellId)
        or PositiveInteger(entry.overrideSpellId)
        or PositiveInteger(entry.spellId)
        or PositiveInteger(entry.spellID)
        or stable
    return stable, runtime
end

local function ReadOverride(overrides, ...)
    if type(overrides) ~= "table" then return nil, nil end
    for index = 1, select("#", ...) do
        local spellID = PositiveInteger(select(index, ...))
        if spellID and overrides[spellID] ~= nil then
            return overrides[spellID], spellID
        end
    end
    return nil, nil
end

local function ReadAutomatic(...)
    local resolver = YHUD.KeybindResolver
    if not (resolver and resolver.Get) then return nil, nil end
    for index = 1, select("#", ...) do
        local spellID = PositiveInteger(select(index, ...))
        if spellID then
            local candidate = resolver:Get(spellID)
            if candidate and type(candidate.text) == "string" then
                return candidate.text, spellID
            end
        end
    end
    return nil, nil
end

function Service:Sanitize(value)
    return SanitizeText(value)
end

function Service:GetIdentity(monitor, entry, binding)
    return Identity(monitor, entry, binding)
end

function Service:Resolve(style, monitor, entry, binding)
    style = type(style) == "table" and style or {}
    local mode = style.keybindTextMode
    if mode == "off" then return nil, "off" end
    local stable, runtime = Identity(monitor, entry, binding)
    if not stable then return nil, "unsupported" end
    local override, overrideID = ReadOverride(
        style.keybindTextOverrides,
        stable,
        runtime,
        entry and entry.overrideSpellId,
        entry and entry.spellId,
        binding and binding.overrideSpellId
    )
    if override ~= nil then
        return DisplayText(override), override == "" and "hidden" or "manual",
            stable, overrideID
    end
    if mode == "manual" then return nil, "manual-empty", stable end
    local automatic, resolvedID = ReadAutomatic(
        runtime,
        stable,
        entry and entry.overrideSpellId,
        entry and entry.spellId,
        binding and binding.overrideSpellId
    )
    return DisplayText(automatic), automatic and "auto" or "missing",
        stable, resolvedID
end

function Service:GetAutomatic(monitor, entry, binding)
    local stable, runtime = Identity(monitor, entry, binding)
    if not stable then return nil, nil end
    local text = ReadAutomatic(
        runtime,
        stable,
        entry and entry.overrideSpellId,
        entry and entry.spellId,
        binding and binding.overrideSpellId
    )
    return SanitizeText(text), stable
end

local function SpellName(spellID, fallback)
    local spell = YUI.API and YUI.API.Spell
    local name = spell and spell.GetName and spell.GetName(spellID)
    if type(name) == "string" and name ~= "" then return name end
    return fallback or tostring(spellID)
end

local function SpellTexture(spellID)
    local spell = YUI.API and YUI.API.Spell
    return spell and spell.GetTexture and spell.GetTexture(spellID) or nil
end

function Service:BuildRows(profile, groupId)
    local rows, seen = {}, {}
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if not (group and group.layout == "icons") then return rows end
    local style = YHUD:GetIconGroupStyle(profile, groupId)
    local function Append(monitor)
        local entry = monitor and profile.entries
            and profile.entries[monitor.entryKey]
        local stable = Identity(monitor, entry)
        if not stable or seen[stable] then return end
        seen[stable] = true
        local automatic = self:GetAutomatic(monitor, entry)
        local override = style.keybindTextOverrides[stable]
        local status, effective
        if override ~= nil then
            status = override == "" and "hidden" or "manual"
            effective = override
        elseif style.keybindTextMode == "manual" then
            status = "manual-empty"
            effective = ""
        else
            status = automatic and "auto" or "missing"
            effective = automatic or ""
        end
        rows[#rows + 1] = {
            spellID = stable,
            name = SpellName(stable, entry and entry.name),
            icon = SpellTexture(stable),
            entry = entry,
            automatic = automatic,
            override = override,
            effective = effective,
            status = status,
        }
    end
    local view = YHUD.View
    local runtime = view and view.groups and view.groups[groupId]
    if runtime and view.desiredMonitors then
        for index = 1, runtime.monitorCount or 0 do
            Append(view.desiredMonitors[runtime.monitorIds[index]])
        end
    end
    if #rows == 0 then
        for index = 1, #(group.monitors or {}) do
            Append(profile.monitors and profile.monitors[group.monitors[index]])
        end
    end
    return rows
end

function Service:OnResolverUpdated()
    if not self.active then return end
    local startedAt = type(_G.debugprofilestop) == "function"
        and _G.debugprofilestop() or nil
    local visited, writes = 0, 0
    if YHUD.View and YHUD.View.RefreshKeybindTexts then
        local count, changed = YHUD.View:RefreshKeybindTexts()
        visited = visited + (count or 0)
        writes = writes + (changed or 0)
    end
    if YHUD.NativeBridge and YHUD.NativeBridge.RefreshKeybindTexts then
        local count, changed = YHUD.NativeBridge:RefreshKeybindTexts()
        visited = visited + (count or 0)
        writes = writes + (changed or 0)
    end
    if YHUD.IsPerformanceDiagnosticsEnabled
        and YHUD:IsPerformanceDiagnosticsEnabled() then
        self.stats = self.stats or {
            refreshes = 0,
            visited = 0,
            writes = 0,
            elapsedMS = 0,
        }
        local stats = self.stats
        stats.refreshes = stats.refreshes + 1
        stats.visited = stats.visited + visited
        stats.writes = stats.writes + writes
        if startedAt then
            stats.elapsedMS = stats.elapsedMS
                + math.max(0, _G.debugprofilestop() - startedAt)
        end
    end
end

function Service:Enable()
    if self.active then return true end
    self.active = true
    if YUI.Event and YUI.Event.On then
        YUI.Event:On(UPDATED_EVENT, "OnResolverUpdated", self, {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.KeybindText",
        })
    end
    return true
end

function Service:Disable()
    self.active = false
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(self) end
    self.stats = nil
    return true
end

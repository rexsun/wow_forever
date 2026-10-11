local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Resolver = YHUD.KeybindResolver or {}
YHUD.KeybindResolver = Resolver

local ActionBar = YUI.API and YUI.API.ActionBar
local Security = YUI.API and YUI.API.Security
local tinsert = table.insert
local tsort = table.sort

local REBUILD_DELAY = 0.20
local UPDATED_EVENT = "YUI_YHUD_KEYBINDS_UPDATED"
local HARD_FAILURES = {
    ["api-error"] = true,
    ["api-unavailable"] = true,
    ["invalid-action-type"] = true,
    ["invalid-spell"] = true,
    ["restricted"] = true,
}
local STATIC_COMMANDS = {
    cast = true,
    castsequence = true,
    castrandom = true,
    use = true,
    userandom = true,
}
local NATIVE_FIXED_BARS = {
    { prefix = "MULTIACTIONBAR1BUTTON", firstSlot = 61, sourceRank = 100 },
    { prefix = "MULTIACTIONBAR2BUTTON", firstSlot = 49, sourceRank = 100 },
    { prefix = "MULTIACTIONBAR3BUTTON", firstSlot = 25, sourceRank = 100 },
    { prefix = "MULTIACTIONBAR4BUTTON", firstSlot = 37, sourceRank = 100 },
    { prefix = "MULTIACTIONBAR5BUTTON", firstSlot = 145, sourceRank = 100 },
    { prefix = "MULTIACTIONBAR6BUTTON", firstSlot = 157, sourceRank = 100 },
    { prefix = "MULTIACTIONBAR7BUTTON", firstSlot = 169, sourceRank = 100 },
}
local REBUILD_EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_HIDEGRID",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "GAME_PAD_ACTIVE_CHANGED",
    "GAME_PAD_CONNECTED",
    "GAME_PAD_DISCONNECTED",
    "ADDON_LOADED",
    "PLAYER_REGEN_ENABLED",
}

Resolver.providers = Resolver.providers or {}
Resolver.cache = Resolver.cache or {}
Resolver.candidates = Resolver.candidates or {}
Resolver.generation = Resolver.generation or 0
Resolver.active = Resolver.active == true

local function IsSecretValue(value)
    if Security and Security.IsSecretValue then
        return Security.IsSecretValue(value) == true
    end
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function SafeNumber(value)
    if IsSecretValue(value) or value == nil then return nil end
    local ok, numberValue = pcall(tonumber, value)
    if not ok or IsSecretValue(numberValue) or not numberValue then return nil end
    return numberValue
end

local function SafeString(value)
    if IsSecretValue(value) or type(value) ~= "string" then return nil end
    return value
end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NowMS()
    if type(debugprofilestop) ~= "function" then return 0 end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or 0
end

local function InCombat()
    if Security and Security.InCombatLockdown then
        local ok, value = pcall(Security.InCombatLockdown)
        return ok and value == true
    end
    if type(InCombatLockdown) == "function" then
        local ok, value = pcall(InCombatLockdown)
        return ok and value == true
    end
    return false
end

local function CandidateLess(left, right)
    if left.rank ~= right.rank then return left.rank < right.rank end
    if left.providerPriority ~= right.providerPriority then
        return left.providerPriority < right.providerPriority
    end
    if left.buttonOrder ~= right.buttonOrder then
        return left.buttonOrder < right.buttonOrder
    end
    if left.providerId ~= right.providerId then
        return left.providerId < right.providerId
    end
    if left.sourceId ~= right.sourceId then
        return left.sourceId < right.sourceId
    end
    return left.slot < right.slot
end

local function CacheEquals(left, right)
    for spellID, candidate in pairs(left) do
        local other = right[spellID]
        if not other
            or candidate.text ~= other.text
            or candidate.rawKey ~= other.rawKey
            or candidate.providerId ~= other.providerId
            or candidate.sourceId ~= other.sourceId
            or candidate.buttonId ~= other.buttonId
            or candidate.kind ~= other.kind
            or candidate.slot ~= other.slot then
            return false
        end
    end
    for spellID in pairs(right) do
        if left[spellID] == nil then return false end
    end
    return true
end

local function ResolveSpellToken(token)
    token = Trim(token)
    token = token:gsub("^!+", "")
    local explicitID = token:match("^[Ss][Pp][Ee][Ll][Ll]:(%d+)$")
    if explicitID then
        explicitID = SafeNumber(explicitID)
        return explicitID and explicitID > 0 and math.floor(explicitID) or nil
    end
    if token == "" or token:match("^%d+$") or token:lower():match("^item:") then
        return nil
    end

    local modern = _G.C_Spell and _G.C_Spell.GetSpellInfo
    if type(modern) == "function" then
        local ok, info = pcall(modern, token)
        if ok and not IsSecretValue(info) and type(info) == "table" then
            local spellID = SafeNumber(info.spellID)
            if spellID and spellID > 0 then return math.floor(spellID) end
        end
    end
    if type(_G.GetSpellInfo) == "function" then
        local ok, _, _, _, _, _, _, spellID = pcall(_G.GetSpellInfo, token)
        if ok and not IsSecretValue(spellID) then
            spellID = SafeNumber(spellID)
            if spellID and spellID > 0 then return math.floor(spellID) end
        end
    end
    return nil
end

local function ParseMacroBody(body, output)
    output = output or {}
    if IsSecretValue(body) or type(body) ~= "string" then
        return output, "restricted"
    end
    local seen = {}
    for line in body:gmatch("[^\r\n]+") do
        local command, arguments = line:match("^%s*/([%a]+)%s+(.+)$")
        command = command and command:lower() or nil
        if command and STATIC_COMMANDS[command] then
            for branch in arguments:gmatch("[^;]+") do
                branch = Trim(branch:gsub("%b[]", ""))
                if command == "castsequence" then
                    branch = branch:gsub("^[Rr][Ee][Ss][Ee][Tt]%s*=%s*[^%s]+%s*", "")
                end
                for token in branch:gmatch("[^,]+") do
                    local spellID = ResolveSpellToken(token)
                    if spellID and not seen[spellID] then
                        seen[spellID] = true
                        output[#output + 1] = spellID
                    end
                end
            end
        end
    end
    return output, nil
end

local function AddAliasID(aliasSet, value)
    value = SafeNumber(value)
    if value and value > 0 then aliasSet[math.floor(value)] = true end
end

local function AddSpellAliases(spellID, aliasSet)
    AddAliasID(aliasSet, spellID)
    local spellAPI = _G.C_Spell
    if not spellAPI then return end
    for _, method in ipairs({ "GetBaseSpell", "GetOverrideSpell" }) do
        local reader = spellAPI[method]
        if type(reader) == "function" then
            local ok, value = pcall(reader, spellID)
            if ok and not IsSecretValue(value) then AddAliasID(aliasSet, value) end
        end
    end
end

local function MarkFailure(build, providerID, reason)
    local stats = build.providerStats[providerID]
    stats.failures = stats.failures + 1
    stats.lastFailure = reason
    if HARD_FAILURES[reason] then build.complete = false end
end

function Resolver:RegisterProvider(provider)
    if type(provider) ~= "table" or type(provider.id) ~= "string"
        or type(provider.Enumerate) ~= "function" then
        return false, "invalid-provider"
    end
    self.providers[provider.id] = provider
    return true
end

function Resolver:AddCandidate(build, provider, entry, spellID, kind, kindRank, binding)
    spellID = SafeNumber(spellID)
    if not spellID or spellID <= 0 then return end
    spellID = math.floor(spellID)
    local rawKey = binding and binding.primaryKey or entry.rawKey
    local text = binding and binding.primaryText or nil
    if not rawKey then return end
    if not text and ActionBar and ActionBar.FormatBindingKey then
        local reason
        text, reason = ActionBar:FormatBindingKey(rawKey)
        if not text then
            MarkFailure(build, provider.id, reason)
            return
        end
    end
    text = text or rawKey

    local candidate = {
        spellID = spellID,
        rawKey = rawKey,
        text = text,
        secondaryKey = binding and binding.secondaryKey or nil,
        secondaryText = binding and binding.secondaryText or nil,
        providerId = provider.id,
        providerPriority = provider.priority or 100,
        sourceId = entry.sourceId or provider.id,
        sourceRank = entry.sourceRank or 500,
        buttonId = tostring(entry.buttonId or entry.slot or ""),
        buttonOrder = SafeNumber(entry.buttonOrder) or SafeNumber(entry.buttonId) or 9999,
        slot = math.floor(SafeNumber(entry.slot) or 0),
        kind = kind,
    }
    candidate.rank = kindRank + candidate.sourceRank

    local aliases = {}
    AddSpellAliases(spellID, aliases)
    for aliasID in pairs(aliases) do
        local list = build.candidates[aliasID]
        if not list then
            list = {}
            build.candidates[aliasID] = list
        end
        local duplicate = false
        for index = 1, #list do
            local current = list[index]
            if current.providerId == candidate.providerId
                and current.sourceId == candidate.sourceId
                and current.buttonId == candidate.buttonId
                and current.rawKey == candidate.rawKey
                and current.kind == candidate.kind then
                duplicate = true
                break
            end
        end
        if not duplicate then list[#list + 1] = candidate end
    end
    build.candidateCount = build.candidateCount + 1
end

function Resolver:ConsumeEntry(build, provider, entry)
    local providerStats = build.providerStats[provider.id]
    providerStats.entries = providerStats.entries + 1
    local binding
    if entry.rawKey then
        binding = { primaryKey = SafeString(entry.rawKey) }
        if not binding.primaryKey then
            MarkFailure(build, provider.id, "restricted")
            return
        end
    elseif entry.bindingCommand and ActionBar and ActionBar.ReadBinding then
        local reason
        binding, reason = ActionBar:ReadBinding(entry.bindingCommand)
        if not binding then
            if reason ~= "unbound" then MarkFailure(build, provider.id, reason) end
            return
        end
    else
        MarkFailure(build, provider.id, "api-unavailable")
        return
    end
    providerStats.bound = providerStats.bound + 1

    local identity, identityReason = ActionBar:ReadSlotIdentity(entry.slot)
    if not identity then
        if identityReason ~= "empty" then MarkFailure(build, provider.id, identityReason) end
        return
    end
    providerStats.actions = providerStats.actions + 1
    if identity.spellID then
        self:AddCandidate(build, provider, entry, identity.spellID, "direct", 0, binding)
        return
    end
    if identity.actionType ~= "macro" then return end

    if identity.currentSpellID then
        self:AddCandidate(
            build, provider, entry, identity.currentSpellID,
            "macro-current", 10000, binding
        )
    end
    if not identity.macroIndex then return end
    local body, bodyReason = ActionBar:ReadMacroBody(identity.macroIndex)
    if not body then
        if bodyReason ~= "unavailable" then MarkFailure(build, provider.id, bodyReason) end
        return
    end
    local spellIDs, parseReason = ParseMacroBody(body)
    if parseReason then
        MarkFailure(build, provider.id, parseReason)
        return
    end
    for index = 1, #spellIDs do
        self:AddCandidate(
            build, provider, entry, spellIDs[index],
            "macro-static", 20000, binding
        )
    end
end

local NativeProvider = {
    id = "native",
    priority = 100,
}

function NativeProvider:Enumerate(resolver, build)
    for barIndex = 1, #NATIVE_FIXED_BARS do
        local definition = NATIVE_FIXED_BARS[barIndex]
        for buttonIndex = 1, 12 do
            resolver:ConsumeEntry(build, self, {
                slot = definition.firstSlot + buttonIndex - 1,
                bindingCommand = definition.prefix .. buttonIndex,
                sourceId = "native:fixed:" .. barIndex,
                sourceRank = definition.sourceRank,
                buttonId = barIndex .. ":" .. buttonIndex,
                buttonOrder = (barIndex * 100) + buttonIndex,
            })
        end
    end
    for buttonIndex = 1, 12 do
        resolver:ConsumeEntry(build, self, {
            slot = buttonIndex,
            bindingCommand = "ACTIONBUTTON" .. buttonIndex,
            sourceId = "native:main-home",
            sourceRank = 200,
            buttonId = "home:" .. buttonIndex,
            buttonOrder = 800 + buttonIndex,
        })
    end
    for page = 7, 11 do
        for buttonIndex = 1, 12 do
            resolver:ConsumeEntry(build, self, {
                slot = ((page - 1) * 12) + buttonIndex,
                bindingCommand = "ACTIONBUTTON" .. buttonIndex,
                sourceId = "native:bonus:" .. page,
                sourceRank = 300 + page,
                buttonId = page .. ":" .. buttonIndex,
                buttonOrder = (page * 100) + buttonIndex,
            })
        end
    end
    return true
end

local YActionBarProvider = {
    id = "yactionbar",
    priority = 0,
}

local function ReadYActionBarSlot(button, meta)
    if not button then return nil, "unavailable" end
    if type(button.GetAttribute) == "function" then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if not ok then return nil, "api-error" end
        if IsSecretValue(value) then return nil, "restricted" end
        local slot = SafeNumber(value)
        if slot and slot > 0 then return math.floor(slot), nil end
    end
    local slot = SafeNumber(button.action) or SafeNumber(button.yabSlot)
        or SafeNumber(meta and meta.slot)
    if slot and slot > 0 then return math.floor(slot), nil end
    return nil, "unavailable"
end

function YActionBarProvider:Enumerate(resolver, build)
    local product = YUI.YActionBar
    local manager = product and product.BarManager
    local factory = product and product.SecureFactory
    if not (manager and type(manager.buttonsByKey) == "table" and factory) then
        return false, "unavailable"
    end

    local keys = {}
    for buttonKey in pairs(manager.buttonsByKey) do
        if type(buttonKey) == "string" then keys[#keys + 1] = buttonKey end
    end
    tsort(keys)
    for order = 1, #keys do
        local buttonKey = keys[order]
        local button = manager.buttonsByKey[buttonKey]
        local meta = factory.GetButtonMeta and factory:GetButtonMeta(button) or nil
        local slot, slotReason = ReadYActionBarSlot(button, meta)
        local command = factory.GetButtonCommand and factory:GetButtonCommand(button)
            or (button and (button.commandName or button.bindingAction))
        command = SafeString(command)
        if slot and slot > 0 and command then
            resolver:ConsumeEntry(build, self, {
                slot = math.floor(slot),
                bindingCommand = command,
                sourceId = "yactionbar:actual",
                sourceRank = 0,
                buttonId = buttonKey,
                buttonOrder = order,
            })
        elseif HARD_FAILURES[slotReason] then
            MarkFailure(build, self.id, slotReason)
        end
    end
    return true
end

Resolver:RegisterProvider(NativeProvider)
Resolver:RegisterProvider(YActionBarProvider)

function Resolver:Build(reason)
    local startedAt = NowMS()
    local build = {
        complete = true,
        cache = {},
        candidates = {},
        candidateCount = 0,
        providerStats = {},
    }
    local providerIDs = {}
    for providerID in pairs(self.providers) do providerIDs[#providerIDs + 1] = providerID end
    tsort(providerIDs, function(left, right)
        local leftProvider = Resolver.providers[left]
        local rightProvider = Resolver.providers[right]
        if leftProvider.priority ~= rightProvider.priority then
            return leftProvider.priority < rightProvider.priority
        end
        return left < right
    end)

    for index = 1, #providerIDs do
        local providerID = providerIDs[index]
        local provider = self.providers[providerID]
        build.providerStats[providerID] = {
            available = true,
            entries = 0,
            bound = 0,
            actions = 0,
            failures = 0,
        }
        local ok, available, providerReason = pcall(provider.Enumerate, provider, self, build)
        if not ok then
            build.complete = false
            local stats = build.providerStats[providerID]
            stats.available = false
            stats.failures = stats.failures + 1
            stats.lastFailure = "provider-error"
        elseif available == false then
            local stats = build.providerStats[providerID]
            stats.available = false
            stats.lastFailure = providerReason or "unavailable"
        end
    end

    for spellID, list in pairs(build.candidates) do
        tsort(list, CandidateLess)
        build.cache[spellID] = list[1]
    end
    build.reason = reason or "unknown"
    build.elapsedMS = math.max(0, NowMS() - startedAt)
    return build
end

function Resolver:RebuildNow(reason)
    if not (ActionBar and ActionBar.ReadSlotIdentity and ActionBar.ReadBinding) then
        self.lastStats = {
            complete = false,
            reason = reason or "unknown",
            lastFailure = "adapter-unavailable",
            elapsedMS = 0,
        }
        return false, "adapter-unavailable"
    end
    local build = self:Build(reason)
    build.changed = false
    if not build.complete then
        self.pendingRetry = true
        self.lastStats = build
        return false, "incomplete"
    end

    build.changed = not CacheEquals(self.cache, build.cache)
    self.cache = build.cache
    self.candidates = build.candidates
    self.generation = self.generation + 1
    self.pendingRetry = false
    self.lastStats = build
    if build.changed and YUI.Event and YUI.Event.Emit then
        YUI.Event:Emit(UPDATED_EVENT, self.generation)
    end
    return true, build.changed and "changed" or "unchanged"
end

function Resolver:CancelPending()
    local timer = self.rebuildTimer
    self.rebuildTimer = nil
    if timer and timer.Cancel then pcall(timer.Cancel, timer) end
end

local function RebuildTimerCallback()
    Resolver.rebuildTimer = nil
    if Resolver.active then Resolver:RebuildNow(Resolver.pendingReason) end
end

function Resolver:ScheduleRebuild(reason)
    self.pendingReason = reason or self.pendingReason or "event"
    self:CancelPending()
    if _G.C_Timer and type(_G.C_Timer.NewTimer) == "function" then
        self.rebuildTimer = _G.C_Timer.NewTimer(REBUILD_DELAY, RebuildTimerCallback)
    elseif self.active then
        self:RebuildNow(self.pendingReason)
    end
end

function Resolver:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= "YUI" and addonName ~= "YUI_YActionBar" then return end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit and unit ~= "player" then return end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not self.pendingRetry then return end
    end
    self:ScheduleRebuild(event)
end

function Resolver:Enable()
    if self.active then return true end
    self.active = true
    if YUI.Event and YUI.Event.On then
        for index = 1, #REBUILD_EVENTS do
            YUI.Event:On(REBUILD_EVENTS[index], "OnEvent", self, {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.KeybindResolver",
            })
        end
    end
    self:ScheduleRebuild("enable")
    return true
end

function Resolver:Disable()
    self.active = false
    self:CancelPending()
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(self) end
    self.cache = {}
    self.candidates = {}
    self.lastStats = nil
    self.pendingReason = nil
    self.pendingRetry = false
    return true
end

function Resolver:Get(spellID)
    spellID = SafeNumber(spellID)
    return spellID and self.cache[math.floor(spellID)] or nil
end

function Resolver:GetCandidates(spellID)
    spellID = SafeNumber(spellID)
    return spellID and self.candidates[math.floor(spellID)] or nil
end

function Resolver:InspectSlot(slot)
    if not (ActionBar and ActionBar.ReadSlotIdentity) then
        return nil, "adapter-unavailable"
    end
    local identity, reason = ActionBar:ReadSlotIdentity(slot)
    if not identity then return nil, reason end
    local result = { identity = identity, staticSpellIDs = {} }
    if identity.macroIndex then
        local body, bodyReason = ActionBar:ReadMacroBody(identity.macroIndex)
        if body then
            ParseMacroBody(body, result.staticSpellIDs)
        else
            result.macroReason = bodyReason
        end
    end
    return result, nil
end

local function Print(message)
    if YUI.Print then YUI:Print(message) else _G.print(message) end
end

local function ProviderSummary(providerID, stats)
    return string.format(
        "%s available=%s entries=%d bound=%d actions=%d failures=%d%s",
        providerID,
        tostring(stats.available == true),
        stats.entries or 0,
        stats.bound or 0,
        stats.actions or 0,
        stats.failures or 0,
        stats.lastFailure and (" last=" .. stats.lastFailure) or ""
    )
end

function Resolver:PrintScan()
    local ok, code = self:RebuildNow("command")
    local stats = self.lastStats or {}
    Print(string.format(
        "YHUD KB scan: ok=%s code=%s changed=%s candidates=%d elapsed=%.2fms",
        tostring(ok), tostring(code), tostring(stats.changed == true),
        stats.candidateCount or 0, stats.elapsedMS or 0
    ))
    local providerIDs = {}
    for providerID in pairs(stats.providerStats or {}) do
        providerIDs[#providerIDs + 1] = providerID
    end
    tsort(providerIDs)
    for index = 1, #providerIDs do
        local providerID = providerIDs[index]
        Print("YHUD KB provider: " .. ProviderSummary(
            providerID, stats.providerStats[providerID]
        ))
    end
end

function Resolver:PrintSpell(spellID)
    spellID = SafeNumber(spellID)
    if not spellID or spellID <= 0 then
        Print("YHUD KB: spellID 无效")
        return
    end
    spellID = math.floor(spellID)
    local list = self:GetCandidates(spellID) or {}
    local winner = self:Get(spellID)
    if winner then
        Print(string.format(
            "YHUD KB %d winner: %s [%s/%s/%s slot=%d rank=%d]",
            spellID, winner.text, winner.providerId, winner.sourceId,
            winner.kind, winner.slot, winner.rank
        ))
    else
        Print("YHUD KB " .. spellID .. ": no candidate")
    end
    for index = 1, #list do
        local candidate = list[index]
        Print(string.format(
            "YHUD KB %d #%d: %s [%s/%s/%s button=%s slot=%d rank=%d]",
            spellID, index, candidate.text, candidate.providerId,
            candidate.sourceId, candidate.kind, candidate.buttonId,
            candidate.slot, candidate.rank
        ))
    end
end

function Resolver:PrintSlot(slot)
    slot = SafeNumber(slot)
    if not slot or slot <= 0 then
        Print("YHUD KB slot: 动作槽无效")
        return
    end
    slot = math.floor(slot)
    local inspection, reason = self:InspectSlot(slot)
    if not inspection then
        Print(string.format("YHUD KB slot %d: %s", slot, tostring(reason)))
        return
    end
    local identity = inspection.identity
    Print(string.format(
        "YHUD KB slot %d: type=%s id=%s subtype=%s spell=%s macro=%s current=%s item=%s",
        slot, tostring(identity.actionType), tostring(identity.actionID),
        tostring(identity.actionSubType), tostring(identity.spellID),
        tostring(identity.macroIndex), tostring(identity.currentSpellID),
        tostring(identity.itemID)
    ))
    if identity.macroIndex then
        Print(string.format(
            "YHUD KB slot %d macro: static=%s reason=%s",
            slot,
            #inspection.staticSpellIDs > 0
                and table.concat(inspection.staticSpellIDs, ",") or "none",
            tostring(inspection.macroReason)
        ))
    end
end

function Resolver:HandleCommand(message)
    message = Trim(message)
    local subcommand, rest = message:match("^(%S+)%s*(.-)$")
    if subcommand ~= "kb" then return false end
    local action, argument = rest:match("^(%S+)%s*(.-)$")
    if not action or action == "" or action == "scan" then
        self:PrintScan()
    elseif action == "slot" then
        self:PrintSlot(argument)
    else
        self:PrintSpell(action)
    end
    return true
end

Resolver._ParseMacroBodyForTests = ParseMacroBody

local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
local Keybinds = {}
YAB.Keybinds = Keybinds

local ACCOUNT_BINDINGS = Enum and Enum.BindingSet and Enum.BindingSet.Account or 1
local CHARACTER_BINDINGS = Enum and Enum.BindingSet and Enum.BindingSet.Character or 2

local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    UNKNOWN = true,
}

local function InCombat()
    return YAB.Adapter and YAB.Adapter:InCombat()
end

local function GetBindingKeys(command, reuse)
    local keys = reuse or {}
    for index in pairs(keys) do
        keys[index] = nil
    end
    if not (command and GetBindingKey) then
        return keys
    end
    local key1, key2 = GetBindingKey(command)
    if key1 and key1 ~= "" then
        keys[#keys + 1] = key1
    end
    if key2 and key2 ~= "" and key2 ~= key1 then
        keys[#keys + 1] = key2
    end
    return keys
end

local function GetBindingSet()
    if not GetCurrentBindingSet then return nil end
    local set = GetCurrentBindingSet()
    if set then return set end
    return nil
end

local function SaveCurrentBindings()
    if not (SaveBindings and GetCurrentBindingSet) then return false end
    local set = GetBindingSet()
    if not set then return false end
    local ok = pcall(SaveBindings, set)
    return ok == true
end

local function FormatBindingText(text)
    if not text or text == "" then return "" end
    local actionBar = YUI.API and YUI.API.ActionBar
    if actionBar and actionBar.FormatBindingKey then
        local formatted = actionBar:FormatBindingKey(text)
        if formatted then return formatted end
    end
    text = text:gsub("CTRL%-", "C")
    text = text:gsub("ALT%-", "A")
    text = text:gsub("SHIFT%-", "S")
    text = text:gsub("META%-", "M")
    text = text:gsub("Mouse Button ", "M")
    text = text:gsub("MOUSEWHEELUP", "MU")
    text = text:gsub("MOUSEWHEELDOWN", "MD")
    text = text:gsub("CAPSLOCK", "Caps")
    text = text:gsub("NUMPADDECIMAL", "N.")
    text = text:gsub("NUMPADPLUS", "N+")
    text = text:gsub("NUMPADMINUS", "N-")
    text = text:gsub("NUMPADMULTIPLY", "N*")
    text = text:gsub("NUMPADDIVIDE", "N/")
    text = text:gsub("NUMPAD", "N")
    text = text:gsub("BUTTON", "M")
    text = text:gsub("PAGEUP", "PU")
    text = text:gsub("PAGEDOWN", "PD")
    text = text:gsub("SPACE", "SpB")
    text = text:gsub("INSERT", "Ins")
    text = text:gsub("HOME", "Hm")
    text = text:gsub("DELETE", "Del")
    return text
end

local function FormatBindingDisplayText(text)
    if not text or text == "" then return "" end
    local formatted = GetBindingText and GetBindingText(text, false) or text
    if not formatted or formatted == "" then formatted = text end

    local modifierCount = 0
    local remaining = text
    while modifierCount < 3 do
        local prefix = remaining:match("^(%u+)%-")
        if prefix ~= "CTRL" and prefix ~= "ALT" and prefix ~= "SHIFT" then break end
        modifierCount = modifierCount + 1
        remaining = remaining:sub(#prefix + 2)
    end
    if modifierCount > 0 then
        formatted = formatted:gsub("%-", "+", modifierCount)
    end
    return formatted
end

local function CopyBindingKeys(keys, reuse)
    local result = reuse or {}
    for index in pairs(result) do
        result[index] = nil
    end
    if type(keys) == "string" then
        if keys ~= "" then result[#result + 1] = keys end
    elseif type(keys) == "table" then
        for _, key in ipairs(keys) do
            if type(key) == "string" and key ~= "" then
                result[#result + 1] = key
                if #result >= 2 then break end
            end
        end
    end
    return result
end

local function CopyBindingMap(source, reuse)
    local result = reuse or {}
    for key in pairs(result) do
        result[key] = nil
    end
    for buttonKey, keys in pairs(source or {}) do
        result[buttonKey] = CopyBindingKeys(keys, {})
    end
    return result
end

local function BindingListsEqual(first, second)
    first = first or {}
    second = second or {}
    if #first ~= #second then return false end
    for index = 1, #first do
        if first[index] ~= second[index] then return false end
    end
    return true
end

local function BindingMapsEqual(first, second)
    for buttonKey, keys in pairs(first or {}) do
        if not BindingListsEqual(keys, second and second[buttonKey]) then return false end
    end
    for buttonKey, keys in pairs(second or {}) do
        if not BindingListsEqual(keys, first and first[buttonKey]) then return false end
    end
    return true
end

local function NormalizeBindingSet(bindingSet)
    bindingSet = tonumber(bindingSet)
    if bindingSet == ACCOUNT_BINDINGS or bindingSet == CHARACTER_BINDINGS then
        return bindingSet
    end
    return nil
end

local function CallBindingAPI(callback, ...)
    if type(callback) ~= "function" then return false, "api unavailable" end
    local ok, result = pcall(callback, ...)
    if not ok or result == false then
        return false, ok and "operation rejected" or result
    end
    return true, result
end

local function RemoveBindingKeysFromValue(value, blockedKeys, preserveLists)
    if type(value) == "string" then
        if blockedKeys[value] then
            return nil, true
        end
        return value, false
    end
    if type(value) ~= "table" then
        return value, false
    end

    local result = {}
    local changed = false
    for _, key in ipairs(value) do
        if type(key) == "string" and key ~= "" then
            if blockedKeys[key] then
                changed = true
            else
                result[#result + 1] = key
            end
        end
    end
    if not changed then
        return value, false
    end
    if not result[1] then
        return nil, true
    end
    return preserveLists and result or result[1], true
end

local function PruneStoredBindingConflicts(bindings, buttonKey, keyList, preserveLists)
    if type(bindings) ~= "table" or type(keyList) ~= "table" then return false end

    local blockedKeys
    for _, key in ipairs(keyList) do
        if type(key) == "string" and key ~= "" then
            blockedKeys = blockedKeys or {}
            blockedKeys[key] = true
        end
    end
    if not blockedKeys then return false end

    local changed = false
    for otherButtonKey, value in pairs(bindings) do
        if otherButtonKey ~= buttonKey then
            local nextValue, removed = RemoveBindingKeysFromValue(value, blockedKeys, preserveLists)
            if removed then
                bindings[otherButtonKey] = nextValue
                changed = true
            end
        end
    end
    return changed
end

function Keybinds:GetButtonKey(barId, index)
    return tostring(barId) .. "." .. tostring(index)
end

local function GetButtonCommand(button)
    if YAB.SecureFactory and YAB.SecureFactory.GetButtonCommand then
        return YAB.SecureFactory:GetButtonCommand(button)
    end
    return button and button.commandName or nil
end

local function UsesNativeStanceBinding(button)
    if Client.heldBindings ~= true or not SetOverrideBinding then return false end
    local factory = YAB.SecureFactory
    local meta = factory and factory.GetButtonMeta and factory:GetButtonMeta(button) or nil
    return meta and meta.nativeSpecial == true and meta.barId == "stance" or false
end

local function GetRuntimeClickButton(button)
    local factory = YAB.SecureFactory
    return factory and factory.detachedButtons and factory.detachedButtons[button] and "Keybind" or "LeftButton"
end

-- Only ordinary spells use the native keyboard path. Flyouts and empowered
-- spells retain the owned button's popup and press/release attributes.
local HELD_BINDING_REFRESH = [[
    if not self:GetAttribute("held-routing-active") then return end
    local target = ...
    local button, entry
    if target then
        button, entry = target, heldBindings[target]
    else
        button, entry = next(heldBindings)
    end
    while button do
        if entry then
            local slot = button:GetAttribute("action")
            local actionType, spellID, subType = GetActionInfo(slot or 0)
            local empowered = (actionType == "spell" or (actionType == "macro" and subType == "spell"))
                and IsPressHoldReleaseSpell(spellID) == true or false
            if button:GetAttribute("pressAndHoldAction") ~= empowered then
                button:SetAttribute("pressAndHoldAction", empowered)
            end
            local native = actionType == "spell" and not empowered
            if entry.native ~= native then
                entry.native = native
                for _, key in ipairs(entry.keys) do
                    if native then
                        self:SetBinding(false, key, entry.command)
                    else
                        self:SetBindingClick(false, key, button:GetName(), "Keybind")
                    end
                end
            end
        end
        if target then break end
        button, entry = next(heldBindings, button)
    end
]]

local HELD_BINDING_ATTRIBUTE = [[
    if name == "action" or name == "yab-flyout-identity" then
        control:RunAttribute("RefreshHeldBindings", self)
    end
]]

local HELD_BINDING_GRID = [[
    if name == "showgrid" then
        control:RunAttribute("RefreshHeldBindings")
    end
]]

-- The outer drag wrapper lets the existing inner wrapper perform PickupAction
-- before reconciling the changed slot. A pickup return in this wrapper would
-- short-circuit its own post body, so use the drag message protocol instead.
local HELD_BINDING_DRAG_PRE = [[
    if control:GetAttribute("held-routing-active") and heldBindings[self] then
        return "message", true
    end
]]

local HELD_BINDING_CLICK_PRE = [[
    if control:GetAttribute("held-routing-active") and heldBindings[self] then
        return nil, true
    end
]]

local HELD_BINDING_EDIT_POST = [[
    if not control:GetAttribute("held-routing-active") or not heldBindings[self] then return end
    control:RunAttribute("RefreshHeldBindings", self)
    local slot = self:GetAttribute("action")
    local hasFlyout = GetActionInfo(slot or 0) == "flyout"
    if self:GetAttribute("yab-flyout-identity") ~= hasFlyout then
        self:SetAttribute("yab-flyout-identity", hasFlyout)
    end
]]

local NATIVE_PRESS_BARS = {
    main = "main", bar2 = "MultiBarBottomLeft", bar3 = "MultiBarBottomRight",
    bar4 = "MultiBarRight", bar5 = "MultiBarLeft", bar6 = "MultiBar5",
    bar7 = "MultiBar6", bar8 = "MultiBar7",
}

local function SetNativePressed(barName, index, down)
    if not Keybinds.heldRoutingActive then return end
    local bars = Keybinds.nativePressButtons
    local buttons = bars and bars[barName]
    local button = buttons and buttons[index]
    if button and YAB.Visuals and YAB.Visuals.SetKeyboardPressedState then
        YAB.Visuals:SetKeyboardPressedState(button, down)
    end
end

local function NativeMainDown(index) SetNativePressed("main", index, true) end
local function NativeMainUp(index) SetNativePressed("main", index, false) end
local function NativeMultiDown(barName, index) SetNativePressed(barName, index, true) end
local function NativeMultiUp(barName, index) SetNativePressed(barName, index, false) end

function Keybinds:ResetHeldBindings()
    self.heldRoutingActive = false
    for _, buttons in pairs(self.nativePressButtons or {}) do
        for index, button in pairs(buttons) do
            if YAB.Visuals and YAB.Visuals.SetKeyboardPressedState then
                YAB.Visuals:SetKeyboardPressedState(button, false)
            end
            buttons[index] = nil
        end
    end
    local owner = self.ownerFrame
    if owner and owner.Execute then
        owner:SetAttribute("held-routing-active", false)
        owner:Execute("heldBindings = table.new()")
    end
end

function Keybinds:RefreshHeldBindings()
    if not self.heldRoutingActive or InCombat() then return end
    self.ownerFrame:Execute([[self:RunAttribute("RefreshHeldBindings")]])
end

function Keybinds:PrepareHeldBindings()
    local system = YUI.API and YUI.API.System
    if Client.heldBindings ~= true or not system or not system.GetCVarBool
        or system.GetCVarBool("ActionButtonUseKeyHeldSpell") ~= true then return false end
    local owner = self:EnsureOwner()
    if not owner.Execute or not owner.WrapScript or not _G.ActionButton1 then return false end
    if not self.nativePressHooked and hooksecurefunc
        and ActionButtonDown and ActionButtonUp and MultiActionButtonDown and MultiActionButtonUp then
        hooksecurefunc("ActionButtonDown", NativeMainDown)
        hooksecurefunc("ActionButtonUp", NativeMainUp)
        hooksecurefunc("MultiActionButtonDown", NativeMultiDown)
        hooksecurefunc("MultiActionButtonUp", NativeMultiUp)
        self.nativePressHooked = true
    end
    owner:SetAttribute("RefreshHeldBindings", HELD_BINDING_REFRESH)
    self.heldBindingHooks = self.heldBindingHooks or setmetatable({}, { __mode = "k" })
    if not self.heldGridHooked then
        owner:WrapScript(_G.ActionButton1, "OnAttributeChanged", HELD_BINDING_GRID)
        self.heldGridHooked = true
    end
    owner:SetAttribute("held-routing-active", true)
    self.heldRoutingActive = true
    return true
end

function Keybinds:RegisterHeldBinding(button, command, keys)
    local factory = YAB.SecureFactory
    if not (factory and factory.detachedButtons and factory.detachedButtons[button]) then return end
    local owner = self.ownerFrame
    local meta = factory.GetButtonMeta and factory:GetButtonMeta(button)
    local barName = meta and NATIVE_PRESS_BARS[meta.barId]
    if barName and meta.index then
        self.nativePressButtons = self.nativePressButtons or {}
        local buttons = self.nativePressButtons[barName] or {}
        self.nativePressButtons[barName] = buttons
        buttons[meta.index] = button
    end
    if not self.heldBindingHooks[button] then
        owner:WrapScript(button, "OnAttributeChanged", HELD_BINDING_ATTRIBUTE)
        owner:WrapScript(button, "OnDragStart", HELD_BINDING_DRAG_PRE, HELD_BINDING_EDIT_POST)
        owner:WrapScript(button, "OnReceiveDrag", HELD_BINDING_DRAG_PRE, HELD_BINDING_EDIT_POST)
        owner:WrapScript(button, "OnClick", HELD_BINDING_CLICK_PRE, HELD_BINDING_EDIT_POST)
        self.heldBindingHooks[button] = true
    end
    owner:SetFrameRef("held-button", button)
    owner:SetAttribute("held-command", command)
    owner:SetAttribute("held-key1", keys[1])
    owner:SetAttribute("held-key2", keys[2])
    owner:Execute([[
        local button = self:GetFrameRef("held-button")
        local entry = table.new()
        entry.command = self:GetAttribute("held-command")
        entry.keys = table.new()
        entry.keys[1] = self:GetAttribute("held-key1")
        entry.keys[2] = self:GetAttribute("held-key2")
        entry.native = false
        heldBindings[button] = entry
        self:RunAttribute("RefreshHeldBindings", button)
    ]])
end

function Keybinds:EnsureOwner()
    if self.ownerFrame then return self.ownerFrame end
    self.ownerFrame = CreateFrame("Frame", "YUI_YActionBar_KeybindOwner", UIParent,
        Client.heldBindings == true and "SecureHandlerBaseTemplate" or nil)
    return self.ownerFrame
end

function Keybinds:GetSystemBindingSuppressionReason()
    if YAB.Adapter and YAB.Adapter.GetSystemBindingSuppressionReason then
        return YAB.Adapter:GetSystemBindingSuppressionReason()
    end
    return nil
end

function Keybinds:SuppressRuntimeBindings(reason)
    local owner = self:EnsureOwner()
    self:ResetHeldBindings()
    if ClearOverrideBindings then
        ClearOverrideBindings(owner)
    end
    self.activeBindings = 0
    self.bindingSuppressed = true
    self.bindingSuppressReason = reason or "system"
    self:ExitBindMode("system")
    return true
end

function Keybinds:GetBindingText(buttonKey)
    local button = self:FindButton(buttonKey)
    local command = GetButtonCommand(button)
    if command and GetBindingKey then
        local key = GetBindingKey(command)
        if key and key ~= "" then
            return FormatBindingText(key)
        end
    end
    local db = YAB.GetDB and YAB:GetDB() or nil
    local stored = db and db.keybinds and db.keybinds.bindings and db.keybinds.bindings[buttonKey] or nil
    return stored and FormatBindingText(stored) or nil
end

function Keybinds:FormatBindingText(text)
    return FormatBindingText(text)
end

function Keybinds:FormatBindingDisplayText(text)
    return FormatBindingDisplayText(text)
end

function Keybinds:GetBindingKeysForButton(buttonKey, limit, reuse)
    local keys = reuse or {}
    for index in pairs(keys) do
        keys[index] = nil
    end

    limit = tonumber(limit) or 2
    if limit < 1 then return keys end

    local button = self:FindButton(buttonKey)
    local command = GetButtonCommand(button)
    if command and GetBindingKey then
        local scratch = self.scratchKeys or {}
        self.scratchKeys = scratch
        GetBindingKeys(command, scratch)
        for _, key in ipairs(scratch) do
            if key and key ~= "" then
                keys[#keys + 1] = key
                if #keys >= limit then return keys end
            end
        end
    end

    local db = YAB.GetDB and YAB:GetDB() or nil
    local stored = db and db.keybinds and db.keybinds.bindings and db.keybinds.bindings[buttonKey] or nil
    if stored and stored ~= "" and #keys < limit then
        local duplicate = false
        for _, existing in ipairs(keys) do
            if existing == stored then
                duplicate = true
                break
            end
        end
        if not duplicate then
            keys[#keys + 1] = stored
        end
    end

    return keys
end

function Keybinds:GetBindingTexts(buttonKey, limit, reuse)
    local keys = self:GetBindingKeysForButton(buttonKey, limit, self.scratchDisplayKeys)
    local result = reuse or {}
    for index in pairs(result) do
        result[index] = nil
    end
    for _, key in ipairs(keys) do
        result[#result + 1] = FormatBindingText(key)
    end
    return result
end

function Keybinds:FindButton(buttonKey)
    if not (YAB.BarManager and YAB.BarManager.buttonsByKey) then return nil end
    return YAB.BarManager.buttonsByKey[buttonKey]
end

function Keybinds:GetCommandForButton(buttonKey)
    local button = self:FindButton(buttonKey)
    return GetButtonCommand(button)
end

function Keybinds:SnapshotSessionBindings(reuse)
    local bindings = reuse or {}
    for buttonKey in pairs(bindings) do
        bindings[buttonKey] = nil
    end
    local commandsByButton = self.sessionCommandsByButton or {}
    local buttonsByCommand = self.sessionButtonsByCommand or {}
    for buttonKey in pairs(commandsByButton) do commandsByButton[buttonKey] = nil end
    for command in pairs(buttonsByCommand) do buttonsByCommand[command] = nil end
    self.sessionCommandsByButton = commandsByButton
    self.sessionButtonsByCommand = buttonsByCommand

    local scratch = self.scratchSessionKeys or {}
    self.scratchSessionKeys = scratch
    for buttonKey, button in pairs(YAB.BarManager and YAB.BarManager.buttonsByKey or {}) do
        local command = GetButtonCommand(button)
        if type(command) == "string" and command ~= "" then
            commandsByButton[buttonKey] = command
            buttonsByCommand[command] = buttonKey
            GetBindingKeys(command, scratch)
            bindings[buttonKey] = CopyBindingKeys(scratch, {})
        end
    end
    return bindings
end

function Keybinds:RefreshSessionBindings(rebase)
    local session = self.session
    if not session then return nil end
    session.bindings = self:SnapshotSessionBindings(session.bindings)
    if rebase == true then
        session.baseline = CopyBindingMap(session.bindings, session.baseline)
        session.bindingChanged = false
        session.dirty = false
        return session
    end
    session.dirty = session.bindingChanged == true or not BindingMapsEqual(session.bindings, session.baseline)
    return session
end

function Keybinds:GetSessionState()
    return self.session
end

function Keybinds:BeginSession(bindingSet)
    if self.session or InCombat() then return false, self.session and "session active" or "combat" end
    if not (GetBindingKey and SetBinding and LoadBindings and SaveBindings) then
        return false, "binding api unavailable"
    end

    local originalBindingSet = NormalizeBindingSet(GetBindingSet()) or ACCOUNT_BINDINGS
    local selectedBindingSet = NormalizeBindingSet(bindingSet) or originalBindingSet
    if selectedBindingSet ~= originalBindingSet then
        local loaded, reason = CallBindingAPI(LoadBindings, selectedBindingSet)
        if not loaded then return false, reason end
    end

    local bindings = self:SnapshotSessionBindings({})
    self.session = {
        originalBindingSet = originalBindingSet,
        selectedBindingSet = selectedBindingSet,
        bindingSet = selectedBindingSet,
        setChanged = selectedBindingSet ~= originalBindingSet,
        bindingChanged = false,
        dirty = false,
        baseline = CopyBindingMap(bindings, {}),
        bindings = bindings,
    }
    return self.session
end

local function SnapshotActionKeys(command)
    return GetBindingKeys(command, {})
end

local function RestoreActionKeys(command, keys)
    if not command then return true end
    local current = SnapshotActionKeys(command)
    for _, key in ipairs(current) do
        local ok = CallBindingAPI(SetBinding, key)
        if not ok then return false end
    end
    for _, key in ipairs(keys or {}) do
        local ok = CallBindingAPI(SetBinding, key, command)
        if not ok then return false end
    end
    return true
end

function Keybinds:ApplySessionKeys(buttonKey, nextKeys, metadata)
    local session = self.session
    if not session or InCombat() then return false, not session and "no session" or "combat" end
    local command = self.sessionCommandsByButton and self.sessionCommandsByButton[buttonKey]
    if not command then return false, "button is not bindable" end

    local previousKeys = SnapshotActionKeys(command)
    if BindingListsEqual(previousKeys, nextKeys) then
        return true, { status = "unchanged", buttonKey = buttonKey }
    end

    local conflictAction = metadata and metadata.conflictAction
    local conflictKeys = conflictAction and conflictAction ~= command and SnapshotActionKeys(conflictAction) or nil
    local function RestoreAffectedActions()
        local restored = RestoreActionKeys(command, previousKeys)
        if conflictKeys then
            restored = RestoreActionKeys(conflictAction, conflictKeys) and restored
        end
        if not restored then session.bindingChanged = true end
        self:RefreshSessionBindings()
        return restored
    end

    for _, key in ipairs(previousKeys) do
        local cleared = CallBindingAPI(SetBinding, key)
        if not cleared then
            RestoreAffectedActions()
            return false, "clear failed"
        end
    end
    for _, key in ipairs(nextKeys or {}) do
        local assigned = CallBindingAPI(SetBinding, key, command)
        if not assigned then
            local restored = RestoreAffectedActions()
            return false, restored and "assign failed" or "assign failed; restore failed"
        end
    end

    session.bindingChanged = true
    self:RefreshSessionBindings()
    if YAB.BarManager and YAB.BarManager.QueueRefresh then
        YAB.BarManager:QueueRefresh("keybind session")
    end
    return true, {
        status = nextKeys and nextKeys[1] and "assigned" or "cleared",
        buttonKey = buttonKey,
        command = command,
        conflictAction = conflictAction,
    }
end

function Keybinds:AssignChord(buttonKey, chord)
    local session = self.session
    if not session then return false, "no session" end
    if type(chord) ~= "string" or chord == "" or IGNORED_KEYS[chord] then return false, "invalid chord" end
    local command = self.sessionCommandsByButton and self.sessionCommandsByButton[buttonKey]
    if not command then return false, "button is not bindable" end

    local current = session.bindings and session.bindings[buttonKey] or {}
    for _, key in ipairs(current) do
        if key == chord then
            return true, { status = "duplicate", buttonKey = buttonKey, command = command }
        end
    end

    local conflictAction = GetBindingAction and GetBindingAction(chord) or nil
    if conflictAction == "" then conflictAction = nil end
    local nextKeys = {}
    if #current >= 2 then
        nextKeys[1] = current[#current]
    elseif current[1] then
        nextKeys[1] = current[1]
    end
    nextKeys[#nextKeys + 1] = chord
    return self:ApplySessionKeys(buttonKey, nextKeys, { conflictAction = conflictAction })
end

function Keybinds:ClearButton(buttonKey)
    return self:ApplySessionKeys(buttonKey, nil)
end

function Keybinds:SwitchBindingSet(targetSet)
    local session = self.session
    targetSet = NormalizeBindingSet(targetSet)
    if not session or not targetSet or InCombat() then return false, not session and "no session" or "invalid state" end
    if targetSet == session.selectedBindingSet then return true, session end
    local loaded, reason = CallBindingAPI(LoadBindings, targetSet)
    if not loaded then return false, reason end

    session.selectedBindingSet = targetSet
    session.bindingSet = targetSet
    session.setChanged = targetSet ~= session.originalBindingSet
    session.bindingChanged = false
    session.bindings = self:SnapshotSessionBindings(session.bindings)
    session.baseline = CopyBindingMap(session.bindings, session.baseline)
    session.dirty = false
    if YAB.BarManager and YAB.BarManager.QueueRefresh then
        YAB.BarManager:QueueRefresh("keybind set")
    end
    return true, session
end

function Keybinds:CommitSession()
    local session = self.session
    if not session or InCombat() then return false, not session and "no session" or "combat" end
    if session.dirty or session.setChanged then
        local saved, reason = CallBindingAPI(SaveBindings, session.selectedBindingSet)
        if not saved then return false, reason end
    end
    self.session = nil
    self:ApplyRuntimeBindings(true)
    if YAB.BarManager and YAB.BarManager.QueueRefresh then
        YAB.BarManager:QueueRefresh("keybind commit")
    end
    return true
end

function Keybinds:RollbackSession(reason)
    local session = self.session
    if not session then return true end
    if InCombat() then return false, "combat" end
    local loaded, loadReason = CallBindingAPI(LoadBindings, session.selectedBindingSet)
    if not loaded then return false, loadReason end
    if session.originalBindingSet ~= session.selectedBindingSet then
        local restored, restoreReason = CallBindingAPI(LoadBindings, session.originalBindingSet)
        if not restored then return false, restoreReason end
    end
    self.session = nil
    self.lastRollbackReason = reason
    self:ApplyRuntimeBindings(true)
    if YAB.BarManager and YAB.BarManager.QueueRefresh then
        YAB.BarManager:QueueRefresh("keybind rollback")
    end
    return true
end

function Keybinds:RepairPrivateBindings()
    if InCombat() or not SetBinding then return false end
    local db = YAB.GetDB and YAB:GetDB() or nil
    if db then
        db.keybinds = db.keybinds or {}
        db.keybinds.bindings = db.keybinds.bindings or {}
    end
    local changed = false
    local scratch = self.scratchKeys or {}
    self.scratchKeys = scratch

    for buttonKey, button in pairs(YAB.BarManager and YAB.BarManager.buttonsByKey or {}) do
        local command = GetButtonCommand(button)
        local name = button and button.GetName and button:GetName()
        if command and name then
            for _, clickCommand in ipairs({ name, "CLICK " .. name .. ":LeftButton" }) do
                GetBindingKeys(clickCommand, scratch)
                for _, key in ipairs(scratch) do
                    if key and key ~= "" then
                        pcall(SetBinding, key, command)
                        changed = true
                    end
                end
            end
            local storedKey = db and db.keybinds and db.keybinds.bindings and db.keybinds.bindings[buttonKey]
            if storedKey and storedKey ~= "" then
                pcall(SetBinding, storedKey, command)
                db.keybinds.bindings[buttonKey] = nil
                changed = true
            end
        end
    end

    if changed then
        SaveCurrentBindings()
    end
    return changed
end

function Keybinds:ApplyRuntimeBindings(skipCompatibilityRepair)
    if InCombat() then
        if YAB.Drivers then
            YAB.Drivers:Queue("apply keybinds", function() Keybinds:ApplyRuntimeBindings() end)
        end
        return false
    end
    local owner = self:EnsureOwner()
    local suppressReason = self:GetSystemBindingSuppressionReason()
    if suppressReason then
        return self:SuppressRuntimeBindings(suppressReason)
    end
    self.bindingSuppressed = false
    self.bindingSuppressReason = nil
    if not self.session and skipCompatibilityRepair ~= true then
        self:RepairPrivateBindings()
    end
    if ClearOverrideBindings then
        ClearOverrideBindings(owner)
    end
    local db = YAB.GetDB and YAB:GetDB() or nil
    local bindings = db and db.keybinds and db.keybinds.bindings
    local active = 0
    self:ResetHeldBindings()
    local heldRouting = self:PrepareHeldBindings()
    if SetOverrideBindingClick then
        local scratch = self.scratchKeys or {}
        self.scratchKeys = scratch
        for buttonKey, button in pairs(YAB.BarManager and YAB.BarManager.buttonsByKey or {}) do
            local name = button and button.GetName and button:GetName()
            local command = GetButtonCommand(button)
            local clickButton = GetRuntimeClickButton(button)
            if name and command then
                GetBindingKeys(command, scratch)
                for _, key in ipairs(scratch) do
                    if key and key ~= "" then
                        local applied
                        if UsesNativeStanceBinding(button) then
                            applied = SetOverrideBinding(owner, false, key, command)
                        else
                            applied = SetOverrideBindingClick(owner, false, key, name, clickButton)
                        end
                        if applied then
                            active = active + 1
                        end
                    end
                end
                if heldRouting and scratch[1] then
                    self:RegisterHeldBinding(button, command, scratch)
                end
            elseif name and type(bindings) == "table" then
                local key = bindings[buttonKey]
                if type(key) == "string" and key ~= "" and SetOverrideBindingClick(owner, false, key, name, clickButton) then
                    active = active + 1
                end
            end
        end
    end
    self.activeBindings = active
    return true
end

function Keybinds:ClearRuntimeBindings()
    if self.ownerFrame and ClearOverrideBindings and not InCombat() then
        self:ResetHeldBindings()
        ClearOverrideBindings(self.ownerFrame)
    end
    self.activeBindings = 0
    self.bindingSuppressed = false
    self.bindingSuppressReason = nil
end

function Keybinds:SetBindings(buttonKey, keys)
    if self.session then return false, "keybind session active" end
    local db = YAB.GetDB and YAB:GetDB() or nil
    if not db then return false end
    db.keybinds = db.keybinds or {}
    db.keybinds.bindings = db.keybinds.bindings or {}
    db.keybinds.pending = db.keybinds.pending or {}
    local button = self:FindButton(buttonKey)
    if not button then return false end
    local command = GetButtonCommand(button)
    local keyList = CopyBindingKeys(keys, self.scratchSetKeys)
    PruneStoredBindingConflicts(db.keybinds.bindings, buttonKey, keyList, false)
    PruneStoredBindingConflicts(db.keybinds.pending, buttonKey, keyList, true)

    if not InCombat() and SetBinding then
        self:RepairPrivateBindings()
        if command then
            local scratch = self.scratchKeys or {}
            self.scratchKeys = scratch
            GetBindingKeys(command, scratch)
            for _, oldKey in ipairs(scratch) do
                if oldKey then
                    pcall(SetBinding, oldKey)
                end
            end
            for _, key in ipairs(keyList) do
                pcall(SetBinding, key, command)
            end
            db.keybinds.bindings[buttonKey] = nil
            SaveCurrentBindings()
        else
            if keyList[1] then
                db.keybinds.bindings[buttonKey] = keyList[1]
            else
                db.keybinds.bindings[buttonKey] = nil
            end
        end
        db.keybinds.pending[buttonKey] = nil
        self:ApplyRuntimeBindings()
    else
        db.keybinds.pending[buttonKey] = keyList[1] and CopyBindingKeys(keyList, {}) or false
        if YAB.Drivers then
            local pendingKeys = CopyBindingKeys(keyList, {})
            YAB.Drivers:Queue("save keybinding", function() Keybinds:SetBindings(buttonKey, pendingKeys) end)
        end
    end
    if YAB.BarManager and YAB.BarManager.QueueRefresh then
        YAB.BarManager:QueueRefresh("keybind")
    end
    return true
end

function Keybinds:SetBinding(buttonKey, key)
    if key == nil or key == false or key == "" then
        return self:SetBindings(buttonKey, nil)
    end
    return self:SetBindings(buttonKey, { key })
end

function Keybinds:HookButton(button, buttonKey)
    if YAB.KeybindMode and YAB.KeybindMode.HookButton then
        return YAB.KeybindMode:HookButton(button, buttonKey)
    end
    return false
end

function Keybinds:EnterBindMode(source, barId)
    return YAB.KeybindMode and YAB.KeybindMode:Enter(source, barId) or false
end

function Keybinds:ExitBindMode(reason)
    return YAB.KeybindMode and YAB.KeybindMode:Cancel(reason or "cancel") or true
end

function Keybinds:GetStats()
    return {
        active = self.activeBindings or 0,
        bindMode = YAB.KeybindMode and YAB.KeybindMode.active == true or false,
        suppressed = self.bindingSuppressed == true,
        suppressReason = self.bindingSuppressReason,
    }
end

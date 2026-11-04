local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or not (YUI.IsRetail or YUI.IsForever) then return end

local GUI = YUI.GUI2
local Action = YUI.API and YUI.API.ActionBar
local Spell = YUI.API and YUI.API.Spell
local Item = YUI.API and YUI.API.Item
if not (GUI and GUI.PaintIconPressedVisual and Action and Action.ReadSlotIdentity) then return end

local Press = { active = false, targets = {}, spells = {}, items = {}, held = {}, pool = {}, colors = {},
    nativeKeys = {}, layers = setmetatable({}, { __mode = "k" }),
    mouseHooks = setmetatable({}, { __mode = "k" }),
    externalButtons = setmetatable({}, { __mode = "k" }), externalHeldKeys = {}, modifiers = {},
    stats = { reads = 0, signals = 0, matched = 0, writes = 0 } }
YHUD.PressFeedback = Press

local function IsSecret(value)
    local security = YUI.API.Security
    return security and security.IsSecretValue and security.IsSecretValue(value)
        or type(issecretvalue) == "function" and issecretvalue(value)
end

local function Number(value)
    if IsSecret(value) then return nil end
    return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
        and value or nil
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function Suppressed()
    local view = YHUD.View
    return not view or not view.active or view.preview or view.designMode or view.layoutEditMode
end

local function Shown(target, record)
    local runtime, native = record.runtime, record.native
    if Suppressed() or runtime.enabled == false or runtime.visibilityAllowed == false
        or not YHUD.View:IsGroupLevelDisplayAllowed(runtime)
        or native and (native.nativeIncluded ~= true or native.visibilitySuppressed == true) then return false end
    local value = target:IsShown()
    local security = YUI.API.Security
    if security and security.SafeBoolean then return security.SafeBoolean(value) == true end
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return value == true
end

function Press:SetShown(record, shown)
    local layer = record.layer
    shown = shown == true
    if not layer or record.shown == shown then return end
    record.shown = shown
    if shown then layer:Show() else layer:Hide() end
    self.stats.writes = self.stats.writes + 1
end

function Press:Prepare(target, record)
    if InCombat() then record.pending = true; return end
    local runtime = record.runtime
    local layer = self.layers[target]
    local created = layer == nil
    if not layer then
        layer = GUI:CreateFrame(target, { mouse = false })
        layer:Hide()
        layer.pressState = { pressedOverlay = GUI:CreateIcon(layer, { crop = false, layer = "OVERLAY" }) }
        layer.pressState.pressedOverlay:SetAllPoints(layer)
        self.layers[target] = layer
    end
    layer:ClearAllPoints()
    layer:SetPoint("CENTER", target, "CENTER", 0, 0)
    layer:SetSize(runtime.itemWidth or runtime.iconWidth or runtime.iconSize or 42,
        runtime.itemHeight or runtime.iconHeight or runtime.iconSize or 42)
    local level, strata = YHUD.View:GetMonitorDisplayLayer(runtime, record.monitorId)
    if level then layer:SetFrameLevel(level + 15) end
    if strata then layer:SetFrameStrata(strata) end
    if GUI.IsIconSkinManaged and GUI:IsIconSkinManaged(layer.pressState.pressedOverlay) then
        record.layer, record.pending = layer, nil
        return
    end
    local maskPath = GUI:GetIconAppearanceMask(runtime.shape, runtime.border)
    if maskPath and layer.CreateMaskTexture then
        if not layer.pressMask then
            layer.pressMask = layer:CreateMaskTexture(nil, "BACKGROUND")
            layer.pressMask:SetAllPoints(layer)
        end
        layer.pressMask:SetTexture(maskPath)
        if not layer.pressMaskAttached then
            layer.pressState.pressedOverlay:AddMaskTexture(layer.pressMask)
            layer.pressMaskAttached = true
        end
    elseif layer.pressMaskAttached then
        layer.pressState.pressedOverlay:RemoveMaskTexture(layer.pressMask)
        layer.pressMaskAttached = nil
    end
    record.layer, record.pending = layer, nil
    if created and GUI.RefreshIconSkinRegion then
        GUI:RefreshIconSkinRegion(target, "Pushed", layer.pressState.pressedOverlay)
    end
end

local function Add(index, id, target, record)
    id = Number(id)
    if not id then return end
    local bucket = index[id]
    if not bucket then bucket = {}; index[id] = bucket end
    bucket[target] = record
    record.index = index
    record.ids[id] = true
end

local function AddSpell(id, target, record)
    id = Number(id)
    if not id then return end
    Add(Press.spells, id, target, record)
    if Spell and Spell.GetBaseSpellID then Add(Press.spells, Spell.GetBaseSpellID(id), target, record) end
    if Spell and Spell.GetOverrideSpellID then Add(Press.spells, Spell.GetOverrideSpellID(id), target, record) end
end

function Press:Release(target)
    local record = self.targets[target]
    if not record then return end
    self:SetShown(record, false)
    -- Retired records can still occur in an input snapshot; never reuse them.
    record.active = false
    record.layer = nil
    self.targets[target] = nil
    for id in pairs(record.ids) do
        local bucket = record.index[id]
        if bucket then
            bucket[target] = nil
            if not next(bucket) then record.index[id] = nil end
        end
    end
end

function Press:Bind(target, runtime, monitor, entry, native, binding)
    if not self.active then return end
    if not (target and runtime and runtime.view == "icon" and monitor and monitor.enabled ~= false
        and entry and YHUD:GetEntrySemantic(entry) == "cooldown") then return self:Release(target) end
    local slot = Number(entry.equipSlot or entry.slotId)
    local itemID = Number(entry.itemId or entry.itemID)
    if slot and Item and Item.GetInventoryItemID then itemID = Number(Item.GetInventoryItemID("player", slot)) end
    binding = binding or native and (native.nativeStyleBinding or native.nativeBinding or native.binding)
    local stable, current
    if not itemID then stable, current = YHUD.KeybindText:GetIdentity(monitor, entry, binding) end
    if not itemID and not stable then return self:Release(target) end
    local previous = self.targets[target]
    local level, strata = YHUD.View:GetMonitorDisplayLayer(runtime, monitor.id)
    if previous and previous.runtime == runtime and previous.entry == entry
        and previous.monitorId == monitor.id and previous.native == native
        and previous.itemID == itemID and previous.stable == stable and previous.current == current
        and previous.shape == runtime.shape and previous.border == runtime.border
        and previous.width == runtime.itemWidth and previous.height == runtime.itemHeight
        and previous.level == level and previous.strata == strata then return end
    self:Release(target)
    local record = { runtime = runtime, monitorId = monitor.id, native = native, active = true, count = 0,
        entry = entry, ids = {}, shape = runtime.shape, border = runtime.border,
        width = runtime.itemWidth, height = runtime.itemHeight, level = level, strata = strata,
        itemID = itemID, stable = stable, current = current }
    if itemID then
        Add(self.items, itemID, target, record)
    else
        AddSpell(stable, target, record)
        AddSpell(current, target, record)
    end
    self.targets[target] = record
    self:Prepare(target, record)
end

function Press:End(source)
    self.externalHeldKeys[source] = nil
    local held = self.held[source]
    if not held then return end
    self.held[source] = nil
    for record in pairs(held) do
        held[record] = nil
        record.count = math.max(0, record.count - 1)
        if record.count == 0 then self:SetShown(record, false) end
    end
    self.pool[#self.pool + 1] = held
end

function Press:Clear()
    for source in pairs(self.held) do self:End(source) end
    for _, record in pairs(self.externalButtons) do
        for _, source in pairs(record.mouse) do source.edge = nil end
    end
end

local function ReadSlot(button)
    if not button then return end
    if button.GetAttribute then
        local ok, slot = pcall(button.GetAttribute, button, "action")
        if not ok then return end
        if type(issecretvalue) == "function" and issecretvalue(slot) then return end
        local id = Number(slot)
        if id then return id end
    end
    return Number(button.action) or Number(button.yabSlot)
end

function Press:Signal(source, button, down, visual)
    if not self.active then return end
    self.stats.signals = self.stats.signals + 1
    if not down then self:End(source); return end
    if self.held[source] or Suppressed() then return end
    local slot = ReadSlot(button)
    if not slot then return end
    self.stats.reads = self.stats.reads + 1
    local identity = Action:ReadSlotIdentity(slot, self.identity)
    if not identity then return end
    self.identity = identity
    local id = Number(identity.spellID or identity.currentSpellID)
    local bucket = id and self.spells[id] or self.items[Number(identity.itemID or identity.currentItemID)]
    if not bucket then return end
    local held = table.remove(self.pool) or {}
    self.held[source] = held
    local product = YUI.YActionBar
    local visuals = product and product.Visuals
    local db = product and product.db
    local effect = visual and visual.pressedEffect or db and db.appearance and db.appearance.pressedEffect
    local colors = visuals and visuals.theme and visuals.theme.colors
    if not colors and GUI.GetPaint then
        local paint = GUI:GetPaint("color.control.pressed")
        self.colors.pressed = paint and (paint.value or paint.fallback)
        colors = self.colors
    end
    for target, record in pairs(bucket) do
        self.stats.matched = self.stats.matched + 1
        if record.active and record.layer and Shown(target, record) then
            held[record] = true
            record.count = record.count + 1
            local state = record.layer.pressState
            state.pressedEffect = effect
            self.stats.writes = self.stats.writes + GUI:PaintIconPressedVisual(state, record.runtime.shape, colors)
            self:SetShown(record, true)
        end
    end
end

local function OnManagedPress(button, down, visual)
    if down and (not visual or visual.isAction ~= true) then return end
    Press:Signal(button, button, down, visual)
end

local function NativeSignal(bar, index, down)
    if not Press.active then return end
    index = Number(index)
    if not index then return end
    local keys = Press.nativeKeys[bar]
    local source = keys and keys[index]
    if not down then if source then Press:End(source) end; return end
    local product = YUI.YActionBar
    local bindings = product and product.Keybinds
    local managed = bindings and bindings.heldRoutingActive and bindings.nativePressButtons
        and bindings.nativePressButtons[bar]
    if managed and managed[index] then return end
    if not keys then keys = {}; Press.nativeKeys[bar] = keys end
    if not source then source = {}; keys[index] = source end
    local button = bar == "main" and GetActionButtonForID and GetActionButtonForID(index)
        or _G[bar .. "Button" .. index]
    if button and button.GetButtonState then
        local ok, state = pcall(button.GetButtonState, button)
        if not ok or type(issecretvalue) == "function" and issecretvalue(state) or state ~= "PUSHED" then return end
    end
    Press:Signal(source, button, true)
end

local function NativeMouseDown(button, mouseButton)
    if Press.active and mouseButton ~= "Keybind" then Press:Signal(button, button, true) end
end

local function NativeMouseEnd(button)
    if Press.active then Press:End(button) end
end

local modifierReaders = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown,
    alt = IsAltKeyDown, meta = IsMetaKeyDown }
local modifierNames = { LSHIFT = "shift", RSHIFT = "shift", LCTRL = "ctrl", RCTRL = "ctrl",
    LALT = "alt", RALT = "alt", LMETA = "meta", RMETA = "meta" }

function Press:RefreshModifiers()
    for name, reader in pairs(modifierReaders) do
        local value = reader()
        self.modifiers[name] = not IsSecret(value) and value == true or nil
    end
end

local function ExternalMouseEnd(button)
    if not Press.active then return end
    local record = Press.externalButtons[button]
    if record then
        for _, source in pairs(record.mouse) do source.edge = nil; Press:End(source) end
    end
end

local function ExternalAllEnd(button)
    if not Press.active then return end
    local record = Press.externalButtons[button]
    if record then Press:End(record.key); ExternalMouseEnd(button) end
end

local function ExternalInput(button, inputButton, down, fromMouse)
    if not Press.active then return end
    local record = Press.externalButtons[button]
    if not record then return end
    if IsSecret(inputButton) or IsSecret(down) then
        ExternalAllEnd(button)
        return
    end
    if type(inputButton) ~= "string" then return end
    down = down == true
    local keyboard = inputButton == "Keybind" or not fromMouse
    local source = record.mouse[inputButton]
    if inputButton ~= "Keybind" then
        if fromMouse then
            if not source then source = {}; record.mouse[inputButton] = source end
            source.edge = down
        else
            -- A physical click reports its mouse edge before PostClick. Consume
            -- that edge once; otherwise this is a forwarded keyboard click,
            -- including bindings using the default LeftButton name. A stale
            -- mouse-up without a click must not swallow the next key-down.
            local edge = source and source.edge
            if source then source.edge = nil end
            if edge == down then return end
        end
    end
    if keyboard then source = record.key end
    if down ~= true then if source then Press:End(source) end; return end
    if source and Press.held[source] or Suppressed() then return end
    local ok, kind = pcall(button.GetAttribute, button, "type")
    if not ok or IsSecret(kind) or kind ~= "action" then return end
    if keyboard then
        local modifiers = Press.modifiers
        source.shift, source.ctrl, source.alt, source.meta = modifiers.shift, modifiers.ctrl, modifiers.alt, modifiers.meta
    end
    Press:Signal(source, button, true)
    if keyboard and Press.held[source] then Press.externalHeldKeys[source] = true end
end

local function ExternalMouseDown(button, inputButton)
    ExternalInput(button, inputButton, true, true)
end

local function ExternalMouseUp(button, inputButton)
    ExternalInput(button, inputButton, false, true)
end

local function ExternalPostClick(button, inputButton, down)
    ExternalInput(button, inputButton, down, false)
end

function Press:OnModifierChanged(_, key, state)
    if not self.active or IsSecret(key) or IsSecret(state) then return end
    local name = modifierNames[key]
    local reader = name and modifierReaders[name]
    if not reader then return end
    local value = reader()
    local pressed = not IsSecret(value) and value == true or nil
    self.modifiers[name] = pressed
    if state ~= 0 or pressed or not next(self.externalHeldKeys) then return end
    -- Releasing a modifier can route the eventual key-up to another binding.
    -- Cancel only keyboard snapshots that actually started with this modifier.
    for source in pairs(self.externalHeldKeys) do
        if source[name] then self:End(source) end
    end
end

function Press:ConnectExternalButton(button)
    if not self.active or not button or not button.HookScript or not button.GetAttribute
        or self.externalButtons[button] then return end
    if InCombat() then self.externalPending = true; return end
    self.externalButtons[button] = { key = {}, mouse = {} }
    -- Observe both click edges without replacing the secure action handler or
    -- writing any state on a foreign protected button.
    button:HookScript("OnMouseDown", ExternalMouseDown)
    button:HookScript("OnMouseUp", ExternalMouseUp)
    button:HookScript("PostClick", ExternalPostClick)
    button:HookScript("OnLeave", ExternalMouseEnd)
    button:HookScript("OnHide", ExternalAllEnd)
    button:HookScript("OnDragStart", ExternalAllEnd)
    button:HookScript("OnReceiveDrag", ExternalAllEnd)
end

local function ExternalButtonCreated(_, button)
    Press:ConnectExternalButton(button)
end

function Press:DisconnectExternalInputs()
    if self.externalLibrary then
        self.externalLibrary.UnregisterCallback(self, "OnButtonCreated")
        self.externalLibrary = nil
    end
    self.externalPending = nil
end

function Press:ConnectExternalInputs()
    if not self.active then return end
    if InCombat() then self.externalPending = true; return end
    self.externalPending = nil
    local stub = _G.LibStub
    local library = stub and stub.GetLibrary and stub:GetLibrary("LibActionButton-1.0-ElvUI", true)
    if not (library and library.buttonRegistry and library.RegisterCallback and library.UnregisterCallback) then return end
    if self.externalLibrary ~= library then
        self:DisconnectExternalInputs()
        self.externalLibrary = library
        library.RegisterCallback(self, "OnButtonCreated", ExternalButtonCreated)
    end
    for button in pairs(library.buttonRegistry) do self:ConnectExternalButton(button) end
end

function Press:ConnectNativeMouse()
    if InCombat() then self.mousePending = true; return end
    for _, prefix in ipairs({ "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
        "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }) do
        for index = 1, 12 do
            local button = _G[prefix .. "Button" .. index]
            if button and button.HookScript and not self.mouseHooks[button] then
                button:HookScript("OnMouseDown", NativeMouseDown)
                button:HookScript("OnMouseUp", NativeMouseEnd)
                button:HookScript("OnLeave", NativeMouseEnd)
                button:HookScript("OnHide", NativeMouseEnd)
                self.mouseHooks[button] = true
            end
        end
    end
    self.mousePending = nil
end

function Press:ConnectInputs()
    self:RefreshModifiers()
    local visuals = YUI.YActionBar and YUI.YActionBar.Visuals
    if visuals and visuals ~= self.visuals then
        if self.visuals and self.visuals.pressObserver == OnManagedPress then self.visuals.pressObserver = nil end
        self.visuals, visuals.pressObserver = visuals, OnManagedPress
    end
    self:ConnectNativeMouse()
    self:ConnectExternalInputs()
    if self.hooked or type(hooksecurefunc) ~= "function" then return end
    if not (ActionButtonDown and ActionButtonUp and MultiActionButtonDown and MultiActionButtonUp) then return end
    hooksecurefunc("ActionButtonDown", function(id) NativeSignal("main", id, true) end)
    hooksecurefunc("ActionButtonUp", function(id) NativeSignal("main", id, false) end)
    hooksecurefunc("MultiActionButtonDown", function(bar, id) NativeSignal(bar, id, true) end)
    hooksecurefunc("MultiActionButtonUp", function(bar, id) NativeSignal(bar, id, false) end)
    self.hooked = true
end

function Press:OnContextChanged(event, addonName)
    if event == "ADDON_LOADED" and (addonName == "ElvUI" or addonName == "ElvUI_Libraries") then
        self:ConnectExternalInputs()
        return
    end
    if event == "ADDON_LOADED" and addonName ~= "YUI" and addonName ~= "YUI_YActionBar"
        and addonName ~= "Blizzard_ActionBar" then return end
    self:Clear()
    self:ConnectInputs()
    self:RefreshTargets()
end

function Press:OnCombatEnded()
    if self.mousePending then self:ConnectNativeMouse() end
    if self.externalPending then self:ConnectExternalInputs() end
    for target, record in pairs(self.targets) do
        if record.pending then self:Prepare(target, record) end
    end
end

function Press:RefreshTargets()
    if not self.active then return end
    local view = YHUD.View
    for target in pairs(self.targets) do self:Release(target) end
    for monitorId, target in pairs(view.byMonitor or {}) do
        local runtime = view.groups and view.groups[target._yhudGroupId]
        local monitor = view.desiredMonitors and view.desiredMonitors[monitorId]
        local entry = monitor and view.profile and view.profile.entries[monitor.entryKey]
        self:Bind(target, runtime, monitor, entry)
    end
    local bridge = YHUD.NativeBridge
    for target, state in pairs(bridge and bridge.frameStates or {}) do
        local binding = state.nativeStyleBinding or state.nativeBinding or state.binding
        local monitor = binding and view.profile and view.profile.monitors[binding.monitorId]
        local entry = monitor and view.profile.entries[monitor.entryKey]
        if state.nativeManaged then self:Bind(target, state.nativeStyleRuntime, monitor, entry, state, binding) end
    end
end

function Press:Sync()
    local view = YHUD.View
    local wanted = view and view.active and YHUD:GetConsolePreference("pressFeedback")
        and not (view.profile and view.profile._yhudInitialResourceOnly)
    if not wanted then
        if self.active then self:Disable() end
        return
    end
    if self.active then return end
    self.active = true
    self:RefreshTargets()
    self:ConnectInputs()
    if YUI.Event then
        for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "PLAYER_EQUIPMENT_CHANGED",
            "SPELLS_CHANGED", "YUI_YHUD_KEYBINDS_UPDATED", "ADDON_LOADED" }) do
            YUI.Event:On(event, "OnContextChanged", self)
        end
        YUI.Event:On("PLAYER_REGEN_ENABLED", "OnCombatEnded", self)
        YUI.Event:On("PLAYER_LEAVING_WORLD", "Clear", self)
        YUI.Event:On("PLAYER_CONTROL_LOST", "Clear", self)
        YUI.Event:On("MODIFIER_STATE_CHANGED", "OnModifierChanged", self)
    end
end

function Press:Disable()
    self.active = false
    if YUI.Event then YUI.Event:OffOwner(self) end
    if self.visuals and self.visuals.pressObserver == OnManagedPress then self.visuals.pressObserver = nil end
    self.visuals = nil
    self:DisconnectExternalInputs()
    self:Clear()
    for target in pairs(self.targets) do self:Release(target) end
    wipe(self.spells); wipe(self.items); wipe(self.pool); wipe(self.nativeKeys)
    self.identity, self.mousePending = nil, nil
end

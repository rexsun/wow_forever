local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not (YHUD and YUI.IsForever) then return end

local GUI = YUI.GUI2
local Spell = YUI.API and YUI.API.Spell
if not (GUI and GUI.CreateStaticIconState and Spell and Spell.GetCurrentState
    and _G.C_Spell and _G.C_Spell.IsCurrentSpell) then return end

-- Only next-melee attacks use this state. IsCurrentSpell also reports normal casts.
local nextSwingByID = { [78] = true, [845] = true, [6807] = true, [2973] = true }
local spellIDsByName
local appearance = { color = GUI.ActionStateLightColor }
local Queue = {
    targets = {}, spells = {}, layers = setmetatable({}, { __mode = "k" }),
    stats = { reads = 0, writes = 0, flushes = 0 },
}
YHUD.QueuedAttack = Queue

local function FindAttack(spellID)
    if nextSwingByID[spellID] then return spellID end
    if not spellID then return nil end
    local baseID = Spell.GetBaseSpellID(spellID)
    if nextSwingByID[baseID] then return baseID end
    local name = Spell.GetName(spellID)
    if not name then return nil end
    if not spellIDsByName then
        spellIDsByName = {}
        for id in pairs(nextSwingByID) do
            local knownName = Spell.GetName(id)
            if knownName then spellIDsByName[knownName] = id end
        end
    end
    return spellIDsByName[name]
end

local function CanPresent()
    local view = YHUD.View
    return view and view.active == true and not (view.preview or view.designMode or view.layoutEditMode)
        and not Queue.worldPaused
end

local function Paint(record, visible)
    local state = record.layer and record.layer.state
    if not state then return end
    local native = record.native
    local shown = visible == true and record.spell.queued == true and not record.pending
        and (not native or native.nativeManaged == true and native.nativeIncluded == true
            and native.visibilitySuppressed ~= true)
    if state:SetGlowShown(shown) then Queue.stats.writes = Queue.stats.writes + 1 end
end

local function Prepare(record)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        record.pending = true
        return
    end
    local target = record.target
    local layer = Queue.layers[target]
    local created = layer == nil
    if created then
        layer = GUI:CreateFrame(target, { mouse = false })
        layer:SetPoint("CENTER", target, "CENTER")
        layer.state = GUI:CreateStaticIconState(layer, record.shape, appearance)
        Queue.layers[target] = layer
    end
    record.layer, record.pending = layer, nil
    layer:SetSize(record.width, record.height)
    if record.level then layer:SetFrameLevel(record.level + 9) end
    if record.strata then layer:SetFrameStrata(record.strata) end

    local texture = layer.state.Texture
    if GUI.IsIconSkinManaged and GUI:IsIconSkinManaged(texture) then return end
    if not created then layer.state:SetGlowShape(record.shape) end
    local ratio = GUI.IconCooldownInsets and GUI.IconCooldownInsets[record.border]
    local inset = ratio and ratio * record.width or 0
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", layer, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", -inset, inset)
    local maskPath = GUI:GetIconAppearanceMask(record.shape, record.border)
    if maskPath and layer.CreateMaskTexture then
        if not layer.stateMask then
            layer.stateMask = layer:CreateMaskTexture(nil, "BACKGROUND")
            layer.stateMask:SetAllPoints(layer)
        end
        layer.stateMask:SetTexture(maskPath)
        if not layer.maskAttached then
            texture:AddMaskTexture(layer.stateMask)
            layer.maskAttached = true
        end
    elseif layer.maskAttached then
        texture:RemoveMaskTexture(layer.stateMask)
        layer.maskAttached = nil
    end
    if created and GUI.RefreshIconSkinRegion then
        GUI:RefreshIconSkinRegion(target, "Checked", texture)
    end
end

function Queue:RefreshPresentation()
    local visible = CanPresent()
    if not visible then
        if self.pending then
            self.pending:Cancel()
            self.pending = nil
        end
        for _, spell in pairs(self.spells) do spell.queued = false end
    end
    for _, record in pairs(self.targets) do Paint(record, visible) end
    if visible then self:RequestRefresh() end
end

local function Flush()
    Queue.pending = nil
    if not CanPresent() then return end
    Queue.stats.flushes = Queue.stats.flushes + 1
    for _, spell in pairs(Queue.spells) do
        Queue.stats.reads = Queue.stats.reads + 1
        local queued = Spell.GetCurrentState(spell.query) == true
        if spell.queued ~= queued then
            spell.queued = queued
            for _, record in pairs(spell.targets) do Paint(record, true) end
        end
    end
end

function Queue:RequestRefresh()
    if self.pending or not next(self.spells) or not CanPresent() then return end
    if _G.C_Timer and _G.C_Timer.NewTimer then
        self.pending = _G.C_Timer.NewTimer(0, Flush)
    else
        Flush()
    end
end

function Queue:OnCombatEnded()
    for _, record in pairs(self.targets) do
        if record.pending then Prepare(record) end
    end
    self:RefreshPresentation()
end

function Queue:OnWorldExit()
    self.worldPaused = true
    self:RefreshPresentation()
end

function Queue:OnWorldEnter()
    self.worldPaused = nil
    self:RequestRefresh()
end

function Queue:Connect()
    local event = YUI.Event
    if not event or self.listening then return end
    self.listening = true
    event:On("ACTIONBAR_UPDATE_STATE", "RequestRefresh", self)
    event:On("PLAYER_SWING", "RequestRefresh", self)
    event:On("UNIT_SPELLCAST_SENT", "RequestRefresh", self, { unit = "player" })
    event:On("UNIT_SPELLCAST_SUCCEEDED", "RequestRefresh", self, { unit = "player" })
    event:On("PLAYER_REGEN_ENABLED", "OnCombatEnded", self)
    event:On("PLAYER_ENTERING_WORLD", "OnWorldEnter", self)
    event:On("PLAYER_LEAVING_WORLD", "OnWorldExit", self)
    event:On("PLAYER_CONTROL_GAINED", "OnWorldEnter", self)
    event:On("PLAYER_CONTROL_LOST", "OnWorldExit", self)
end

function Queue:Disconnect()
    if self.listening then YUI.Event:OffOwner(self) end
    if self.pending then self.pending:Cancel() end
    self.listening, self.pending, self.worldPaused = nil, nil, nil
end

function Queue:Release(target)
    local record = self.targets[target]
    if not record then return end
    Paint(record, false)
    self.targets[target] = nil
    local spell = record.spell
    spell.targets[target] = nil
    if not next(spell.targets) then self.spells[spell.id] = nil end
    if not next(self.spells) then self:Disconnect() end
end

function Queue:Disable()
    for target in pairs(self.targets) do self:Release(target) end
end

function Queue:UpdateTarget(target)
    local record = self.targets[target]
    if record then Paint(record, CanPresent()) end
end

function Queue:Bind(target, runtime, monitor, entry, native, binding)
    local view = YHUD.View
    if not (view and view.active and target and runtime and runtime.view == "icon" and runtime.enabled ~= false and monitor
        and monitor.enabled ~= false and entry and not target._yhudDesignProjection
        and not target._yhudFilteredAuraGlow and not runtime._yhudDesignProjection
        and YHUD:GetEntrySemantic(entry) == "cooldown") then
        return self:Release(target)
    end
    if entry.itemId or entry.itemID or entry.slotId or entry.equipSlot then return self:Release(target) end

    local record = self.targets[target]
    local width = runtime.itemWidth or runtime.iconWidth or runtime.iconSize or 42
    local height = runtime.itemHeight or runtime.iconHeight or runtime.iconSize or 42
    local level, strata = view:GetMonitorDisplayLayer(runtime, monitor.id)
    if record and record.entry == entry and record.binding == binding and record.native == native
        and record.runtime == runtime and record.shape == runtime.shape and record.border == runtime.border
        and record.width == width and record.height == height and record.level == level and record.strata == strata then return end

    local stable, current = YHUD.KeybindText:GetIdentity(monitor, entry, binding)
    local id = FindAttack(current) or FindAttack(stable)
    if not id then return self:Release(target) end
    if record and record.spell.id ~= id then
        self:Release(target)
        record = nil
    end
    local spell = self.spells[id]
    if not spell then
        spell = { id = id, query = Spell.GetName(id) or id, targets = {} }
        self.spells[id] = spell
    end
    if not record then
        record = { target = target, spell = spell, layer = self.layers[target] }
        spell.targets[target], self.targets[target] = record, record
    end
    record.entry, record.binding, record.native, record.runtime = entry, binding, native, runtime
    record.width, record.height, record.level, record.strata = width, height, level, strata
    record.shape, record.border = runtime.shape, runtime.border
    Prepare(record)
    Paint(record, CanPresent())
    self:Connect()
    self:RequestRefresh()
end

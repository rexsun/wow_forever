local _, YUI = ...
local Native = YUI and YUI.NativeInterface
if not (Native and YUI.IsForever and Native.MovableWindows) then return end

local Security = YUI.API.Security
local unpack = unpack or table.unpack
local definitions, session = {}, {}
local states = setmetatable({}, { __mode = "k" })
local byId = setmetatable({}, { __mode = "v" })
local owner, combatOwner = {}, {}
local config, listening, waiting, updatingBagLayout
local stats = { applies = 0, failures = 0 }
for _, definition in ipairs(Native.MovableWindows) do definitions[definition.id] = definition end

local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

-- Strict validation is also used by configuration transfer; runtime repair discards malformed fields.
function Native:NormalizeWindowMovement(value, strict)
    if value == nil then value = {} end
    if type(value) ~= "table" then if strict then return nil end; value = {} end
    local result = {
        enabled = true, requireShift = false, positionMode = "permanent", scaleMode = "permanent", windows = {},
    }
    for key, v in pairs(value) do
        local valid = false
        if key == "enabled" or key == "requireShift" then
            valid = type(v) == "boolean"
        elseif key == "positionMode" then
            valid = v == "off" or v == "session" or v == "permanent"
        elseif key == "scaleMode" then
            valid = v == "session" or v == "permanent"
        elseif key == "windows" then
            valid = type(v) == "table"
        end
        if not valid then
            if strict then return nil end
        elseif key ~= "windows" then result[key] = v end
    end
    if type(value.windows) == "table" then
        for id, entry in pairs(value.windows) do
            if not definitions[id] or type(entry) ~= "table" then
                if strict then return nil end
            else
                local clean = {}
                for key, v in pairs(entry) do
                    local valid = false
                    if key == "enabled" then valid = type(v) == "boolean"
                    elseif key == "scale" then valid = Number(v) and v >= 0.5 and v <= 2.5
                    elseif key == "position" and type(v) == "table" then
                        valid = Number(v.x) and Number(v.y) and v.x >= 0 and v.x <= 1 and v.y >= 0 and v.y <= 1
                        for field in pairs(v) do if field ~= "x" and field ~= "y" then valid = false end end
                    end
                    if valid then
                        if key == "position" then clean.position = { x = v.x, y = v.y }
                        elseif key ~= "enabled" then clean[key] = v end
                    elseif strict then return nil end
                end
                if result.positionMode ~= "permanent" then clean.position = nil end
                if result.scaleMode ~= "permanent" then clean.scale = nil end
                result.windows[id] = clean
            end
        end
    end
    return result
end

function Native:GetWindowMovementConfig()
    local parent = self:GetConfig()
    if type(parent.windowMovement) ~= "table" then parent.windowMovement = self:NormalizeWindowMovement(nil) end
    return parent.windowMovement
end

local function Entry(id)
    local entry = config.windows[id]
    if not entry then entry = {}; config.windows[id] = entry end
    return entry
end

local function Session(id)
    local entry = session[id]
    if not entry then entry = {}; session[id] = entry end
    return entry
end

local function Desired(state, key)
    local mode = key == "position" and config.positionMode or config.scaleMode
    return mode == "permanent" and Entry(state.id)[key] or Session(state.id)[key]
end

local function Active(state)
    return Native.runtimeEnabled and config and config.enabled
end

local function SafeFrame(frame)
    return not frame:IsForbidden() and not (frame.HasSecretValues and frame:HasSecretValues())
end

local function Capture(state)
    if state.original then return true end
    local frame = state.frame
    local scale = frame:GetScale()
    if not Number(scale) or scale <= 0 then return false end
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point = { frame:GetPoint(i) }
        if not Number(point[4]) or not Number(point[5]) then return false end
        points[#points + 1] = point
    end
    if #points == 0 then return false end
    state.original = { points = points, scale = scale, movable = frame:IsMovable(),
        clamped = frame:IsClampedToScreen(), userPlaced = frame:IsUserPlaced() }
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    return true
end

local function SetPosition(state, position)
    local frame = state.frame
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not Number(scale) or not Number(parentScale) or scale <= 0 or parentScale <= 0
        or not Number(width) or not Number(height) or width <= 0 or height <= 0 then return end
    local x, y = position.x * width * parentScale / scale, position.y * height * parentScale / scale
    local point, relative, relativePoint, oldX, oldY = frame:GetPoint(1)
    if Number(oldX) and Number(oldY) and point == "CENTER" and relative == UIParent
        and relativePoint == "BOTTOMLEFT" and oldX == x and oldY == y then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    return true
end

local function Restore(state)
    local original, frame = state.original, state.frame
    if not original then return end
    frame:SetScale(original.scale)
    frame:ClearAllPoints()
    for _, point in ipairs(original.points) do frame:SetPoint(unpack(point)) end
    frame:SetMovable(original.movable)
    frame:SetClampedToScreen(original.clamped)
    frame:SetUserPlaced(original.userPlaced)
    state.original = nil
    return true
end

local Apply, FinishDrag

local function UpdateBagLayout()
    if updatingBagLayout or Security.InCombatLockdown() or type(UpdateContainerFrameAnchors) ~= "function" then return end
    updatingBagLayout = true
    local ok = Security.SafeCall("NativeInterface:window-bag-layout", UpdateContainerFrameAnchors)
    updatingBagLayout = nil
    if not ok then stats.failures = stats.failures + 1 end
end

local function AfterCombat()
    waiting = nil
    YUI.Event:OffOwner(combatOwner)
    Native:RefreshWindowMovement("combat-ended")
end

local function WaitForCombat()
    if waiting then return end
    waiting = true
    YUI.Event:On("PLAYER_REGEN_ENABLED", AfterCombat, combatOwner, { moduleId = Native.MODULE_ID })
end

local function Sync(state)
    if state.writing or state.moving or not Active(state) or not state.frame:IsShown() then return end
    if Security.InCombatLockdown() then WaitForCombat(); return end
    -- Restore before this show/layout call returns; deferring exposes the native position for a frame.
    Apply(state)
end

local function ApplyUnsafe(state)
    local frame = state.frame
    local changed = false
    if state.reset or not Active(state) then
        if state.moving then FinishDrag(state, false) end
        state.handle:Hide()
        changed = Restore(state) or changed
        state.reset = nil
    end
    if not Active(state) or not frame:IsShown() then return changed end
    if not Capture(state) then return changed end
    local scale = Desired(state, "scale")
    local currentScale = frame:GetScale()
    if scale and Number(currentScale) and currentScale ~= scale then
        frame:SetScale(scale)
        changed = true
    end
    local position = Desired(state, "position")
    if position then changed = SetPosition(state, position) or changed end
    if frame:IsUserPlaced() ~= state.original.userPlaced then frame:SetUserPlaced(state.original.userPlaced) end
    if not state.handle:IsShown() then state.handle:Show() end
    return changed
end

Apply = function(state, deferBagLayout)
    if not SafeFrame(state.frame) then return end
    if Security.InCombatLockdown() then WaitForCombat(); return end
    state.writing = true
    local ok, changed = Security.SafeCall("NativeInterface:window-apply", ApplyUnsafe, state)
    state.writing = nil
    stats.applies = stats.applies + 1
    if not ok then stats.failures = stats.failures + 1 end
    if ok and changed and definitions[state.id].bank then
        if not deferBagLayout then UpdateBagLayout() end
        return true
    end
end

local function Save(state, key, value)
    Session(state.id)[key] = value
    local mode = key == "position" and config.positionMode or config.scaleMode
    Entry(state.id)[key] = mode == "permanent" and value or nil
end

FinishDrag = function(state, save, deferBagLayout)
    if not state.moving then return end
    if Security.InCombatLockdown() then WaitForCombat(); return end
    state.writing = true
    state.frame:StopMovingOrSizing()
    state.moving = nil
    state.frame:SetUserPlaced(state.original.userPlaced)
    if save then
        local x, y = state.frame:GetCenter()
        local scale, parentScale = state.frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        if Number(x) and Number(y) and Number(scale) and Number(parentScale) and parentScale > 0
            and Number(width) and Number(height) and width > 0 and height > 0 then
            Save(state, "position", { x = math.max(0, math.min(1, x * scale / parentScale / width)),
                y = math.max(0, math.min(1, y * scale / parentScale / height)) })
        end
    end
    state.writing = nil
    if save and definitions[state.id].bank and state.frame:IsShown() then
        if not deferBagLayout then UpdateBagLayout() end
        return true
    end
end

local function Attach(definition)
    if byId[definition.id] then return end
    local frame = _G[definition.id]
    if not frame or not SafeFrame(frame) then return end
    local title = frame
    if definition.titleKey then title = frame[definition.titleKey] end
    if not title or not SafeFrame(title) then return end
    if Security.InCombatLockdown() then WaitForCombat(); return end
    local level = frame:GetFrameLevel()
    if not Number(level) then return end
    local state = { id = definition.id, frame = frame }
    -- Native template boundary: a small drag strip, never an overlay across interactive content.
    local handle = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate")
    state.handle = handle
    handle:Hide()
    handle:SetPoint("TOPLEFT", title, "TOPLEFT", definition.titleLeft or 65, -3)
    handle:SetPoint("TOPRIGHT", title, "TOPRIGHT", -(definition.titleRight or 40), -3)
    handle:SetHeight(22)
    handle:SetFrameLevel(level + 5)
    handle:EnableMouse(true)
    handle:EnableMouseWheel(true)
    handle:SetScript("OnDragStart", function()
        if not Active(state) or Security.InCombatLockdown() or not SafeFrame(frame)
            or (config.requireShift and not IsShiftKeyDown()) or not Capture(state) then return end
        state.writing = true
        frame:StartMoving()
        frame:SetUserPlaced(state.original.userPlaced)
        state.moving = true
        state.writing = nil
    end)
    handle:SetScript("OnDragStop", function() FinishDrag(state, true) end)
    handle:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then FinishDrag(state, true) end end)
    handle:SetScript("OnMouseWheel", function(_, delta)
        if Active(state) and IsControlKeyDown() and not Security.InCombatLockdown() and SafeFrame(frame) then
            local scale = frame:GetScale()
            if Number(scale) and Number(delta) then
                Native:SetWindowScale(state.id, math.max(0.5, math.min(2.5, scale + delta * 0.1)))
            end
        end
    end)
    frame:HookScript("OnShow", function() Sync(state) end)
    frame:HookScript("OnHide", function()
        FinishDrag(state, true)
        if Active(state) and config.positionMode == "off" then
            Session(state.id).position = nil
            state.reset = true
            Apply(state)
        end
    end)
    hooksecurefunc(frame, "SetPoint", function()
        if Active(state) and Desired(state, "position") then Sync(state) end
    end)
    hooksecurefunc(frame, "SetScale", function()
        if Active(state) and Desired(state, "scale") then Sync(state) end
    end)
    states[frame] = state
    byId[definition.id] = state
end

local function OnAddonLoaded(_, addon)
    for _, definition in ipairs(Native.MovableWindows) do
        if definition.addon == addon then
            Attach(definition)
            if byId[definition.id] then Apply(byId[definition.id]) end
        end
    end
end

function Native:RefreshWindowMovement(reason)
    local parent = self:GetConfig()
    local profileChanged = reason == "profile-changed" or reason == "config-transfer"
    if profileChanged then
        for _, state in pairs(states) do state.reset = true end
        session = {}
    end
    parent.windowMovement = self:NormalizeWindowMovement(parent.windowMovement)
    config = parent.windowMovement
    local enabled = self.runtimeEnabled and config.enabled
    if enabled and not listening then
        listening = true
        YUI.Event:On("ADDON_LOADED", OnAddonLoaded, owner, { moduleId = self.MODULE_ID })
    elseif not enabled and listening then
        listening = nil
        YUI.Event:OffOwner(owner)
    end
    if enabled then
        for _, definition in ipairs(self.MovableWindows) do Attach(definition) end
    end
    local restoreBags = false
    for _, state in pairs(states) do
        if definitions[state.id].bag and (state.reset or not enabled) and state.original then restoreBags = true end
        if state.moving and not Security.InCombatLockdown() then
            restoreBags = FinishDrag(state, not profileChanged and not state.reset, true) or restoreBags
        end
        restoreBags = Apply(state, true) or restoreBags
    end
    if restoreBags then UpdateBagLayout() end
end

function Native:SetWindowMovementOption(key, value)
    config = self:GetWindowMovementConfig()
    if key == "enabled" or key == "requireShift" then
        if type(value) ~= "boolean" then return false end
    elseif key == "positionMode" or key == "scaleMode" then
        if value ~= "permanent" and value ~= "session" and not (key == "positionMode" and value == "off") then return false end
        local field = key == "positionMode" and "position" or "scale"
        if config[key] ~= value then
            for id in pairs(definitions) do
                local current = config[key] == "permanent" and Entry(id)[field] or Session(id)[field]
                Session(id)[field] = value ~= "off" and current or nil
                Entry(id)[field] = value == "permanent" and current or nil
                if value == "off" and byId[id] then byId[id].reset = true end
            end
        end
    else return false end
    config[key] = value
    self:RefreshWindowMovement("option")
    return true
end

function Native:SetWindowScale(id, scale)
    if not definitions[id] or not Number(scale) or scale < 0.5 or scale > 2.5 then return false end
    config = self:GetWindowMovementConfig()
    Save({ id = id }, "scale", scale)
    if byId[id] then Apply(byId[id]) end
    return true
end

function Native:ResetAllWindowMovement()
    config = self:GetWindowMovementConfig()
    session = {}
    for _, entry in pairs(config.windows) do entry.position = nil; entry.scale = nil end
    for _, state in pairs(states) do
        state.reset = true
        if state.moving and not Security.InCombatLockdown() then FinishDrag(state, false) end
    end
    self:RefreshWindowMovement("reset")
end

function Native:GetWindowMovementDiagnostics()
    local attached, active = 0, 0
    for _, state in pairs(states) do
        attached = attached + 1
        if Active(state) then active = active + 1 end
    end
    return { attached = attached, active = active, listener = listening == true, timer = false,
        combatPending = waiting == true, applies = stats.applies, failures = stats.failures }
end

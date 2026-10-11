local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
local Factory = {}
YAB.SecureFactory = Factory

Factory.pools = Factory.pools or { movers = {}, holders = {}, controllers = {}, buttons = {} }
Factory.buttonMeta = Factory.buttonMeta or setmetatable({}, { __mode = "k" })
Factory.strippedButtons = Factory.strippedButtons or setmetatable({}, { __mode = "k" })
Factory.stripCount = Factory.stripCount or 0
Factory.detachedButtons = Factory.detachedButtons or setmetatable({}, { __mode = "k" })
Factory.detachedScriptCount = Factory.detachedScriptCount or 0
Factory.nativeSpecialButtons = Factory.nativeSpecialButtons or setmetatable({}, { __mode = "k" })
Factory.nativeSpecialState = Factory.nativeSpecialState or setmetatable({}, { __mode = "k" })
Factory.nativePetDragGuardInstalled = Factory.nativePetDragGuardInstalled or setmetatable({}, { __mode = "k" })
Factory.nativePetClickRefreshInstalled = Factory.nativePetClickRefreshInstalled or setmetatable({}, { __mode = "k" })
Factory.fallbackPetClickInstalled = Factory.fallbackPetClickInstalled or setmetatable({}, { __mode = "k" })
Factory.nativeSpecialTooltipGuardInstalled = Factory.nativeSpecialTooltipGuardInstalled or setmetatable({}, { __mode = "k" })
Factory.actionPickupClickGuardInstalled = Factory.actionPickupClickGuardInstalled or setmetatable({}, { __mode = "k" })
Factory.actionDragInstalled = Factory.actionDragInstalled or setmetatable({}, { __mode = "k" })
Factory.actionDragRegistered = Factory.actionDragRegistered or setmetatable({}, { __mode = "k" })
Factory.actionDragHideEmpty = Factory.actionDragHideEmpty or setmetatable({}, { __mode = "k" })
Factory.buttonBackend = "owned-actionbar-template-detached/owned-retail-stance-template/native-special-reuse"
Factory.nativeCooldownRegistered = Factory.nativeCooldownRegistered or setmetatable({}, { __mode = "k" })
Factory.nativeCooldownRegisterAttempts = Factory.nativeCooldownRegisterAttempts or 0
Factory.nativeCooldownRegisterFails = Factory.nativeCooldownRegisterFails or 0
Factory.nativeCooldownRegisterAPI = Factory.nativeCooldownRegisterAPI or "none"
Factory.retiredAssistedCombatFrames = Factory.retiredAssistedCombatFrames
    or setmetatable({}, { __mode = "k" })
local NOOP = function() end
local ACTION_FLYOUT_IDENTITY_ATTRIBUTE = "yab-flyout-identity"
local RETAIL_STANCE_BUTTON_CAPACITY = 10
local InitializeActionDragRoot

local function GetYUIFlyoutDirection(button)
    if button and button.GetAttribute then
        local ok, direction = pcall(button.GetAttribute, button, "flyoutDirection")
        if ok and direction then
            return direction
        end
    end
    return "UP"
end

local FULL_HIDDEN_ART_FIELDS = {
    "Icon",
    "icon",
    "SlotArt",
    "SlotBackground",
    "Flash",
    "Border",
    "BorderShadow",
    "FlyoutBorderShadow",
    "NormalTexture",
    "PushedTexture",
    "CheckedTexture",
    "HighlightTexture",
    "Arrow",
    "NewActionTexture",
    "SpellHighlightTexture",
    "SpellHighlightAnim",
    "QuickKeybindHighlightTexture",
    "LevelLinkLockIcon",
    "Count",
    "HotKey",
    "Name",
    "cooldown",
    "Cooldown",
    "chargeCooldown",
    "lossOfControlCooldown",
    "CooldownFlash",
    "AutoCastOverlay",
    "TextOverlayContainer",
    "SpellCastAnimFrame",
    "TargetReticleAnimFrame",
    "InterruptDisplay",
}

local ACTION_SKIN_HIDDEN_FIELDS = {
    "SlotArt",
    "SlotBackground",
    "Flash",
    "Border",
    "BorderShadow",
    "FlyoutBorderShadow",
    "NormalTexture",
    "PushedTexture",
    "CheckedTexture",
    "HighlightTexture",
    "Arrow",
    "NewActionTexture",
    "SpellHighlightTexture",
    "SpellHighlightAnim",
    "QuickKeybindHighlightTexture",
    "LevelLinkLockIcon",
    "CooldownFlash",
    "AutoCastOverlay",
    "SpellCastAnimFrame",
    "TargetReticleAnimFrame",
    "InterruptDisplay",
}

local SPECIAL_SKIN_HIDDEN_FIELDS = {
    "SlotArt",
    "SlotBackground",
    "Flash",
    "Border",
    "BorderShadow",
    "FlyoutBorderShadow",
    "NormalTexture",
    "PushedTexture",
    "CheckedTexture",
    "HighlightTexture",
    "Arrow",
    "NewActionTexture",
    "SpellHighlightTexture",
    "SpellHighlightAnim",
    "QuickKeybindHighlightTexture",
    "LevelLinkLockIcon",
    "CooldownFlash",
    "SpellCastAnimFrame",
    "TargetReticleAnimFrame",
    "InterruptDisplay",
}

local function SafeName(value)
    value = tostring(value or "frame")
    value = value:gsub("[^%w_]", "_")
    return value
end

function Factory:FrameName(kind, id, index)
    local name = "YUI_YActionBar_" .. SafeName(kind) .. "_" .. SafeName(id)
    if index then
        name = name .. "_Button" .. tostring(index)
    end
    return name
end

function Factory:InCombat()
    return YAB.Adapter and YAB.Adapter:InCombat()
end

function Factory:CreateRoot()
    if YAB.Adapter and YAB.Adapter.CanUseSecureRuntime then
        local supported, reason = YAB.Adapter:CanUseSecureRuntime()
        if not supported then return nil, reason end
    end
    if self.root then
        if InitializeActionDragRoot then InitializeActionDragRoot(self.root) end
        return self.root
    end
    if self:InCombat() then return nil, "combat" end
    self.root = CreateFrame("Frame", "YUI_YActionBar_Root", UIParent, "SecureHandlerStateTemplate")
    self.root:SetPoint("CENTER")
    self.root:SetSize(1, 1)
    if self.root.SetFrameStrata then self.root:SetFrameStrata("HIGH") end
    self.root:Show()
    if InitializeActionDragRoot then InitializeActionDragRoot(self.root) end
    return self.root
end

function Factory:CreateHiddenParent()
    if self.hiddenParent then return self.hiddenParent end
    if self:InCombat() then return nil, "combat" end
    local parent = CreateFrame("Frame", "YUI_YActionBar_HiddenParent", UIParent)
    parent:SetAllPoints(UIParent)
    parent:Hide()
    self.hiddenParent = parent
    return parent
end

local function HideRegion(region)
    if not region then return end
    if region.Stop then pcall(region.Stop, region) end
    if region.StopAnimating then pcall(region.StopAnimating, region) end
    if region.SetAlpha then pcall(region.SetAlpha, region, 0) end
    if region.Hide then pcall(region.Hide, region) end
end

local function HideButtonStateTextures(button, checkedTexture)
    if not button then return end
    local getters = {
        "GetNormalTexture",
        "GetPushedTexture",
        "GetCheckedTexture",
        "GetHighlightTexture",
        "GetDisabledTexture",
    }
    for _, getter in ipairs(getters) do
        if button[getter] then
            local ok, region = pcall(button[getter], button)
            if ok and region ~= checkedTexture then HideRegion(region) end
        end
    end
end

local function SuppressActionFlyoutArt(button)
    HideRegion(button and button.Arrow)
    HideRegion(button and button.FlyoutBorderShadow)
    HideRegion(button and button.BorderShadow)
end

local function EnsureActionFlyoutBridge(button)
    if not button then return false end
    if not button.GetPopupDirection then
        button.GetPopupDirection = GetYUIFlyoutDirection
    end
    SuppressActionFlyoutArt(button)
    return type(button.UpdateFlyout) == "function" and type(button.HasPopup) == "function" and type(button.SetPopup) == "function"
end

local function GetButtonIcon(button)
    if not button then return nil end
    if button.icon then return button.icon end
    if button.Icon then return button.Icon end
    local name = button.GetName and button:GetName()
    return name and _G[name .. "Icon"] or nil
end

local function GetControllerDirection(controller)
    if not controller then return "UP" end
    if controller.flyoutDirection then return controller.flyoutDirection end
    if controller.UpdateSpellFlyoutDirection then
        controller:UpdateSpellFlyoutDirection()
    end
    return controller.flyoutDirection or "UP"
end

local function Controller_UpdateSpellFlyoutDirection(self)
    local direction = self.isHorizontal ~= false and "UP" or "LEFT"
    local centerX, centerY = self:GetCenter()
    if not centerX and self.yabMover and self.yabMover.GetCenter then
        centerX, centerY = self.yabMover:GetCenter()
    end
    if centerX and centerY then
        if self.isHorizontal ~= false then
            local halfScreen = (GetScreenHeight and GetScreenHeight() or 768) / 2
            direction = centerY < halfScreen and "UP" or "DOWN"
        else
            local halfScreen = (GetScreenWidth and GetScreenWidth() or 1024) / 2
            direction = centerX > halfScreen and "LEFT" or "RIGHT"
        end
    end
    self.flyoutDirection = direction
    for _, button in ipairs(self.actionButtons or {}) do
        if not Factory:InCombat() and button.SetAttribute and YAB.SecureFactory then
            YAB.SecureFactory:SetSecureAttribute(button, "flyoutDirection", direction)
        end
    end
    return direction
end

local function Controller_GetSpellFlyoutDirection(self)
    return GetControllerDirection(self)
end

local function Controller_UpdateShownButtons(self)
    return true
end

function Factory:CreateBarController(id, holder, mover)
    if self:InCombat() then return nil, "combat" end
    local root = self:CreateRoot()
    if not root then return nil, "no root" end
    local name = self:FrameName("Controller", id)
    local controller = _G[name] or self.pools.controllers[id]
    if not controller then
        controller = CreateFrame("Frame", name, root)
        controller.actionButtons = {}
        controller.GetSpellFlyoutDirection = Controller_GetSpellFlyoutDirection
        controller.UpdateSpellFlyoutDirection = Controller_UpdateSpellFlyoutDirection
        controller.UpdateShownButtons = Controller_UpdateShownButtons
        self.pools.controllers[id] = controller
    end
    controller:SetParent(root)
    controller:ClearAllPoints()
    if holder then controller:SetPoint("CENTER", holder, "CENTER", 0, 0) end
    local width, height = 1, 1
    if holder and holder.GetSize then
        width, height = holder:GetSize()
    end
    controller:SetSize(width or 1, height or 1)
    controller.yabHolder = holder
    controller.yabMover = mover
    controller.yabId = id
    controller:Show()
    return controller
end

function Factory:CreateMover(id)
    if self:InCombat() then return nil, "combat" end
    local name = self:FrameName("Mover", id)
    local mover = _G[name] or self.pools.movers[id]
    if not mover then
        mover = CreateFrame("Frame", name, UIParent)
        self.pools.movers[id] = mover
    end
    mover:SetParent(UIParent)
    mover:EnableMouse(false)
    mover:Show()
    return mover
end

function Factory:CreateHolder(id, config, secure)
    if self:InCombat() then return nil, "combat" end
    local root = self:CreateRoot()
    if not root then return nil, "no root" end
    local name = self:FrameName("Holder", id)
    local holder = _G[name] or self.pools.holders[id]
    if not holder then
        holder = CreateFrame("Frame", name, root, "SecureHandlerStateTemplate")
        self.pools.holders[id] = holder
    end
    holder.yabSecureHolder = true
    holder:SetParent(root)
    holder:SetSize(1, 1)
    if holder.SetFrameStrata then holder:SetFrameStrata("HIGH") end
    if root.GetFrameLevel and holder.SetFrameLevel then
        holder:SetFrameLevel((root:GetFrameLevel() or 1) + 2)
    end
    holder:EnableMouse(false)
    holder:Show()
    return holder
end

local function CreateWithTemplates(name, parent, templates)
    for _, template in ipairs(templates) do
        local ok, frame = pcall(CreateFrame, "CheckButton", name, parent, template)
        if ok and frame then
            frame.yabTemplate = template
            return frame
        end
    end
    return nil
end

local function ClearArrayValueInPlace(list, value)
    if type(list) ~= "table" then return false end
    local cleared = false
    for key, item in pairs(list) do
        if item == value then
            list[key] = nil
            cleared = true
        end
    end
    return cleared
end

local function ClearDirectMappedValue(map, value)
    if type(map) ~= "table" or map[value] == nil then return false end
    map[value] = nil
    return true
end

local function ClearActionMappedValue(actions, action, value)
    if type(actions) ~= "table" or action == nil then return false end
    local frames = actions[action]
    if type(frames) ~= "table" or frames[value] == nil then return false end
    frames[value] = nil
    return true
end

function Factory:DetachActionButtonDispatchers(button)
    if not button then return false end
    local meta = self:GetButtonMeta(button)
    local action = meta and meta.slot or button.yabSlot or button.action

    local eventFrame = _G.ActionBarButtonEventsFrame
    if eventFrame and type(eventFrame.frames) == "table" then
        ClearArrayValueInPlace(eventFrame.frames, button)
    end

    local actionEvents = _G.ActionBarActionEventsFrame
    if actionEvents then
        local registered = type(actionEvents.frames) == "table" and actionEvents.frames[button] ~= nil
        if registered and actionEvents.UnregisterFrame then
            pcall(actionEvents.UnregisterFrame, actionEvents, button)
        end
        ClearDirectMappedValue(actionEvents.frames, button)
        if actionEvents.tooltipOwner == button then
            actionEvents.tooltipOwner = nil
        end
    end

    local updateFrame = _G.ActionBarButtonUpdateFrame
    if updateFrame then
        local registered = type(updateFrame.frames) == "table" and updateFrame.frames[button] ~= nil
        if registered and updateFrame.UnregisterFrame then
            pcall(updateFrame.UnregisterFrame, updateFrame, button)
        end
        ClearDirectMappedValue(updateFrame.frames, button)
    end

    local rangeFrame = _G.ActionBarButtonRangeCheckFrame
    if rangeFrame then
        local frames = type(rangeFrame.actions) == "table" and action ~= nil and rangeFrame.actions[action] or nil
        local registered = type(frames) == "table" and frames[button] ~= nil
        if registered and rangeFrame.UnregisterFrame then
            pcall(rangeFrame.UnregisterFrame, rangeFrame, action, button)
        end
        ClearActionMappedValue(rangeFrame.actions, action, button)
    end

    local usableFrame = _G.ActionBarButtonUsableWatcherFrame
    if usableFrame then
        local frames = type(usableFrame.actions) == "table" and action ~= nil and usableFrame.actions[action] or nil
        local registered = type(frames) == "table" and frames[button] ~= nil
        if registered and usableFrame.UnregisterFrame then
            pcall(usableFrame.UnregisterFrame, usableFrame, action, button)
        end
        ClearActionMappedValue(usableFrame.actions, action, button)
    end

    button.eventsRegistered = false
    button.actionEventsRegistered = false
    button.rangeTimer = nil
    return true
end

local function BuildActionTemplates(definition)
    local templates = {}
    local primary = definition and definition.buttonTemplate
    if primary and primary ~= "" then
        if primary == "ActionBarButtonTemplate" then
            templates[#templates + 1] = primary .. ",SecureActionButtonTemplate"
        end
        templates[#templates + 1] = primary .. ",SecureHandlerStateTemplate"
        templates[#templates + 1] = primary
    end
    if primary ~= "SecureActionButtonTemplate" then
        templates[#templates + 1] = "SecureActionButtonTemplate,SecureHandlerStateTemplate"
        templates[#templates + 1] = "SecureActionButtonTemplate"
    end
    return templates
end

local function MarkStripped(factory, button)
    if not factory.strippedButtons[button] then
        factory.strippedButtons[button] = true
        factory.stripCount = (factory.stripCount or 0) + 1
    end
end

local function CountMapKeys(map)
    local count = 0
    if type(map) ~= "table" then return 0 end
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

local function CapturePoints(frame)
    local points = {}
    if not (frame and frame.GetNumPoints and frame.GetPoint) then return points end
    for index = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

local function CaptureFrameState(frame)
    local scripts = nil
    if frame.GetScript then
        scripts = {
            OnDragStart = frame:GetScript("OnDragStart"),
            OnReceiveDrag = frame:GetScript("OnReceiveDrag"),
        }
    end
    return {
        parent = frame.GetParent and frame:GetParent() or nil,
        points = CapturePoints(frame),
        alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        shown = frame.IsShown and frame:IsShown() or false,
        mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false,
        frameLevel = frame.GetFrameLevel and frame:GetFrameLevel() or nil,
        frameStrata = frame.GetFrameStrata and frame:GetFrameStrata() or nil,
        scripts = scripts,
    }
end

local function RestoreFrameState(frame, state)
    if not frame or not state then return true end
    local ok = true
    if frame.SetParent and state.parent then
        ok = pcall(frame.SetParent, frame, state.parent) and ok
    end
    if frame.SetFrameStrata and state.frameStrata then
        ok = pcall(frame.SetFrameStrata, frame, state.frameStrata) and ok
    end
    if frame.SetFrameLevel and state.frameLevel then
        ok = pcall(frame.SetFrameLevel, frame, state.frameLevel) and ok
    end
    if frame.ClearAllPoints then
        ok = pcall(frame.ClearAllPoints, frame) and ok
    end
    if frame.SetPoint and type(state.points) == "table" then
        for _, point in ipairs(state.points) do
            ok = pcall(frame.SetPoint, frame, point[1], point[2], point[3], point[4], point[5]) and ok
        end
    end
    if frame.SetAlpha then ok = pcall(frame.SetAlpha, frame, state.alpha or 1) and ok end
    if frame.EnableMouse then ok = pcall(frame.EnableMouse, frame, state.mouse == true) and ok end
    if frame.SetScript and state.scripts then
        ok = pcall(frame.SetScript, frame, "OnDragStart", state.scripts.OnDragStart) and ok
        ok = pcall(frame.SetScript, frame, "OnReceiveDrag", state.scripts.OnReceiveDrag) and ok
    end
    if state.shown == true then
        if frame.Show then ok = pcall(frame.Show, frame) and ok end
    elseif frame.Hide then
        ok = pcall(frame.Hide, frame) and ok
    end
    return ok
end

function Factory:CaptureNativeSpecialState(button)
    if not button or self.nativeSpecialState[button] then return true end
    self.nativeSpecialState[button] = CaptureFrameState(button)
    return true
end

function Factory:RestoreNativeSpecialButton(button)
    if not button then return true end
    if self:InCombat() then return false, "combat lockdown" end
    local state = self.nativeSpecialState and self.nativeSpecialState[button]
    local ok = true
    if state then
        ok = RestoreFrameState(button, state)
    end
    if not ok then
        return false, "native special button restore failed"
    end
    if state then
        self.nativeSpecialState[button] = nil
    end
    if self.nativeSpecialButtons then
        self.nativeSpecialButtons[button] = nil
    end
    if self.buttonMeta then
        self.buttonMeta[button] = nil
    end
    if self.nativePetDragGuardInstalled then
        self.nativePetDragGuardInstalled[button] = nil
    end
    if self.nativePetClickRefreshInstalled then
        self.nativePetClickRefreshInstalled[button] = nil
    end
    if self.fallbackPetClickInstalled then
        self.fallbackPetClickInstalled[button] = nil
    end
    return ok
end

function Factory:RestoreNativeSpecialButtons()
    if self:InCombat() then return false, "combat lockdown" end
    local failures = 0
    for button in pairs(self.nativeSpecialButtons or {}) do
        local ok = self:RestoreNativeSpecialButton(button)
        if not ok then failures = failures + 1 end
    end
    return failures == 0, failures > 0 and "native special button restore failed" or nil
end

function Factory:SetButtonMeta(button, meta)
    if not button then return nil end
    self.buttonMeta[button] = meta
    return meta
end

function Factory:GetButtonMeta(button)
    return button and self.buttonMeta and self.buttonMeta[button] or nil
end

function Factory:GetButtonCommand(button)
    local meta = self:GetButtonMeta(button)
    return meta and meta.commandName or button and button.commandName or nil
end

function Factory:GetButtonKey(button)
    local meta = self:GetButtonMeta(button)
    if meta and meta.buttonKey then return meta.buttonKey end
    if meta and meta.barId and meta.index and YAB.Keybinds and YAB.Keybinds.GetButtonKey then
        return YAB.Keybinds:GetButtonKey(meta.barId, meta.index)
    end
    return nil
end

local function GetButtonCooldown(button)
    return button and (button.cooldown or button.Cooldown) or nil
end

local function ProductInCombat()
    return YAB.Adapter and YAB.Adapter.InCombat and YAB.Adapter:InCombat() or false
end

function Factory:GetTooltipMode()
    local db = YAB.GetDB and YAB:GetDB() or nil
    local mode = db and db.interaction and db.interaction.tooltipMode
    return mode == "outOfCombat" and "outOfCombat" or "always"
end

local function SetScriptSafe(frame, scriptName, handler)
    if not (frame and scriptName and type(frame.SetScript) == "function") then return false end
    local ok = pcall(frame.SetScript, frame, scriptName, handler)
    return ok == true
end

local function GetDetachedActionSlot(button)
    if not button then return nil end
    local meta = Factory:GetButtonMeta(button)
    local slot = meta and meta.slot or button.yabSlot or button.action
    if slot == nil and button.GetAttribute then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok then slot = value end
    end
    if type(slot) == "number" then return slot end
    return tonumber(slot)
end

local function GetActionSpellID(slot)
    if not (slot and _G.GetActionInfo) then return nil end
    local actionType, id, subType = _G.GetActionInfo(slot)
    if actionType == "spell" then
        return id
    elseif actionType == "macro" and subType == "spell" then
        return id
    end
    return nil
end

local function IsPressHoldSpell(spellID)
    if not spellID then return false end
    local spell = _G.C_Spell
    if spell and type(spell.IsPressHoldReleaseSpell) == "function" then
        local ok, result = pcall(spell.IsPressHoldReleaseSpell, spellID)
        if ok then return result == true end
    end
    if type(_G.IsPressHoldReleaseSpell) == "function" then
        local ok, result = pcall(_G.IsPressHoldReleaseSpell, spellID)
        if ok then return result == true end
    end
    return false
end

local function ApplyPressAndHoldAttributes(button, slot)
    if not (button and button.SetAttribute) or ProductInCombat() then return false end
    local pressAndHold = IsPressHoldSpell(GetActionSpellID(slot))
    pcall(button.SetAttribute, button, "pressAndHoldAction", pressAndHold)
    pcall(button.SetAttribute, button, "typerelease", "actionrelease")
    return true
end

local function NormalizeBoolean(value)
    if value == nil then return nil end
    if value == true or value == 1 or value == "1" then return true end
    if value == false or value == 0 or value == "0" then return false end
    return false
end

local function ReadCVarBool(name)
    if type(_G.GetCVarBool) == "function" then
        local ok, value = pcall(_G.GetCVarBool, name)
        if ok then return NormalizeBoolean(value) end
    end
    if type(_G.GetCVar) == "function" then
        local ok, value = pcall(_G.GetCVar, name)
        if ok then return NormalizeBoolean(value) end
    end
    return nil
end

local function IsActionBarsLocked()
    local settings = _G.Settings
    if settings and type(settings.GetValue) == "function" then
        local ok, value = pcall(settings.GetValue, "lockActionBars")
        if ok then
            local normalized = NormalizeBoolean(value)
            if normalized ~= nil then return normalized end
        end
    end
    return ReadCVarBool("lockActionBars") == true
end

local function ApplyActionButtonClickAttributes(button)
    if not (button and button.SetAttribute) or ProductInCombat() then return false end
    local keyDown = ReadCVarBool("ActionButtonUseKeyDown")
    local locked = IsActionBarsLocked()
    local ok = true
    ok = pcall(button.SetAttribute, button, "useOnKeyDown", keyDown) and ok
    ok = pcall(button.SetAttribute, button, "buttonlock", locked or nil) and ok
    ok = pcall(button.SetAttribute, button, "unlockedpreventdrag", true) and ok
    return ok == true
end

local ACTION_PICKUP_CLICK_GUARD_PRE = [[
    if down and button ~= "Keybind" and ((self:GetAttribute("unlockedpreventdrag") and not self:GetAttribute("buttonlock")) or IsModifiedClick("PICKUPACTION")) then
        local useOnKeyDown = self:GetAttribute("useOnKeyDown")
        if useOnKeyDown ~= false then
            self:SetAttribute("yabPickupToggledOnDown", true)
            self:SetAttribute("yabPickupUseOnKeyDownBackup", useOnKeyDown)
            self:SetAttribute("useOnKeyDown", false)
        end
    end
]]

local ACTION_PICKUP_CLICK_GUARD_RESTORE = [[
    if self:GetAttribute("yabPickupToggledOnDown") then
        self:SetAttribute("useOnKeyDown", self:GetAttribute("yabPickupUseOnKeyDownBackup"))
        self:SetAttribute("yabPickupToggledOnDown", nil)
        self:SetAttribute("yabPickupUseOnKeyDownBackup", nil)
    end
]]

-- Keep keyboard input distinct through PreClick, then use the native left
-- action for both press and release. Mouse pickup guards must not delay keys.
local ACTION_KEYBIND_CLICK = [[
    if button == "Keybind" then return "LeftButton" end
]]

local function InstallActionPickupClickGuard(button, holder)
    if not (button and holder and type(holder.WrapScript) == "function") or ProductInCombat() then return false end
    local installed = Factory.actionPickupClickGuardInstalled
    if installed and installed[button] == holder then return true end
    SetScriptSafe(button, "PreClick", NOOP)
    SetScriptSafe(button, "PostClick", NOOP)
    local okClick = pcall(function()
        holder:WrapScript(button, "OnClick", ACTION_KEYBIND_CLICK)
    end)
    local okPost = pcall(function()
        holder:WrapScript(button, "PostClick", "if not down then return nil, true end", ACTION_PICKUP_CLICK_GUARD_RESTORE)
    end)
    local okDrag = pcall(function()
        holder:WrapScript(button, "OnDragStart", "return 'message', true", ACTION_PICKUP_CLICK_GUARD_RESTORE)
    end)
    local okPre = okClick and okPost and okDrag and pcall(function()
        holder:WrapScript(button, "PreClick", ACTION_PICKUP_CLICK_GUARD_PRE)
    end)
    if okPre and okPost and okDrag then
        installed[button] = holder
        return true
    end
    return false
end

local function ClearDetachedTooltipOwner(button)
    if not button then return end
    local tooltip = _G.GameTooltip
    if tooltip and tooltip.GetOwner and tooltip.Hide then
        local ok, owner = pcall(tooltip.GetOwner, tooltip)
        if ok and owner == button then
            pcall(tooltip.Hide, tooltip)
        end
    end
    local eventFrame = _G.ActionBarButtonEventsFrame
    if eventFrame and eventFrame.tooltipOwner == button then
        eventFrame.tooltipOwner = nil
    end
    local actionEvents = _G.ActionBarActionEventsFrame
    if actionEvents and actionEvents.tooltipOwner == button then
        actionEvents.tooltipOwner = nil
    end
end

local function IsTooltipScopedButton(button)
    if not button then return false end
    if Factory.detachedButtons and Factory.detachedButtons[button] then return true end
    local meta = Factory:GetButtonMeta(button)
    return meta and (meta.barId == "pet" or meta.barId == "stance") or false
end

function Factory:ShouldShowTooltip(button)
    if not ProductInCombat() or self:GetTooltipMode() ~= "outOfCombat" then return true end
    return not IsTooltipScopedButton(button)
end

function Factory:HideRestrictedCombatTooltip()
    if not ProductInCombat() or self:GetTooltipMode() ~= "outOfCombat" then return false end
    local tooltip = _G.GameTooltip
    if not (tooltip and tooltip.GetOwner and tooltip.Hide) then return false end
    local ok, owner = pcall(tooltip.GetOwner, tooltip)
    if not (ok and IsTooltipScopedButton(owner)) then return false end
    pcall(tooltip.Hide, tooltip)
    return true
end

local function GuardNativeSpecialTooltip(button)
    if Factory:ShouldShowTooltip(button) then return end
    ClearDetachedTooltipOwner(button)
end

function Factory:InstallNativeSpecialTooltipGuard(button, kind)
    if not button or (kind ~= "pet" and kind ~= "stance") then return true end
    if self.nativeSpecialTooltipGuardInstalled[button] then return true end
    if type(button.HookScript) ~= "function" then return false end
    local ok = pcall(button.HookScript, button, "OnEnter", GuardNativeSpecialTooltip)
    if ok then self.nativeSpecialTooltipGuardInstalled[button] = true end
    return ok == true
end

local function DetachedActionButtonSetTooltip(button)
    if not button then return end
    if not Factory:ShouldShowTooltip(button) then
        ClearDetachedTooltipOwner(button)
        return
    end
    local tooltip = _G.GameTooltip
    local slot = GetDetachedActionSlot(button)
    if not (tooltip and slot and tooltip.SetAction) then return end
    if _G.GameTooltip_SetDefaultAnchor then
        pcall(_G.GameTooltip_SetDefaultAnchor, tooltip, button)
    elseif tooltip.SetOwner then
        pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_RIGHT")
    end
    pcall(tooltip.SetAction, tooltip, slot)
end

local function DetachedActionButtonOnEnter(button)
    DetachedActionButtonSetTooltip(button)
    local keybindMode = YAB.KeybindMode
    if keybindMode and keybindMode.HandleButtonEnter then
        keybindMode:HandleButtonEnter(button, Factory:GetButtonKey(button))
    end
end

local function DetachedActionButtonOnLeave(button)
    ClearDetachedTooltipOwner(button)
    if button then
        button.UpdateTooltip = nil
    end
end

local function MarkDetached(factory, button)
    if not factory.detachedButtons[button] then
        factory.detachedButtons[button] = true
        factory.detachedScriptCount = (factory.detachedScriptCount or 0) + 1
    end
end

function Factory:RegisterNativeActionCooldown(button, action)
    if not button or self:InCombat() then return false end
    local meta = self:GetButtonMeta(button)
    action = tonumber(action or (meta and meta.slot) or (button.GetAttribute and button:GetAttribute("action")) or button.yabSlot or button.action)
    if not action then return false end

    local cooldown = GetButtonCooldown(button)
    if not cooldown then return false end

    local registered = self.nativeCooldownRegistered
    if type(registered) ~= "table" then
        registered = setmetatable({}, { __mode = "k" })
        self.nativeCooldownRegistered = registered
    end
    if registered[button] == action then
        return true
    end

    local actionBar = _G.C_ActionBar
    if registered[button] ~= nil and actionBar and type(actionBar.UnregisterActionUIButton) == "function" then
        local unregistered = pcall(actionBar.UnregisterActionUIButton, button)
        if not unregistered then
            self.nativeCooldownRegisterFails = (self.nativeCooldownRegisterFails or 0) + 1
        end
        registered[button] = nil
    end

    if actionBar and type(actionBar.RegisterActionUIButton) == "function" then
        self.nativeCooldownRegisterAttempts = (self.nativeCooldownRegisterAttempts or 0) + 1
        self.nativeCooldownRegisterAPI = "C_ActionBar.RegisterActionUIButton"
        local ok = pcall(actionBar.RegisterActionUIButton, button, action, cooldown)
        if ok then
            registered[button] = action
            return true
        end
        self.nativeCooldownRegisterFails = (self.nativeCooldownRegisterFails or 0) + 1
        return false
    end

    if type(_G.SetActionUIButton) == "function" then
        self.nativeCooldownRegisterAttempts = (self.nativeCooldownRegisterAttempts or 0) + 1
        self.nativeCooldownRegisterAPI = "SetActionUIButton"
        local ok = pcall(_G.SetActionUIButton, button, action, cooldown)
        if ok then
            registered[button] = action
            return true
        end
        self.nativeCooldownRegisterFails = (self.nativeCooldownRegisterFails or 0) + 1
        return false
    end

    self.nativeCooldownRegisterAPI = "none"
    return false
end

function Factory:UnregisterNativeActionCooldown(button)
    if not button or self:InCombat() then return false end
    local registered = self.nativeCooldownRegistered
    if type(registered) == "table" then
        registered[button] = nil
    end
    local actionBar = _G.C_ActionBar
    if actionBar and type(actionBar.UnregisterActionUIButton) == "function" then
        local ok = pcall(actionBar.UnregisterActionUIButton, button)
        if not ok then
            self.nativeCooldownRegisterFails = (self.nativeCooldownRegisterFails or 0) + 1
        end
        return ok == true
    end
    return false
end

function Factory:GetNativeCooldownRegistrationStats()
    return {
        nativeRegistered = CountMapKeys(self.nativeCooldownRegistered),
        nativeRegisterAttempts = self.nativeCooldownRegisterAttempts or 0,
        nativeRegisterFails = self.nativeCooldownRegisterFails or 0,
        nativeRegisterAPI = self.nativeCooldownRegisterAPI or "none",
    }
end

function Factory:DisableAssistedCombatRotation(button)
    if not button then return false end
    button.UpdateAssistedCombatRotationFrame = NOOP

    local frame = button.AssistedCombatRotationFrame
    if not frame or self.retiredAssistedCombatFrames[frame] then return true end
    if frame.SetScript then
        pcall(frame.SetScript, frame, "OnUpdate", nil)
    end
    if frame.UnregisterAllEvents then
        pcall(frame.UnregisterAllEvents, frame)
    end
    if frame.Hide then
        pcall(frame.Hide, frame)
    end
    self.retiredAssistedCombatFrames[frame] = true
    return true
end

function Factory:NeutralizeButtonArt(button, mode)
    if not button then return false end
    local icon = GetButtonIcon(button)
    local visual = YAB.Visuals and YAB.Visuals.buttons[button]
    local checkedTexture = visual and visual.nativeChecked and visual.checkedRing or nil

    if icon and button.IconMask and icon.RemoveMaskTexture then
        pcall(icon.RemoveMaskTexture, icon, button.IconMask)
    end
    HideRegion(button.IconMask)

    if mode == "special" then
        for _, field in ipairs(SPECIAL_SKIN_HIDDEN_FIELDS) do
            if button[field] ~= checkedTexture then HideRegion(button[field]) end
        end
        HideButtonStateTextures(button, checkedTexture)
        MarkStripped(self, button)
        return true
    end

    local fields = mode == "action" and ACTION_SKIN_HIDDEN_FIELDS or FULL_HIDDEN_ART_FIELDS
    for _, field in ipairs(fields) do
        if button[field] ~= checkedTexture then HideRegion(button[field]) end
    end
    HideButtonStateTextures(button, checkedTexture)
    local professionQualityOverlay = button.ProfessionQualityOverlayFrame
    if professionQualityOverlay and professionQualityOverlay.Hide then
        pcall(professionQualityOverlay.Hide, professionQualityOverlay)
    end

    button.UpdateButtonArt = NOOP
    self:DisableAssistedCombatRotation(button)
    button.UpdateProfessionQuality = NOOP
    button.ClearProfessionQuality = NOOP
    button.UpdateTypeOverlay = NOOP
    button.ClearTypeOverlay = NOOP
    button.UpdateSpellHighlightMark = NOOP
    button.UpdateHighlightMark = NOOP
    button.UpdateSpellAlert = NOOP
    button.UpdateFlash = NOOP
    if mode == "action" then
        EnsureActionFlyoutBridge(button)
    else
        button.GetPopupDirection = GetYUIFlyoutDirection
    end
    MarkStripped(self, button)
    return true
end

function Factory:SyncActionFlyoutIdentity(button, hasFlyout)
    if not button or self:InCombat() then return false end
    if not EnsureActionFlyoutBridge(button) then return false end
    local desired = hasFlyout == true
    if button.GetAttribute then
        local ok, current = pcall(button.GetAttribute, button, ACTION_FLYOUT_IDENTITY_ATTRIBUTE)
        if ok and current == desired then return true end
    end
    return self:SetSecureAttribute(button, ACTION_FLYOUT_IDENTITY_ATTRIBUTE, desired)
end

function Factory:InitializeNativeActionButton(button)
    if not button or self:InCombat() then return false end
    self:DetachActionButtonDispatchers(button)
    button.OnEvent = NOOP
    button.OnUpdate = NOOP
    button.Update = NOOP
    button.UpdateAction = NOOP
    button.UpdatePressAndHoldAction = NOOP
    button.UpdateCooldown = NOOP
    button.UpdateTooltip = nil
    button.SetTooltip = DetachedActionButtonSetTooltip
    button.ActionBarActionButtonDerivedMixin_OnEvent = NOOP
    button.ActionBarActionButtonDerivedMixin_OnPostClick = NOOP
    button.ActionBarActionButtonDerivedMixin_OnEnter = DetachedActionButtonOnEnter
    button.ActionBarActionButtonDerivedMixin_OnLeave = DetachedActionButtonOnLeave
    button.ActionBarActionButtonDerivedMixin_OnShow = NOOP
    button.ActionBarActionButtonDerivedMixin_OnHide = NOOP
    button.ActionBarButtonMixin_OnEnter = DetachedActionButtonOnEnter
    button.ActionBarButtonMixin_OnLeave = DetachedActionButtonOnLeave
    if button.UnregisterAllEvents then
        button:UnregisterAllEvents()
    end
    SetScriptSafe(button, "OnEvent", NOOP)
    SetScriptSafe(button, "OnUpdate", nil)
    -- Detach native interaction scripts once. Replacing them during page sync
    -- would discard the visual hooks and secure click wrappers installed later.
    if not self.detachedButtons[button] then
        SetScriptSafe(button, "OnShow", NOOP)
        SetScriptSafe(button, "OnHide", NOOP)
        SetScriptSafe(button, "OnEnter", DetachedActionButtonOnEnter)
        SetScriptSafe(button, "OnLeave", DetachedActionButtonOnLeave)
        SetScriptSafe(button, "PostClick", nil)
    end
    EnsureActionFlyoutBridge(button)
    self:DetachActionButtonDispatchers(button)
    MarkDetached(self, button)
    return true
end

local ACTION_DRAG_START_SECURE = [[
    if self:GetAttribute("yab-action-active") ~= true then return false end
    if self:GetAttribute("buttonlock") and not IsModifiedClick("PICKUPACTION") then return false end
    local slot = self:GetAttribute("action")
    if not slot or not HasAction(slot) then return false end
    if self:GetAttribute("yabPickupToggledOnDown") then
        self:SetAttribute("useOnKeyDown", self:GetAttribute("yabPickupUseOnKeyDownBackup"))
        self:SetAttribute("yabPickupToggledOnDown", nil)
        self:SetAttribute("yabPickupUseOnKeyDownBackup", nil)
    end
    control:RunAttribute("SetActionGridReason", true, 2)
    return "action", slot
]]

local ACTION_RECEIVE_DRAG_SECURE = [[
    if self:GetAttribute("yab-action-active") ~= true or not kind then return false end
    local slot = self:GetAttribute("action")
    if not slot then return false end
    return "action", slot
]]

local ACTION_GRID_REASON_SECURE = [[
    local show, reason = ...
    local current = yabActionGridMask or 0
    local previous = current
    if show then
        if current % (reason * 2) < reason then current = current + reason end
    elseif current % (reason * 2) >= reason then
        current = current - reason
    end
    if current == previous then return end
    yabActionGridMask = current
    local wasActive = previous > 0
    local active = current > 0
    if active == wasActive then return end
    self:SetAttribute("yab-action-grid-active", active or nil)
    for button in pairs(yabActionButtons) do
        if button:GetAttribute("yab-action-active") == true
            and button:GetAttribute("yab-hide-empty") == true
            and not HasAction(button:GetAttribute("action") or 0) then
            if active then button:Show(true) else button:Hide(true) end
        end
    end
]]

local ACTION_GRID_RESET_SECURE = [[
    if (yabActionGridMask or 0) == 0 then return end
    yabActionGridMask = 0
    self:SetAttribute("yab-action-grid-active", nil)
    for button in pairs(yabActionButtons) do
        if button:GetAttribute("yab-action-active") == true
            and button:GetAttribute("yab-hide-empty") == true
            and not HasAction(button:GetAttribute("action") or 0) then
            button:Hide(true)
        end
    end
]]

local ACTION_GRID_MONITOR_SECURE = [[
    if name ~= "showgrid" then return end
    value = value or 0
    for reason = 2, 4, 2 do
        control:RunAttribute("SetActionGridReason", value % (reason * 2) >= reason, reason)
    end
]]

InitializeActionDragRoot = function(root)
    if not root or root:GetAttribute("yab-action-drag-ready") == true or ProductInCombat() then
        return root and root:GetAttribute("yab-action-drag-ready") == true
    end
    root:SetAttribute("SetActionGridReason", ACTION_GRID_REASON_SECURE)
    root:SetAttribute("ResetActionGrid", ACTION_GRID_RESET_SECURE)
    root:Execute([[
        yabActionButtons = table.new()
        yabActionGridMask = 0
    ]])
    local monitor = _G.ActionButton1
    if not monitor then return false end
    local ok = pcall(function()
        root:WrapScript(monitor, "OnAttributeChanged", ACTION_GRID_MONITOR_SECURE)
    end)
    if not ok then return false end
    root:SetAttribute("yab-action-drag-ready", true)
    return true
end

function Factory:InstallActionDragGuard(button)
    if not button or self:InCombat() or not self.detachedButtons[button] then return false end
    local root = self:CreateRoot()
    if not root or not InitializeActionDragRoot(root) then return false end
    if self.actionDragInstalled[button] ~= root then
        local dragOk = pcall(function()
            root:WrapScript(button, "OnDragStart", ACTION_DRAG_START_SECURE)
        end)
        local receiveOk = dragOk and pcall(function()
            root:WrapScript(button, "OnReceiveDrag", ACTION_RECEIVE_DRAG_SECURE)
        end)
        if not receiveOk then return false end
        self.actionDragInstalled[button] = root
    end
    if self.actionDragRegistered[button] ~= root then
        root:SetFrameRef("yabActionButton", button)
        root:Execute([[
            local button = self:GetFrameRef("yabActionButton")
            yabActionButtons[button] = true
        ]])
        self.actionDragRegistered[button] = root
    end
    button:SetAttribute("yab-action-active", true)
    return true
end

function Factory:UpdateActionDragButton(button, active, hideEmpty)
    if not button or self:InCombat() or not self.detachedButtons[button] then return false end
    if active == true then
        if not self:InstallActionDragGuard(button) then return false end
        hideEmpty = hideEmpty == true
        if self.actionDragHideEmpty[button] ~= hideEmpty then
            button:SetAttribute("yab-hide-empty", hideEmpty or nil)
            self.actionDragHideEmpty[button] = hideEmpty
        end
        return true
    end
    local root = self.actionDragRegistered[button]
    button:SetAttribute("yab-action-active", nil)
    button:SetAttribute("yab-hide-empty", nil)
    self.actionDragHideEmpty[button] = nil
    if root then
        root:SetFrameRef("yabActionButton", button)
        root:Execute([[
            local button = self:GetFrameRef("yabActionButton")
            yabActionButtons[button] = nil
        ]])
        self.actionDragRegistered[button] = nil
    end
    return true
end

function Factory:ResetActionDragGrid()
    if self:InCombat() then return false end
    local root = self.root
    if not (root and root:GetAttribute("yab-action-drag-ready") == true) then return true end
    local ok = pcall(root.Execute, root, [[ self:RunAttribute("ResetActionGrid") ]])
    return ok == true
end

function Factory:RefreshActionButtonClickAttributes(reason)
    if self:InCombat() then
        if YAB.Drivers and YAB.Drivers.Queue then
            local factory = self
            return YAB.Drivers:Queue(reason or "action-click-attributes", function()
                factory:RefreshActionButtonClickAttributes(reason)
            end)
        end
        return false
    end
    local ok = true
    for button in pairs(self.detachedButtons or {}) do
        local meta = self:GetButtonMeta(button)
        if meta and meta.slot and meta.barId then
            ok = ApplyActionButtonClickAttributes(button) ~= false and ok
        end
    end
    self.actionClickAttributeRefreshReason = reason
    return ok
end

function Factory:SetSecureAttribute(button, attr, value)
    if not button or not attr or not button.SetAttribute or self:InCombat() then return false end
    local ok = pcall(button.SetAttribute, button, attr, value)
    return ok == true
end

function Factory:SetSpellAction(button, spellID)
    if not button or self:InCombat() then return false end
    self:SetSecureAttribute(button, "type", "spell")
    self:SetSecureAttribute(button, "type1", "spell")
    self:SetSecureAttribute(button, "spell", spellID)
    self:SetSecureAttribute(button, "spell1", spellID)
    return true
end

function Factory:ConfigureBarController(controller, record, config, width, height)
    if not controller then return end
    controller.actionButtons = record and record.buttons or controller.actionButtons or {}
    controller.numRows = tonumber(config and config.rows) or 1
    controller.isHorizontal = (tonumber(width) or 1) >= (tonumber(height) or 1)
    controller.yabMover = record and record.mover or controller.yabMover
    controller.yabHolder = record and record.holder or controller.yabHolder
    if width and height then controller:SetSize(width, height) end
    controller:UpdateSpellFlyoutDirection()
end

function Factory:SyncActionButtonState(button, holder, controller, barId, index, page)
    if not button or self:InCombat() then return false end
    self:DisableAssistedCombatRotation(button)
    local definition = YAB.Adapter and YAB.Adapter:GetActionBarDefinition(barId) or nil
    if barId ~= "main" and YAB.Adapter then
        page = YAB.Adapter:GetActionBarPageForBar(barId, page)
    end
    page = tonumber(page) or 1
    index = tonumber(index) or 1
    local slot = YAB.Adapter and YAB.Adapter:GetActionSlot(page, index) or (((page - 1) * 12) + index)
    local commandPrefix = definition and definition.commandNamePrefix or "ACTIONBUTTON"
    local commandName = commandPrefix .. tostring(index)

    if holder then
        button:SetParent(holder)
        if holder.GetFrameLevel and button.SetFrameLevel then
            button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
        end
    end
    button:SetID(index)
    button:RegisterForClicks("AnyDown", "AnyUp")
    self:InitializeNativeActionButton(button)
    button:SetAttribute("type", "action")
    button:SetAttribute("type1", "action")
    button:SetAttribute("typerelease", "actionrelease")
    button:SetAttribute("useparent-actionpage", false)
    button:SetAttribute("useparent-unit", false)
    button:SetAttribute("useparent*", false)
    button:SetAttribute("action", slot)
    button:SetAttribute("action1", slot)
    button:SetAttribute("action2", slot)
    button:SetAttribute("actionpage", page)
    button:SetAttribute("flyoutDirection", GetControllerDirection(controller))
    button.action = slot
    button.buttonType = definition and definition.buttonType or "ACTIONBUTTON"
    button.commandName = commandName
    button.bindingAction = commandName
    local buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey and YAB.Keybinds:GetButtonKey(barId, index) or nil
    self:NeutralizeButtonArt(button, "action")
    self:SetButtonMeta(button, {
        barId = barId,
        index = index,
        page = page,
        slot = slot,
        commandName = commandName,
        buttonKey = buttonKey,
        controller = controller,
        holder = holder,
    })
    button.commandName = commandName
    button.bindingAction = commandName
    ApplyPressAndHoldAttributes(button, slot)
    ApplyActionButtonClickAttributes(button)
    self:InstallActionDragGuard(button)
    InstallActionPickupClickGuard(button, holder)
    self:RegisterNativeActionCooldown(button, slot)
    return true
end

function Factory:CreateActionButton(holder, controller, barId, index, page)
    if self:InCombat() then return nil, "combat" end
    local definition = YAB.Adapter and YAB.Adapter:GetActionBarDefinition(barId) or nil
    local name = self:FrameName("Action", barId, index)
    local button = _G[name] or self.pools.buttons[name]
    if not button then
        button = CreateWithTemplates(name, holder, BuildActionTemplates(definition))
        if not button then
            return nil, "secure action button template unavailable"
        end
        if definition and definition.buttonTemplate == "ActionBarButtonTemplate" and not tostring(button.yabTemplate or ""):find("ActionBarButtonTemplate", 1, true) then
            return nil, "ActionBarButtonTemplate unavailable"
        end
        self.pools.buttons[name] = button
    end
    if definition and definition.buttonTemplate == "ActionBarButtonTemplate" and not tostring(button.yabTemplate or ""):find("ActionBarButtonTemplate", 1, true) then
        return nil, "ActionBarButtonTemplate unavailable"
    end
    self:SyncActionButtonState(button, holder, controller, barId, index, page)
    button:Show()
    return button
end

local NATIVE_SPECIAL_BUTTON_PREFIX = {
    pet = "PetActionButton",
    stance = "StanceButton",
    possess = "PossessButton",
}

local NATIVE_SPECIAL_COMMAND_PREFIX = {
    pet = "BONUSACTIONBUTTON",
    stance = "SHAPESHIFTBUTTON",
}

local function ProductMedia(path)
    local Assets = YUI and YUI.Assets
    if Assets and Assets.Product then
        return Assets:Product(YAB.PRODUCT_ID or "yactionbar", path)
    end
    return "Interface\\AddOns\\" .. (YUI and YUI.AddonName or "YUI") .. "\\Products\\YActionBar\\Media\\" .. tostring(path or "")
end

local VEHICLE_EXIT_ICON = ProductMedia("icons\\vehicle-exit-modern.tga")

local function QueueNativePetRefresh(reason)
    if YAB.BarManager and YAB.BarManager.QueueSpecialRefresh then
        YAB.BarManager:QueueSpecialRefresh("pet", reason or "pet-refresh")
    end
end

local function NativePetActionDragAllowed()
    local locked = false
    local settings = _G.Settings
    if settings and type(settings.GetValue) == "function" then
        local ok, value = pcall(settings.GetValue, "lockActionBars")
        locked = ok and value == true
    end
    if not locked then return true end
    return _G.IsModifiedClick and _G.IsModifiedClick("PICKUPACTION") == true
end

local function NativePetButtonOnDragStart(button)
    if ProductInCombat() or not NativePetActionDragAllowed() then return end
    if button and button.SetChecked then
        button:SetChecked(false)
    end
    if _G.PickupPetAction then
        pcall(_G.PickupPetAction, button and button.GetID and button:GetID() or 0)
    end
    QueueNativePetRefresh("pet-drag")
end

local function NativePetButtonOnReceiveDrag(button)
    if ProductInCombat() then return end
    if _G.GetCursorInfo then
        local cursorType = _G.GetCursorInfo()
        if cursorType and cursorType ~= "petaction" then return end
    end
    if button and button.SetChecked then
        button:SetChecked(false)
    end
    if _G.PickupPetAction then
        pcall(_G.PickupPetAction, button and button.GetID and button:GetID() or 0)
    end
    QueueNativePetRefresh("pet-drag")
end

local function NativePetButtonOnClick()
    QueueNativePetRefresh("pet-click")
end

local function FallbackPetButtonOnClick(button, mouseButton)
    if mouseButton ~= "RightButton" then
        QueueNativePetRefresh("pet-click")
        return
    end
    if ProductInCombat() then return end
    if _G.TogglePetAutocast then
        pcall(_G.TogglePetAutocast, button and button.GetID and button:GetID() or 0)
    end
    QueueNativePetRefresh("pet-autocast")
end

function Factory:InstallNativePetDragGuard(button)
    if not button or self:InCombat() then return false end
    if self.nativePetDragGuardInstalled[button] then return true end
    if button.RegisterForDrag then
        pcall(button.RegisterForDrag, button, "LeftButton")
    end
    local dragOk = SetScriptSafe(button, "OnDragStart", NativePetButtonOnDragStart)
    local receiveOk = SetScriptSafe(button, "OnReceiveDrag", NativePetButtonOnReceiveDrag)
    if dragOk and receiveOk then
        self.nativePetDragGuardInstalled[button] = true
        return true
    end
    return false
end

function Factory:InstallNativePetClickRefresh(button)
    if not button then return false end
    if self.nativePetClickRefreshInstalled[button] then return true end
    if type(button.HookScript) ~= "function" then return false end
    local ok = pcall(button.HookScript, button, "OnClick", NativePetButtonOnClick)
    if ok then
        self.nativePetClickRefreshInstalled[button] = true
        return true
    end
    return false
end

function Factory:InstallFallbackPetClick(button)
    if not button then return false end
    if self.fallbackPetClickInstalled[button] then return true end
    if type(button.HookScript) ~= "function" then return false end
    local ok = pcall(button.HookScript, button, "OnClick", FallbackPetButtonOnClick)
    if ok then
        self.fallbackPetClickInstalled[button] = true
        return true
    end
    return false
end

function Factory:GetNativeSpecialButton(kind, index)
    if Client.nativeSpecialButtons ~= true then return nil end
    local prefix = NATIVE_SPECIAL_BUTTON_PREFIX[kind]
    return prefix and _G[prefix .. tostring(index)] or nil
end

function Factory:PrepareNativeSpecialButton(holder, kind, index)
    local button = self:GetNativeSpecialButton(kind, index)
    if not button then return nil end
    self:CaptureNativeSpecialState(button)
    if kind == "pet" then
        if not self:InstallNativePetDragGuard(button) then
            return nil
        end
        self:InstallNativePetClickRefresh(button)
    end
    button:SetParent(holder)
    if holder.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    end
    button:SetID(index)
    self:NeutralizeButtonArt(button, "special")
    local commandPrefix = NATIVE_SPECIAL_COMMAND_PREFIX[kind]
    local buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey and YAB.Keybinds:GetButtonKey(kind, index) or nil
    self:SetButtonMeta(button, {
        barId = kind,
        index = index,
        buttonKey = buttonKey,
        commandName = commandPrefix and (commandPrefix .. tostring(index)) or nil,
        nativeSpecial = true,
    })
    self:InstallNativeSpecialTooltipGuard(button, kind)
    self.nativeSpecialButtons[button] = true
    button:Show()
    return button
end

function Factory:CreatePetButton(holder, index)
    if self:InCombat() then return nil, "combat" end
    local nativeButton = self:PrepareNativeSpecialButton(holder, "pet", index)
    if nativeButton then return nativeButton end
    local name = self:FrameName("Pet", "pet", index)
    local button = _G[name] or self.pools.buttons[name]
    if not button then
        button = CreateWithTemplates(name, holder, { "SecureActionButtonTemplate" })
        if not button then return nil, "pet template unavailable" end
        self.pools.buttons[name] = button
    end
    button:SetParent(holder)
    if holder.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    end
    button:SetID(index)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", nil)
    button:SetAttribute("type1", "pet")
    button:SetAttribute("type2", nil)
    button:SetAttribute("action", index)
    button:SetAttribute("action1", index)
    self:InstallFallbackPetClick(button)
    self:NeutralizeButtonArt(button)
    local commandName = "BONUSACTIONBUTTON" .. tostring(index)
    self:SetButtonMeta(button, {
        barId = "pet",
        index = index,
        buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey and YAB.Keybinds:GetButtonKey("pet", index) or nil,
        commandName = commandName,
    })
    button:Show()
    return button
end

function Factory:CreateOwnedRetailStanceButton(holder, index)
    if Client.ownedStanceButtons ~= true then return nil, "unsupported version" end
    if self:InCombat() then return nil, "combat" end
    local name = self:FrameName("Stance", "stance", index)
    local button = _G[name] or self.pools.buttons[name]
    if not button then
        button = CreateWithTemplates(name, holder, { "StanceButtonTemplate" })
        if not button then return nil, "stance template unavailable" end
        self.pools.buttons[name] = button
    elseif button.yabTemplate ~= "StanceButtonTemplate" then
        return nil, "stance template mismatch"
    end
    button:SetParent(holder)
    if holder.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    end
    button:SetID(index)
    self:NeutralizeButtonArt(button, "special")
    local commandName = "SHAPESHIFTBUTTON" .. tostring(index)
    local buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey
        and YAB.Keybinds:GetButtonKey("stance", index) or nil
    self:SetButtonMeta(button, {
        barId = "stance",
        index = index,
        buttonKey = buttonKey,
        commandName = commandName,
        ownedStanceTemplate = true,
    })
    button.commandName = commandName
    button.bindingAction = commandName
    self:InstallNativeSpecialTooltipGuard(button, "stance")
    return button
end

function Factory:PrecreateRetailStanceButtons(holder)
    if Client.ownedStanceButtons ~= true then return true end
    if self:InCombat() then return false, "combat" end
    for index = 1, RETAIL_STANCE_BUTTON_CAPACITY do
        local button, reason = self:CreateOwnedRetailStanceButton(holder, index)
        if not button then return false, reason end
        button:Hide()
    end
    return true
end

function Factory:CreateStanceButton(holder, index)
    if self:InCombat() then return nil, "combat" end
    if Client.ownedStanceButtons == true then
        local button, reason = self:CreateOwnedRetailStanceButton(holder, index)
        if not button then return nil, reason end
        button:Show()
        return button
    end
    local name = self:FrameName("Stance", "stance", index)
    local button = _G[name] or self.pools.buttons[name]
    if not button then
        button = CreateWithTemplates(name, holder, { "SecureActionButtonTemplate" })
        if not button then return nil, "stance template unavailable" end
        self.pools.buttons[name] = button
    end
    button:SetParent(holder)
    if holder.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    end
    button:SetID(index)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("type1", "spell")
    self:NeutralizeButtonArt(button)
    local commandName = "SHAPESHIFTBUTTON" .. tostring(index)
    self:SetButtonMeta(button, {
        barId = "stance",
        index = index,
        buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey and YAB.Keybinds:GetButtonKey("stance", index) or nil,
        commandName = commandName,
    })
    button:Show()
    return button
end

function Factory:CreatePossessButton(holder, index)
    if self:InCombat() then return nil, "combat" end
    local nativeButton = self:PrepareNativeSpecialButton(holder, "possess", index)
    if nativeButton then return nativeButton end
    local name = self:FrameName("Possess", "possess", index)
    local button = _G[name] or self.pools.buttons[name]
    if not button then
        button = CreateWithTemplates(name, holder, { "SecureActionButtonTemplate" })
        if not button then return nil, "possess template unavailable" end
        self.pools.buttons[name] = button
    end
    button:SetParent(holder)
    if holder.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    end
    button:SetID(index)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("type1", "spell")
    self:NeutralizeButtonArt(button)
    self:SetButtonMeta(button, {
        barId = "possess",
        index = index,
        buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey and YAB.Keybinds:GetButtonKey("possess", index) or nil,
    })
    button:Show()
    return button
end

function Factory:CreateVehicleExitButton(holder)
    if self:InCombat() then return nil, "combat" end
    local name = self:FrameName("VehicleExit", "vehicleExit", 1)
    local button = _G[name] or self.pools.buttons[name]
    if not button then
        button = CreateWithTemplates(name, holder, { "SecureActionButtonTemplate" })
        if not button then return nil, "vehicle exit template unavailable" end
        self.pools.buttons[name] = button
    end
    button:SetParent(holder)
    if holder and holder.GetFrameLevel and button.SetFrameLevel then
        button:SetFrameLevel((holder:GetFrameLevel() or 1) + 1)
    end
    button:SetID(1)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("type", "leavevehicle")
    button:SetAttribute("type1", "leavevehicle")
    button:SetAttribute("type2", "leavevehicle")
    button:SetAttribute("useparent*", false)
    button.commandName = nil
    button.bindingAction = nil
    if not button.icon then
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        button.icon = icon
    end
    if button.icon then
        button.icon:SetTexture(VEHICLE_EXIT_ICON)
        button.icon:SetTexCoord(0, 1, 0, 1)
        button.icon:Show()
    end
    self:SetButtonMeta(button, {
        barId = "vehicleExit",
        index = 1,
        buttonKey = YAB.Keybinds and YAB.Keybinds.GetButtonKey and YAB.Keybinds:GetButtonKey("vehicleExit", 1) or nil,
        externalSpecial = true,
        ownedSpecial = true,
    })
    button:Show()
    return button
end

function Factory:GetPoolStats()
    local movers, holders, controllers, buttons = 0, 0, 0, 0
    for _ in pairs(self.pools.movers) do movers = movers + 1 end
    for _ in pairs(self.pools.holders) do holders = holders + 1 end
    for _ in pairs(self.pools.controllers) do controllers = controllers + 1 end
    for _ in pairs(self.pools.buttons) do buttons = buttons + 1 end
    local nativeCooldown = self:GetNativeCooldownRegistrationStats()
    return {
        movers = movers,
        holders = holders,
        controllers = controllers,
        buttons = buttons,
        strippedButtons = self.stripCount or 0,
        buttonBackend = self.buttonBackend,
        detachedActionButtons = self.detachedScriptCount or 0,
        nativeSpecialButtons = CountMapKeys(self.nativeSpecialButtons),
        nativeCooldownRegistered = nativeCooldown.nativeRegistered or 0,
        nativeCooldownRegisterFails = nativeCooldown.nativeRegisterFails or 0,
        nativeCooldownRegisterAPI = nativeCooldown.nativeRegisterAPI or "none",
    }
end

local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
local GUI2 = YUI.GUI2
local Keybinds = YAB.Keybinds
local KeybindMode = {}
YAB.KeybindMode = KeybindMode

local ACCOUNT_BINDINGS = Enum and Enum.BindingSet and Enum.BindingSet.Account or 1
local CHARACTER_BINDINGS = Enum and Enum.BindingSet and Enum.BindingSet.Character or 2
local FORCED_CANCEL_REASONS = {
    combat = true,
    disable = true,
    disabled = true,
    profile = true,
    rebuild = true,
    shutdown = true,
    system = true,
    command = true,
}
local MOUSE_KEYS = {
    MiddleButton = "BUTTON3",
    Button3 = "BUTTON3",
    Button4 = "BUTTON4",
    Button5 = "BUTTON5",
    Button6 = "BUTTON6",
    Button7 = "BUTTON7",
    Button8 = "BUTTON8",
}

KeybindMode.hookedButtons = KeybindMode.hookedButtons or setmetatable({}, { __mode = "k" })

local function T(key, fallback)
    local locale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("YActionBar") or nil
    local value = locale and locale[key]
    if type(value) == "string" and value ~= "" then return value end
    return fallback or key
end

local function TF(key, fallback, ...)
    local template = T(key, fallback)
    local ok, value = pcall(string.format, template, ...)
    return ok and value or template
end

local function PrintMessage(message)
    if YUI.Print then
        YUI:Print(message)
    elseif print then
        print(message)
    end
end

local function InCombat()
    return YAB.Adapter and YAB.Adapter.InCombat and YAB.Adapter:InCombat() == true
end

local function IsLayoutEditing()
    return YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() == true
end

local function HasActiveChatInput()
    local chatFrameUtil = _G.ChatFrameUtil
    if chatFrameUtil and chatFrameUtil.GetActiveWindow then
        return chatFrameUtil.GetActiveWindow() ~= nil
    end
    if _G.ChatEdit_GetActiveWindow then
        return _G.ChatEdit_GetActiveWindow() ~= nil
    end
    return _G.ACTIVE_CHAT_EDIT_BOX ~= nil
end

local function BuildChord(key)
    if not key or key == "" then return nil end
    if key == "LSHIFT" or key == "RSHIFT"
        or key == "LCTRL" or key == "RCTRL"
        or key == "LALT" or key == "RALT"
        or key == "UNKNOWN"
    then
        return nil
    end
    local parts = {}
    if IsControlKeyDown and IsControlKeyDown() then parts[#parts + 1] = "CTRL" end
    if IsAltKeyDown and IsAltKeyDown() then parts[#parts + 1] = "ALT" end
    if IsShiftKeyDown and IsShiftKeyDown() then parts[#parts + 1] = "SHIFT" end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

local function SetFrameShown(frame, shown)
    if not frame then return end
    if shown then frame:Show() else frame:Hide() end
end

local function GetTextWidth(text)
    if not (text and text.GetStringWidth) then return 0 end
    return math.ceil(tonumber(text:GetStringWidth()) or 0)
end

function KeybindMode:SetStatus(text, tone)
    if not self.statusText then return end
    local hasText = type(text) == "string" and text ~= ""
    self.statusText:SetText(hasText and text or "")
    SetFrameShown(self.statusText, hasText)
    if not hasText then return end
    if GUI2 and GUI2.SetTextColorKey then
        local colorKey = "color.text.secondary"
        if tone == "success" then
            colorKey = "color.state.success"
        elseif tone == "warning" then
            colorKey = "color.state.warning"
        elseif tone == "danger" then
            colorKey = "color.state.error"
        elseif tone == "accent" then
            colorKey = "color.text.accent"
        end
        GUI2:SetTextColorKey(self.statusText, colorKey)
    end
end

function KeybindMode:GetEligibleCount()
    local session = Keybinds and Keybinds:GetSessionState()
    local count = 0
    for _ in pairs(session and session.bindings or {}) do
        count = count + 1
    end
    return count
end

function KeybindMode:GetHoveredButtonTitle()
    local button = self.hoverButton
    local meta = YAB.SecureFactory and YAB.SecureFactory.GetButtonMeta and YAB.SecureFactory:GetButtonMeta(button) or nil
    local barId = meta and meta.barId or nil
    local index = meta and meta.index or nil
    if not barId and YAB.BarManager then
        barId = YAB.BarManager.externalButtonOwners and YAB.BarManager.externalButtonOwners[button] or nil
        index = YAB.BarManager.externalButtonIndices and YAB.BarManager.externalButtonIndices[button] or nil
    end
    if not barId and type(self.hoverButtonKey) == "string" then
        local parsedBarId, parsedIndex = self.hoverButtonKey:match("^(.+)%.(%d+)$")
        barId = parsedBarId
        index = tonumber(parsedIndex)
    end
    if type(barId) == "string" and type(index) == "number" then
        local labelKey = barId == "stance" and Client.ownedStanceButtons == true and "bar.stance.retail" or ("bar." .. barId)
        local label = T(labelKey, barId)
        return TF("keybind_mode.button_title", "%s - Button %d", label, index)
    end
    return Keybinds:GetCommandForButton(self.hoverButtonKey) or self.hoverButtonKey or ""
end

function KeybindMode:UpdateScopeCheckbox()
    local session = Keybinds and Keybinds:GetSessionState()
    if self.characterCheckbox and session then
        self.characterCheckbox:SetChecked(session.selectedBindingSet == CHARACTER_BINDINGS, true)
    end
end

function KeybindMode:RefreshTooltip()
    local tooltip = self.tooltip
    local buttonKey = self.hoverButtonKey
    if not (tooltip and buttonKey and self.hoverButton) then
        SetFrameShown(tooltip, false)
        return
    end
    local session = Keybinds and Keybinds:GetSessionState()
    local keys = session and session.bindings and session.bindings[buttonKey] or nil
    local firstBound = keys and keys[1] ~= nil
    local secondBound = keys and keys[2] ~= nil
    local first = firstBound and Keybinds:FormatBindingDisplayText(keys[1]) or T("keybind_mode.unbound", "Not set")
    local second = secondBound and Keybinds:FormatBindingDisplayText(keys[2]) or T("keybind_mode.unbound", "Not set")
    if tooltip.heading then tooltip.heading:SetText(self:GetHoveredButtonTitle()) end
    if tooltip.binding1Value then tooltip.binding1Value:SetText(first) end
    if tooltip.binding2Value then tooltip.binding2Value:SetText(second) end
    if GUI2 and GUI2.SetTextColorKey then
        if tooltip.binding1Value then GUI2:SetTextColorKey(tooltip.binding1Value, firstBound and "color.state.warning" or "color.text.muted") end
        if tooltip.binding2Value then GUI2:SetTextColorKey(tooltip.binding2Value, secondBound and "color.state.warning" or "color.text.muted") end
    end
    local width = math.max(
        196,
        GetTextWidth(tooltip.heading) + 24,
        GetTextWidth(tooltip.binding1Label) + GetTextWidth(tooltip.binding1Value) + 44,
        GetTextWidth(tooltip.binding2Label) + GetTextWidth(tooltip.binding2Value) + 44,
        GetTextWidth(tooltip.escapeKey) + GetTextWidth(tooltip.escapeAction) + 29
    )
    width = math.min(width, 280)
    tooltip:SetWidth(width)
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMLEFT", self.hoverButton, "TOPRIGHT", 8, 8)
    tooltip:Show()
end

function KeybindMode:SetHoveredButton(button, buttonKey)
    if not self.active then return false end
    if self.hoverButton == button and self.hoverButtonKey == buttonKey then return true end

    if self.hoverButton and YAB.Visuals and YAB.Visuals.SetBindHighlight then
        YAB.Visuals:SetBindHighlight(self.hoverButton, false, false)
    end
    self.hoverButton = button
    self.hoverButtonKey = buttonKey

    local proxy = self.hoverProxy
    if button and buttonKey and proxy then
        proxy:ClearAllPoints()
        proxy:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        proxy:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        proxy:Show()
        if YAB.Visuals and YAB.Visuals.SetBindHighlight then
            YAB.Visuals:SetBindHighlight(button, true, true)
        end
    elseif proxy then
        proxy:Hide()
    end
    self:RefreshTooltip()
    return true
end

function KeybindMode:ClearHoveredButton()
    if self.hoverButton and YAB.Visuals and YAB.Visuals.SetBindHighlight then
        YAB.Visuals:SetBindHighlight(self.hoverButton, false, false)
    end
    self.hoverButton = nil
    self.hoverButtonKey = nil
    if self.hoverProxy then self.hoverProxy:Hide() end
    if self.tooltip then self.tooltip:Hide() end
end

function KeybindMode:IsHoveredTargetUnderCursor()
    local proxy = self.hoverProxy
    if proxy and proxy.IsMouseOver and proxy:IsMouseOver() then return true end
    local button = self.hoverButton
    return button and button.IsMouseOver and button:IsMouseOver() == true or false
end

function KeybindMode:ReconcileHoverAfterLeave()
    if not self.active or not self.hoverButton then return false end
    if self:IsHoveredTargetUnderCursor() then return false end
    self:ClearHoveredButton()
    return true
end

function KeybindMode:SyncHoveredButton()
    if not self.active then return false end
    for button, buttonKey in pairs(self.hookedButtons) do
        if buttonKey and button.IsMouseOver and button:IsMouseOver() then
            return self:HandleButtonEnter(button, buttonKey)
        end
    end
    return false
end

function KeybindMode:HandleButtonEnter(button, buttonKey)
    if not self.active or not button or type(buttonKey) ~= "string" or buttonKey == "" then
        return false
    end
    return self:SetHoveredButton(button, buttonKey)
end

function KeybindMode:HookButton(button, buttonKey)
    if not button then return false end
    if self.hookedButtons[button] then
        self.hookedButtons[button] = buttonKey
        return true
    end
    self.hookedButtons[button] = buttonKey
    button:HookScript("OnEnter", function(frame)
        KeybindMode:HandleButtonEnter(frame, KeybindMode.hookedButtons[frame])
    end)
    return true
end

function KeybindMode:ApplyHighlights(shown)
    local visuals = YAB.Visuals
    if not (visuals and visuals.SetBindHighlight) then return end
    if shown == true then return end
    for button in pairs(visuals.bindHighlights or {}) do
        visuals:SetBindHighlight(button, false, false)
    end
end

function KeybindMode:HandleOperationResult(ok, metadata)
    if not ok then
        self:SetStatus(T("keybind_mode.error_operation", "Unable to update this binding."), "danger")
        return false
    end
    local status = type(metadata) == "table" and metadata.status or nil
    if status == "duplicate" then
        self:SetStatus(T("keybind_mode.status_duplicate", "That binding is already assigned to this button."), "warning")
    elseif status == "cleared" then
        self:SetStatus(T("keybind_mode.status_cleared", "Both bindings were cleared."), "success")
    elseif metadata and metadata.conflictAction then
        self:SetStatus(TF("keybind_mode.status_conflict", "Binding moved from %s.", metadata.conflictAction), "warning")
    else
        self:SetStatus(T("keybind_mode.status_assigned", "Binding updated."), "success")
    end
    self:RefreshTooltip()
    return true
end

function KeybindMode:ClearHoveredBindings()
    if not self.hoverButtonKey then
        self:SetStatus(T("keybind_mode.error_no_hover", "Move the cursor over an action button first."), "warning")
        return false
    end
    return self:HandleOperationResult(Keybinds:ClearButton(self.hoverButtonKey))
end

function KeybindMode:AssignHoveredChord(chord)
    if not self.hoverButtonKey then
        self:SetStatus(T("keybind_mode.error_no_hover", "Move the cursor over an action button first."), "warning")
        return false
    end
    if not chord then return false end
    local ok, metadata = Keybinds:AssignChord(self.hoverButtonKey, chord)
    return self:HandleOperationResult(ok, metadata)
end

function KeybindMode:HandleKeyDown(key)
    if not self.active then return end
    local propagate = self.scopeConfirmOpen or HasActiveChatInput() or key == "ENTER" or key == "NUMPADENTER"
    if self.captureFrame and self.captureFrame.SetPropagateKeyboardInput then
        self.captureFrame:SetPropagateKeyboardInput(propagate)
    end
    if propagate then return end
    if key == "ESCAPE" then
        self:ClearHoveredBindings()
        return
    end
    self:AssignHoveredChord(BuildChord(key))
end

function KeybindMode:HandleMouseDown(button)
    if not self.active or self.scopeConfirmOpen then return end
    if button == "LeftButton" or button == "RightButton" then return end
    self:AssignHoveredChord(BuildChord(MOUSE_KEYS[button]))
end

function KeybindMode:HandleMouseWheel(delta)
    if not self.active or self.scopeConfirmOpen then return end
    self:AssignHoveredChord(BuildChord(delta and delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
end

function KeybindMode:EnsureUI()
    if self.frame then return true end
    if not (GUI2 and GUI2.CreateFrame and GUI2.CreatePanel and GUI2.CreateText and GUI2.CreateTexture and GUI2.SetTexturePaintKey and GUI2.Form) then
        return false, "GUI2 unavailable"
    end

    local dimmer = GUI2:CreateFrame(UIParent, {
        name = "YUI_YActionBar_KeybindDimmer",
        allPoints = true,
        strata = "HIGH",
        level = 900,
        mouse = false,
        hidden = true,
    })
    local shade = GUI2:CreateTexture(dimmer, nil, "BACKGROUND")
    GUI2:SetTexturePaintKey(shade, "color.overlay.shadow")
    shade:SetAllPoints(dimmer)
    dimmer.shade = shade

    local panel = GUI2:CreatePanel(UIParent, {
        name = "YUI_YActionBar_KeybindPanel",
        width = 460,
        height = 224,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(frame)
        if KeybindMode.active then frame:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
    end)
    panel:Hide()

    local title = GUI2:CreateText(panel, T("keybind_mode.title", "Keybinding Mode"), "font.size.xl", "color.text.heading", "CENTER")
    title:SetPoint("TOPLEFT", 20, -15)
    title:SetPoint("TOPRIGHT", -20, -15)

    local description = GUI2:CreateText(panel, T("keybind_mode.description", "Hover an action button, then press a keyboard or mouse input.\nEach button keeps the latest two bindings; ESC clears the current button."), "font.size.md", "color.text.secondary", "CENTER")
    description:SetPoint("TOPLEFT", 24, -49)
    description:SetPoint("TOPRIGHT", -24, -49)
    description:SetHeight(40)
    description:SetWordWrap(true)

    local status = GUI2:CreateText(panel, "", "font.size.md", "color.text.secondary", "CENTER")
    status:SetPoint("TOPLEFT", 24, -101)
    status:SetPoint("TOPRIGHT", -24, -101)
    status:SetHeight(24)
    status:SetWordWrap(false)
    status:Hide()

    local checkbox = GUI2.Form:CreateCheckbox(panel, {
        text = T("keybind_mode.character_specific", "Character-specific keybindings"),
        width = 250,
        height = 30,
        onClick = function(_, checked)
            KeybindMode:RequestScopeSwitch(checked == true)
        end,
    })
    checkbox:SetPoint("BOTTOM", panel, "BOTTOM", 0, 56)

    local save = GUI2.Form:CreateButton(panel, {
        text = T("keybind_mode.save", "Save"),
        width = 120,
        height = 30,
        tone = "success",
        onClick = function() YAB:CommitBindMode() end,
    })
    save:SetPoint("BOTTOM", panel, "BOTTOM", -68, 17)

    local cancel = GUI2.Form:CreateButton(panel, {
        text = T("keybind_mode.cancel", "Cancel"),
        width = 120,
        height = 30,
        tone = "default",
        onClick = function() YAB:CancelBindMode("cancel") end,
    })
    cancel:SetPoint("BOTTOM", panel, "BOTTOM", 68, 17)

    local capture = GUI2:CreateFrame(UIParent, {
        name = "YUI_YActionBar_KeybindCapture",
        allPoints = true,
        strata = "FULLSCREEN_DIALOG",
        level = 1000,
        mouse = false,
        hidden = true,
    })
    capture:EnableKeyboard(true)
    if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(false) end
    capture:SetScript("OnKeyDown", function(_, key) KeybindMode:HandleKeyDown(key) end)

    local proxy = GUI2:CreateFrame(UIParent, {
        name = "YUI_YActionBar_KeybindHoverProxy",
        strata = "DIALOG",
        level = 50,
        mouse = true,
        mouseWheel = true,
        hidden = true,
    })
    proxy:SetScript("OnMouseDown", function(_, button) KeybindMode:HandleMouseDown(button) end)
    proxy:SetScript("OnMouseWheel", function(_, delta) KeybindMode:HandleMouseWheel(delta) end)
    proxy:SetScript("OnLeave", function() KeybindMode:ReconcileHoverAfterLeave() end)

    local tooltip = GUI2:CreatePanel(UIParent, {
        name = "YUI_YActionBar_KeybindHoverPanel",
        width = 196,
        height = 118,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    tooltip:SetFrameStrata("DIALOG")
    tooltip:SetFrameLevel(600)
    if tooltip.SetClampedToScreen then tooltip:SetClampedToScreen(true) end
    local tooltipHeading = GUI2:CreateText(tooltip, "", "font.size.md", "color.text.heading", "LEFT")
    tooltipHeading:SetPoint("TOPLEFT", 12, -10)
    tooltipHeading:SetPoint("TOPRIGHT", -12, -10)
    tooltipHeading:SetWordWrap(false)
    local binding1Label = GUI2:CreateText(tooltip, T("keybind_mode.binding_1", "Binding 1"), "font.size.md", "color.text.secondary", "LEFT")
    binding1Label:SetPoint("TOPLEFT", 12, -36)
    local binding1Value = GUI2:CreateText(tooltip, "", "font.size.md", "color.text.muted", "RIGHT")
    binding1Value:SetPoint("TOPRIGHT", -12, -36)
    local binding2Label = GUI2:CreateText(tooltip, T("keybind_mode.binding_2", "Binding 2"), "font.size.md", "color.text.secondary", "LEFT")
    binding2Label:SetPoint("TOPLEFT", 12, -58)
    local binding2Value = GUI2:CreateText(tooltip, "", "font.size.md", "color.text.muted", "RIGHT")
    binding2Value:SetPoint("TOPRIGHT", -12, -58)
    local escapeKey = GUI2:CreateText(tooltip, T("keybind_mode.escape_key", "ESC"), "font.size.md", "color.state.error", "LEFT")
    escapeKey:SetPoint("BOTTOMLEFT", 12, 12)
    local escapeAction = GUI2:CreateText(tooltip, T("keybind_mode.escape_action", "Clear both bindings"), "font.size.md", "color.state.success", "LEFT")
    escapeAction:SetPoint("LEFT", escapeKey, "RIGHT", 5, 0)
    tooltip.heading = tooltipHeading
    tooltip.binding1Label = binding1Label
    tooltip.binding1Value = binding1Value
    tooltip.binding2Label = binding2Label
    tooltip.binding2Value = binding2Value
    tooltip.escapeKey = escapeKey
    tooltip.escapeAction = escapeAction
    tooltip:Hide()

    self.frame = panel
    self.dimmer = dimmer
    self.captureFrame = capture
    self.hoverProxy = proxy
    self.tooltip = tooltip
    self.statusText = status
    self.characterCheckbox = checkbox
    self.saveButton = save
    self.cancelButton = cancel
    return true
end

function KeybindMode:ClearScopeConfirmOwnership(hideOwned)
    local settings = YUI.Settings
    local frame = self.scopeConfirmFrame
    local ownsFrame = self.scopeConfirmOpen == true
        and frame ~= nil
        and settings ~= nil
        and settings.ConfirmFrame == frame
        and frame.onAccept == self.scopeConfirmAccept
        and frame.onCancel == self.scopeConfirmCancel
    if ownsFrame then
        if hideOwned == true and frame.IsShown and frame:IsShown() then frame:Hide() end
        frame.onAccept = nil
        frame.onCancel = nil
    end
    self.scopeConfirmOpen = false
    self.scopeConfirmToken = nil
    self.scopeConfirmFrame = nil
    self.scopeConfirmAccept = nil
    self.scopeConfirmCancel = nil
    return ownsFrame
end

function KeybindMode:PerformScopeSwitch(targetSet)
    self:ClearScopeConfirmOwnership(false)
    local ok = Keybinds:SwitchBindingSet(targetSet)
    if not ok then
        self:UpdateScopeCheckbox()
        self:SetStatus(T("keybind_mode.error_scope", "Unable to switch keybinding scope."), "danger")
        return false
    end
    self:UpdateScopeCheckbox()
    self:ClearHoveredButton()
    self:SetStatus(targetSet == CHARACTER_BINDINGS
        and T("keybind_mode.status_character", "Character-specific keybindings selected.")
        or T("keybind_mode.status_account", "Account keybindings selected."), "success")
    return true
end

function KeybindMode:RequestScopeSwitch(characterSpecific)
    if self.scopeConfirmOpen then
        self:UpdateScopeCheckbox()
        return false
    end
    local session = Keybinds and Keybinds:GetSessionState()
    if not session then return false end
    local targetSet = characterSpecific and CHARACTER_BINDINGS or ACCOUNT_BINDINGS
    if targetSet == session.selectedBindingSet then return true end

    local needsConfirm = session.dirty == true
        or (session.selectedBindingSet == CHARACTER_BINDINGS and targetSet == ACCOUNT_BINDINGS)
    if not needsConfirm then
        return self:PerformScopeSwitch(targetSet)
    end

    local settings = YUI.Settings
    if not (settings and settings.ShowConfirmPopup) then
        self:UpdateScopeCheckbox()
        self:SetStatus(T("keybind_mode.error_confirm", "A confirmation dialog is unavailable."), "danger")
        return false
    end
    local messageKey = session.dirty == true and "keybind_mode.confirm_discard_dirty" or "keybind_mode.confirm_account_risk"
    local token = {}
    local acceptCallback
    local cancelCallback
    acceptCallback = function()
        if KeybindMode.scopeConfirmToken ~= token then return end
        KeybindMode:ClearScopeConfirmOwnership(false)
        KeybindMode:PerformScopeSwitch(targetSet)
    end
    cancelCallback = function()
        if KeybindMode.scopeConfirmToken ~= token then return end
        KeybindMode:ClearScopeConfirmOwnership(false)
        KeybindMode:UpdateScopeCheckbox()
    end
    self.scopeConfirmOpen = true
    self.scopeConfirmToken = token
    self.scopeConfirmAccept = acceptCallback
    self.scopeConfirmCancel = cancelCallback
    settings:ShowConfirmPopup(T(messageKey, "Discard unsaved keybinding changes and switch scope?"), acceptCallback, {
        titleText = T("keybind_mode.confirm_title", "Switch Keybinding Scope"),
        acceptText = T("keybind_mode.confirm_switch", "Switch"),
        onCancel = cancelCallback,
    })
    if self.scopeConfirmToken == token then
        self.scopeConfirmFrame = settings.ConfirmFrame
    end
    return true
end

function KeybindMode:ShowUI()
    if YUI.Animation and YUI.Animation.StopOwner then
        YUI.Animation:StopOwner(self)
    end
    self.dimmer:SetAlpha(1)
    self.dimmer:Show()
    if GUI2 and GUI2.FadeIn then
        GUI2:FadeIn(self.dimmer, {
            from = 0,
            to = 1,
            duration = 0.20,
            owner = self,
            key = "keybind-dimmer",
        })
    end
    self.frame:Show()
    self.captureFrame:Show()
    self:UpdateScopeCheckbox()
    self:SetStatus(nil)
end

function KeybindMode:HideUI()
    if YUI.Animation and YUI.Animation.StopOwner then
        YUI.Animation:StopOwner(self)
    end
    self:ClearScopeConfirmOwnership(true)
    self:ClearHoveredButton()
    if self.captureFrame then self.captureFrame:Hide() end
    if self.frame then self.frame:Hide() end
    if self.dimmer then
        self.dimmer:SetAlpha(1)
        self.dimmer:Hide()
    end
    if GameTooltip then GameTooltip:Hide() end
end

function KeybindMode:CloseSettingsSource()
    if self.source ~= "settings" then return end
    local settings = YUI.Settings
    if settings and settings.IsOpen and settings:IsOpen() and settings.Close then
        settings:Close()
    end
end

function KeybindMode:ReturnToSource(source, barId, forced)
    if forced or source ~= "settings" then return end
    if YAB.OpenSettings then YAB:OpenSettings(barId) end
end

function KeybindMode:Enter(source, barId)
    if self.active then return true end
    if InCombat() then
        PrintMessage(T("keybind_mode.error_combat", "Keybind mode cannot be opened in combat."))
        return false, "combat"
    end
    if not (YAB.IsEnabled and YAB:IsEnabled() and YAB.BarManager and YAB.BarManager.runtimeActive == true) then
        PrintMessage(T("keybind_mode.error_runtime", "Enable YActionBar before opening keybind mode."))
        return false, "runtime inactive"
    end
    if IsLayoutEditing() then
        PrintMessage(T("keybind_mode.error_layout", "Exit layout edit mode before editing keybindings."))
        return false, "layout edit"
    end
    local suppression = Keybinds and Keybinds:GetSystemBindingSuppressionReason()
    if suppression then
        PrintMessage(T("keybind_mode.error_suppressed", "Keybindings are managed by the current system mode."))
        return false, suppression
    end
    local uiReady, uiReason = self:EnsureUI()
    if not uiReady then return false, uiReason end
    if Keybinds:GetSessionState() and not Keybinds:RollbackSession("stale session") then
        return false, "stale session"
    end
    local session, sessionReason = Keybinds:BeginSession()
    if not session then return false, sessionReason end
    local presented, presentationReason = YAB.BarManager:SetBindPresentation(true, "keybind enter")
    if not presented then
        Keybinds:RollbackSession("presentation failed")
        return false, presentationReason
    end
    Keybinds:RefreshSessionBindings(true)
    if self:GetEligibleCount() == 0 then
        YAB.BarManager:SetBindPresentation(false, "keybind no eligible buttons")
        Keybinds:RollbackSession("no eligible buttons")
        PrintMessage(T("keybind_mode.error_no_buttons", "No enabled bindable action buttons are available."))
        return false, "no eligible buttons"
    end

    self.active = true
    self.source = source or "command"
    self.sourceBarId = barId
    self.pendingRollback = false
    self.pendingRollbackSession = nil
    self:CloseSettingsSource()
    self:ShowUI()
    self:SyncHoveredButton()
    return true
end

function KeybindMode:FinishClose(reason, forced)
    local source = self.source
    local barId = self.sourceBarId
    self.active = false
    self.source = nil
    self.sourceBarId = nil
    self:ApplyHighlights(false)
    self:HideUI()
    if YAB.BarManager then
        YAB.BarManager:SetBindPresentation(false, "keybind " .. tostring(reason or "exit"))
    end
    self:ReturnToSource(source, barId, forced)
    return true
end

function KeybindMode:Commit()
    if not self.active then return false, "inactive" end
    local ok = Keybinds:CommitSession()
    if not ok then
        self:SetStatus(T("keybind_mode.error_save", "Unable to save keybindings. Try again."), "danger")
        return false
    end
    return self:FinishClose("save", false)
end

function KeybindMode:QueueRollback(reason)
    local queuedSession = Keybinds and Keybinds:GetSessionState()
    if not queuedSession then
        self.pendingRollback = false
        self.pendingRollbackSession = nil
        return false
    end
    self.pendingRollback = true
    self.pendingRollbackSession = queuedSession
    if YAB.Drivers then
        YAB.Drivers:Queue("keybind rollback", function()
            if Keybinds:GetSessionState() ~= queuedSession then
                if KeybindMode.pendingRollbackSession == queuedSession then
                    KeybindMode.pendingRollback = false
                    KeybindMode.pendingRollbackSession = nil
                end
                return
            end
            local ok = Keybinds:RollbackSession(reason or "forced")
            if KeybindMode.pendingRollbackSession == queuedSession then
                KeybindMode.pendingRollback = ok ~= true
                if ok then KeybindMode.pendingRollbackSession = nil end
            end
            if not ok then
                PrintMessage(T("keybind_mode.error_rollback", "Keybindings could not be restored; use /reload before editing them again."))
            end
        end)
    end
    return true
end

function KeybindMode:Cancel(reason)
    reason = reason or "cancel"
    local forced = FORCED_CANCEL_REASONS[reason] == true
    local session = Keybinds and Keybinds:GetSessionState()
    if not self.active and not session then return true end
    local rolledBack = true
    if session then
        rolledBack = Keybinds:RollbackSession(reason)
    end
    if not rolledBack and not forced then
        self:SetStatus(T("keybind_mode.error_cancel", "Unable to restore keybindings. Try again out of combat."), "danger")
        return false
    end
    if not rolledBack then
        self:QueueRollback(reason)
    else
        self.pendingRollback = false
        self.pendingRollbackSession = nil
    end
    return self:FinishClose(reason, forced)
end

function KeybindMode:Toggle(source, barId)
    if self.active then return self:Cancel(source == "command" and "command" or "cancel") end
    return self:Enter(source, barId)
end

function KeybindMode:GetStats()
    return {
        active = self.active == true,
        pendingRollback = self.pendingRollback == true,
        eligible = self:GetEligibleCount(),
    }
end

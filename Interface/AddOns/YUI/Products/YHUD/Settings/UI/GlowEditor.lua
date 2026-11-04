local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local DesignerUI = YHUD and YHUD.DesignerUI
local I = DesignerUI and DesignerUI._internal
if not I then return end

local GUI2 = I.GUI2
local S = I.S
local Designer = I.Designer
local Catalog = I.Catalog
local ResourceCatalog = I.ResourceCatalog
local Glow = I.Glow
local QUESTION_ICON = I.QUESTION_ICON
local T = I.T
local InCombat = I.InCombat
local Print = I.Print
local GroupName = I.GroupName
local GroupTypeName = I.GroupTypeName
local CountList = I.CountList
local MONITOR_LAYOUTS = I.MONITOR_LAYOUTS
local CanAddMonitor = I.CanAddMonitor
local SetShown = I.SetShown
local BuildDirectionOptions = I.BuildDirectionOptions
local BuildRingDirectionOptions = I.BuildRingDirectionOptions
local BuildAlignmentOptions = I.BuildAlignmentOptions
local BuildOrientationOptions = I.BuildOrientationOptions
local BuildResourceFillDirectionOptions = I.BuildResourceFillDirectionOptions
local BuildIconPositionOptions = I.BuildIconPositionOptions
local BuildShapeOptions = I.BuildShapeOptions
local BuildBorderOptions = I.BuildBorderOptions
local BuildFontOptions = I.BuildFontOptions
local BuildOutlineOptions = I.BuildOutlineOptions
local BuildTextPositionOptions = I.BuildTextPositionOptions
local BuildNameTextPositionOptions = I.BuildNameTextPositionOptions
local BuildNumberOptions = I.BuildNumberOptions
local BuildGlowTriggerOptions = I.BuildGlowTriggerOptions
local BuildGlowStyleOptions = I.BuildGlowStyleOptions
local BuildGlowControlLabels = I.BuildGlowControlLabels
local MonitorActionText = I.MonitorActionText
local IsMonitorPickerFolder = I.IsMonitorPickerFolder
local MonitorName = I.MonitorName

local function IsGlobalTarget(target)
    return target and (target.kind == "global-native" or target.kind == "global-activation")
end

function DesignerUI:GetSelectedGlowMonitor()
    local profile = Designer:GetProfile()
    local monitor = Designer:GetSelectedMonitor()
    if not (profile and monitor and Glow and Glow.SupportsMonitor
        and Glow:SupportsMonitor(profile, monitor)) then
        return nil, profile
    end
    return monitor, profile
end

function DesignerUI:MoveGlowRule(index, offset)
    local monitor = self:GetSelectedGlowMonitor()
    local rules = monitor and monitor.glow and monitor.glow.rules
    local other = index + offset
    if not (rules and rules[index] and rules[other]) then return false end
    -- Close the editor before indices change so it cannot edit a different rule.
    self:HideGlowEditor()
    local config = YHUD:CopyValue(monitor.glow)
    config.rules[index], config.rules[other] = config.rules[other], config.rules[index]
    local result, code = Designer:SetMonitorGlow(monitor.id, config)
    if result then
        self.glowSelectedPreset = nil
        self:RefreshGlowLibrary()
        self:ApplyPreview()
        self:Refresh(false, false)
    end
    return result, code
end

function DesignerUI:GetSelectedMonitorGlow()
    local monitor = self:GetSelectedGlowMonitor()
    if not monitor then return nil end
    if type(monitor.glow) == "table" then
        return YHUD:NormalizeMonitorGlow(monitor.glow)
    end
    return YHUD:GetDefaultMonitorGlow()
end

function DesignerUI:SetSelectedMonitorGlow(definition, refreshEditor)
    local monitor = self:GetSelectedGlowMonitor()
    if not monitor then return nil, "glow-unsupported" end
    local result, code = Designer:SetMonitorGlow(monitor.id, definition)
    if not result then return nil, code end
    self:ApplyPreview()
    if refreshEditor ~= false then
        self:RefreshGlowEditor(false)
    end
    if self.monitorGlowButton then
        self.monitorGlowButton:SetText(result and result.rules
            and #result.rules > 0
            and T("designer.glow.open_enabled", "发光设置 · 已启用")
            or T("designer.glow.open", "发光设置"))
    end
    return result
end

function DesignerUI:SetSelectedMonitorGlowEnabled(enabled)
    local config = self:GetSelectedMonitorGlow()
    if not config then return nil, "glow-unsupported" end
    if enabled ~= true then config = nil
    elseif #(config.rules or {}) == 0 then
        config.rules = {
            {
                condition = { type = "self-ready" },
                appearance = YHUD:GetDefaultMonitorGlowAppearance(),
            },
        }
    end
    return self:SetSelectedMonitorGlow(config, false)
end

function DesignerUI:SetSelectedMonitorGlowTrigger(conditionType)
    if conditionType ~= "self-ready"
        and conditionType ~= "self-cooldown" then
        return nil, "invalid-glow-condition"
    end
    local config = self:GetSelectedMonitorGlow()
    if not config then return nil, "glow-unsupported" end
    config.rules = config.rules or {}
    config.rules[1] = config.rules[1] or {
        appearance = YHUD:GetDefaultMonitorGlowAppearance(),
    }
    config.rules[1].condition = { type = conditionType }
    return self:SetSelectedMonitorGlow(config, false)
end

function DesignerUI:SetSelectedMonitorGlowCombatOnly(enabled)
    local config = self:GetSelectedMonitorGlow()
    if not config then return nil, "glow-unsupported" end
    if not (config.rules and config.rules[1]) then
        return nil, "glow-rule-not-found"
    end
    config.rules[1].combatOnly = enabled == true and true or nil
    return self:SetSelectedMonitorGlow(config, false)
end

function DesignerUI:SetSelectedMonitorGlowAppearance(appearance)
    local config = self:GetSelectedMonitorGlow()
    if not config then return nil, "glow-unsupported" end
    if not (config.rules and config.rules[1]) then
        return nil, "glow-rule-not-found"
    end
    config.rules[1].appearance = appearance
    return self:SetSelectedMonitorGlow(config, false)
end

function DesignerUI:GetGlowEditAppearance()
    local target = self.glowEditTarget
    local monitor, profile = self:GetSelectedGlowMonitor()
    profile = profile or Designer:GetProfile()
    if not (target and profile) then return nil end
    if IsGlobalTarget(target) and profile ~= self.glowProfile then return nil end
    if not IsGlobalTarget(target) and not (monitor and monitor.id == self.glowMonitorId) then return nil end
    if self.glowPendingAppearance then return self.glowPendingAppearance end
    if target.kind == "global-activation" then
        return YHUD:GetAuraActivationStyle(profile).appearance or YHUD:GetDefaultMonitorGlowAppearance()
    end
    if target.kind == "global-native" then
        local config = profile.style and profile.style.nativeProcGlow
        return config and config.appearance
            or YHUD:GetDefaultMonitorGlowAppearance()
    end
    if target.kind == "monitor-native" then
        local config = monitor and monitor.nativeProcGlowOverride
        return config and config.appearance
            or YHUD:GetDefaultMonitorGlowAppearance()
    end
    local rules = monitor and monitor.glow and monitor.glow.rules
    local rule = rules and rules[target.ruleIndex]
    return rule and rule.appearance or nil
end

local function SameAppearance(left, right)
    for key, value in pairs(left) do
        if key == "color" then
            for index = 1, 4 do
                if value[index] ~= right.color[index] then return false end
            end
        elseif value ~= right[key] then return false end
    end
    return true
end

function DesignerUI:SyncGlowAppearancePreview(appearance)
    local view = YHUD.View
    local monitor = self:GetSelectedGlowMonitor()
    if not (view and view.SetDesignGlowPreview and monitor and monitor.id == self.glowMonitorId
        and self.glowEditor and self.glowEditor:IsShown()) then return false end
    appearance = appearance or self:GetGlowEditAppearance()
    if not appearance then return false end
    view:SetDesignGlowPreview(monitor.id, monitor.groupId, appearance)
    return true
end

function DesignerUI:PreviewGlowAppearance(appearance)
    local current = self:GetGlowEditAppearance()
    if not current then return false end
    self.glowSliderStart = self.glowSliderStart or current
    appearance = YHUD:NormalizeMonitorGlowAppearance(appearance)
    self.glowPendingAppearance = not SameAppearance(appearance, self.glowSliderStart)
        and appearance or nil
    self:SyncGlowAppearancePreview(appearance)
    return true
end

function DesignerUI:FinishGlowSliderEdit()
    local appearance = self.glowPendingAppearance
    self.glowPendingAppearance, self.glowSliderStart = nil, nil
    if appearance then return self:SetGlowEditAppearance(appearance) end
end

function DesignerUI:SetGlowEditAppearance(appearance)
    if self.glowSliderPreviewing then return self:PreviewGlowAppearance(appearance) end
    local target = self.glowEditTarget
    local monitor, profile = self:GetSelectedGlowMonitor()
    profile = profile or Designer:GetProfile()
    if not (target and profile) or not IsGlobalTarget(target)
        and not (monitor and monitor.id == self.glowMonitorId) then
        return nil, "glow-unsupported"
    end
    if IsGlobalTarget(target) and profile ~= self.glowProfile then return nil, "glow-unsupported" end
    local result, code
    if target.kind == "global-activation" then
        result, code = Designer:SetAuraActivationStyle({ mode = "custom", appearance = appearance })
    elseif target.kind == "global-native" then
        local current = YHUD:CopyValue(
            profile.style and profile.style.nativeProcGlow or {}
        )
        current.mode = "custom"
        current.appearance = appearance
        result, code = Designer:SetNativeProcGlow(current)
    elseif target.kind == "monitor-native" then
        local current = YHUD:CopyValue(
            monitor.nativeProcGlowOverride
                or YHUD:GetEffectiveNativeProcGlow(profile, monitor)
        )
        current.mode = "custom"
        current.appearance = appearance
        result, code = Designer:SetMonitorNativeProcGlowOverride(
            monitor.id,
            current
        )
    else
        local config = YHUD:CopyValue(monitor.glow or { rules = {} })
        local rule = config.rules and config.rules[target.ruleIndex]
        if not rule then return nil, "glow-rule-not-found" end
        rule.appearance = appearance
        result, code = Designer:SetMonitorGlow(monitor.id, config)
    end
    if result then
        self.glowPendingAppearance, self.glowSliderStart = nil, nil
        self:ApplyPreview()
        self:Refresh(false, false)
    end
    return result, code
end

function DesignerUI:CopyGlowAppearance()
    local appearance = self:GetGlowEditAppearance()
    if not appearance then return false end
    self.glowAppearanceClipboard = YHUD:NormalizeMonitorGlowAppearance(appearance)
    self:RefreshGlowLibrary()
    self.glowLibraryStatus:SetText(T("designer.glow.copied", "Appearance copied. Open another rule and paste."))
    return true
end

function DesignerUI:ApplyGlowAppearance(appearance)
    if type(appearance) ~= "table" then return false end
    -- End a pending color preview before applying a template, so its cancel
    -- callback cannot overwrite the template when the old control is hidden.
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    self.glowPendingAppearance, self.glowSliderStart = nil, nil
    local result, code = self:SetGlowEditAppearance(YHUD:NormalizeMonitorGlowAppearance(appearance))
    if result then self:RebuildGlowAppearance() end
    return result, code
end

function DesignerUI:SetGlowEditorPage(page)
    self.glowEditorPage = page
    for name, frame in pairs({ appearance = self.glowMainPage,
        save = self.glowPresetDialog, library = self.glowLibraryPanel }) do
        if name == page then frame:Show() else frame:Hide() end
    end
end

function DesignerUI:GetGlowAppearanceSummary(appearance)
    if type(appearance) ~= "table" then return "" end
    local value = YHUD:NormalizeMonitorGlowAppearance(appearance)
    local style = value.style
    local title = T("designer.glow.style." .. style, style)
    for _, option in ipairs(BuildGlowStyleOptions()) do
        if option.value == style then title = option.text; break end
    end
    if style == "none" then return T("designer.glow.style.default", "None") end
    local color = value.color
    local hex = string.format("%02X%02X%02X", math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
    local lines = { title .. " · |cff" .. hex .. "#" .. hex .. "|r" }
    if style == "pixel" then
        lines[#lines + 1] = string.format("%s %d · %s %d", T("designer.glow.lines", "Lines"), value.lines,
            T("designer.glow.thickness", "Thickness"), value.thickness)
    elseif style ~= "masque" then
        lines[#lines + 1] = string.format("%s %.2f", T("designer.glow.size", "Size"), value.size)
    end
    local opacity = string.format("%s %.0f%%", T("designer.glow.alpha", "Opacity"), value.alpha * 100)
    lines[#lines + 1] = (style == "soft" or style == "masque") and opacity
        or string.format("%s %.2f · %s", T("designer.glow.speed", "Speed"), value.speed, opacity)
    if color[4] < 1 then
        lines[#lines + 1] = string.format("%s A %.0f%%", T("designer.glow.color", "Color"), color[4] * 100)
    end
    if style ~= "masque" then
        lines[#lines + 1] = string.format("%s %.2f · %s %.2f", T("designer.glow.offset_x", "X Offset"), value.offsetX,
            T("designer.glow.offset_y", "Y Offset"), value.offsetY)
    end
    return table.concat(lines, "\n")
end

function DesignerUI:CloseGlowPresetDialog()
    if self.glowPresetDialog then
        self.glowPresetDialog.input:ClearFocus()
        self.glowPresetDialog:Hide()
        self.glowPresetDialog.appearance = nil
    end
    if self.glowEditorPage == "save" then self:SetGlowEditorPage("appearance") end
end

function DesignerUI:SaveGlowPresetFromDialog()
    local dialog = self.glowPresetDialog
    if not (dialog and dialog.appearance) then return false end
    local name, code = YHUD:SaveGlowAppearancePreset(dialog.input:GetText(), dialog.appearance)
    if not name then
        local key = code == "glow-preset-exists" and "designer.glow.preset_exists"
            or (code == "glow-preset-limit" and "designer.glow.preset_limit"
            or (code == "account-storage-unavailable" and "designer.glow.preset_unavailable"
            or "designer.glow.preset_invalid_name"))
        dialog.message:SetText(T(key, "Unable to save this appearance."))
        return false
    end
    self.glowSelectedPreset = name
    self:CloseGlowPresetDialog()
    self:RefreshGlowLibrary()
    self.glowLibraryStatus:SetText(T("designer.glow.preset_saved", "Appearance saved for all characters on this account."))
    return true
end

function DesignerUI:OpenGlowPresetDialog()
    self:FinishGlowSliderEdit()
    self:CloseGlowLibrary()
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    local appearance = self:GetGlowEditAppearance()
    if not appearance then return false end
    if not self.glowPresetDialog then
        local page = GUI2:CreateFrame(self.glowEditor, { width = 354 })
        page:SetPoint("TOPLEFT", self.glowEditor, "TOPLEFT", 18, -60)
        page:SetPoint("BOTTOMRIGHT", self.glowEditor, "BOTTOMRIGHT", -18, 16)
        page.title = GUI2:CreateText(page, T("designer.glow.preset_save_title", "Save Appearance"),
            "font.size.lg", "color.text.heading", "LEFT")
        page.title:SetPoint("TOPLEFT", 0, -4)
        page.message = GUI2:CreateText(page, "", "font.size.sm", "color.text.secondary", "LEFT")
        page.message:SetPoint("TOPLEFT", 0, -44)
        page.message:SetWidth(354)
        page.message:SetHeight(36)
        page.input = GUI2.Form:CreateEditBox(page, { width = 354, height = 28, autoFocus = false })
        page.input:SetPoint("TOPLEFT", 0, -92)
        page.input:SetMaxLetters(72)
        page.input:SetScript("OnEnterPressed", function() DesignerUI:SaveGlowPresetFromDialog() end)
        page.input:SetScript("OnEscapePressed", function() DesignerUI:CloseGlowPresetDialog() end)
        page.summary = GUI2:CreateText(page, "", "font.size.md", "color.text.secondary", "LEFT")
        page.summary:SetPoint("TOPLEFT", 0, -148)
        page.summary:SetWidth(354)
        page.summary:SetHeight(144)
        page.save = GUI2.Form:CreateButton(page, {
            text = T("designer.glow.save", "Save"), width = 171, height = 28,
            onClick = function() DesignerUI:SaveGlowPresetFromDialog() end,
        })
        page.save:SetPoint("BOTTOMLEFT", 0, 0)
        page.cancel = GUI2.Form:CreateButton(page, {
            text = T("designer.cancel", "Cancel"), width = 171, height = 28,
            onClick = function() DesignerUI:CloseGlowPresetDialog() end,
        })
        page.cancel:SetPoint("BOTTOMRIGHT", 0, 0)
        self.glowPresetDialog = page
    end
    local page = self.glowPresetDialog
    page.appearance = YHUD:NormalizeMonitorGlowAppearance(appearance)
    page.summary:SetText(self:GetGlowAppearanceSummary(page.appearance))
    page.message:SetText(T("designer.glow.preset_name_hint", "Choose a new name, such as 'High stacks red'."))
    page.input:SetText("")
    self:SetGlowEditorPage("save")
    page.input:SetFocus()
    return true
end

function DesignerUI:CloseGlowLibrary()
    if self.glowLibraryPanel then self.glowLibraryPanel:Hide() end
    if self.glowEditorPage == "library" then self:SetGlowEditorPage("appearance") end
    if S.HideConfirmPopup then S:HideConfirmPopup(self) end
end

function DesignerUI:RefreshGlowLibrary()
    if self.glowPasteButton then
        self.glowPasteButton:SetDisabled(self.glowAppearanceClipboard == nil)
    end
    if self.glowPresetDropdown then
        local presets = YHUD:GetGlowAppearancePresets()
        if not presets[self.glowSelectedPreset] then self.glowSelectedPreset = nil end
        self.glowPresetDropdown:RefreshOptions()
        self.glowPresetDropdown:SetValue(self.glowSelectedPreset or "", true)
        self.glowPresetApply:SetDisabled(self.glowSelectedPreset == nil)
        self.glowPresetDelete:SetDisabled(self.glowSelectedPreset == nil)
        self.glowPresetSummary:SetText(self:GetGlowAppearanceSummary(presets[self.glowSelectedPreset]))
    end
    if self.glowLibraryStatus then
        self.glowLibraryStatus:SetText(T("designer.glow.preset_scope",
            "Presets contain appearance only; conditions and order stay unchanged."))
    end
end

function DesignerUI:OpenGlowLibrary()
    self:FinishGlowSliderEdit()
    self:CloseGlowPresetDialog()
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    if not self:GetGlowEditAppearance() then return false end
    if not self.glowLibraryPanel then
        local panel = GUI2:CreateFrame(self.glowEditor, { width = 354 })
        panel:SetPoint("TOPLEFT", self.glowEditor, "TOPLEFT", 18, -60)
        panel:SetPoint("BOTTOMRIGHT", self.glowEditor, "BOTTOMRIGHT", -18, 16)
        local title = GUI2:CreateText(panel, T("designer.glow.presets", "My Appearances"),
            "font.size.lg", "color.text.heading", "LEFT")
        title:SetPoint("TOPLEFT", 0, -4)
        self.glowPresetDropdown = GUI2.Form:CreateDropdown(panel, {
            width = 354, height = 28,
            options = function()
                local options = { { value = "", text = T("designer.glow.preset_select", "Select an appearance") } }
                local names = {}
                for name in pairs(YHUD:GetGlowAppearancePresets()) do names[#names + 1] = name end
                table.sort(names)
                for _, name in ipairs(names) do options[#options + 1] = { value = name, text = name } end
                return options
            end,
            set = function(name)
                DesignerUI.glowSelectedPreset = YHUD:GetGlowAppearancePresets()[name] and name or nil
                DesignerUI:RefreshGlowLibrary()
            end,
        })
        self.glowPresetDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -44)
        self.glowPresetSummary = GUI2:CreateText(panel, "", "font.size.md", "color.text.primary", "LEFT")
        self.glowPresetSummary:SetPoint("TOPLEFT", 0, -88)
        self.glowPresetSummary:SetWidth(354)
        self.glowPresetSummary:SetHeight(144)
        local hint = GUI2:CreateText(panel,
            T("designer.glow.preset_apply_hint", "Select a saved appearance, then apply it to this rule."),
            "font.size.sm", "color.text.secondary", "LEFT")
        hint:SetPoint("TOPLEFT", 0, -244)
        hint:SetWidth(354)
        hint:SetHeight(44)
        self.glowPresetApply = GUI2.Form:CreateButton(panel, {
            text = T("designer.glow.preset_apply", "Apply Appearance"), width = 171, height = 28,
            onClick = function()
                local appearance = YHUD:GetGlowAppearancePresets()[DesignerUI.glowSelectedPreset]
                if appearance and DesignerUI:ApplyGlowAppearance(appearance) then DesignerUI:CloseGlowLibrary() end
            end,
        })
        self.glowPresetApply:SetPoint("BOTTOMLEFT", 0, 40)
        self.glowPresetDelete = GUI2.Form:CreateButton(panel, {
            text = T("designer.glow.preset_delete_title", "Delete Appearance"), width = 171, height = 28,
            onClick = function()
                local name = DesignerUI.glowSelectedPreset
                if not (name and YHUD:GetGlowAppearancePresets()[name]) then return end
                S:ShowConfirmPopup(
                    string.format(T("designer.glow.preset_delete_confirm", "Delete '%s'? Current glow rules stay unchanged."), name),
                    function()
                        YHUD:DeleteGlowAppearancePreset(name)
                        DesignerUI:RefreshGlowLibrary()
                    end, { owner = DesignerUI, ownerFrame = panel,
                        titleText = T("designer.glow.preset_delete_title", "Delete Appearance"),
                        acceptText = I.TC and I.TC("common.delete", "Delete") or "Delete",
                        cancelText = T("designer.cancel", "Cancel") })
            end,
        })
        self.glowPresetDelete:SetPoint("BOTTOMRIGHT", 0, 40)
        local back = GUI2.Form:CreateButton(panel, {
            text = T("designer.glow.back", "Back to Appearance"), width = 354, height = 28,
            onClick = function() DesignerUI:CloseGlowLibrary() end,
        })
        back:SetPoint("BOTTOMLEFT", 0, 0)
        self.glowLibraryPanel = panel
    end
    -- Opening the library never implies that the current draft is a saved preset.
    self.glowSelectedPreset = nil
    self:RefreshGlowLibrary()
    self:SetGlowEditorPage("library")
    return true
end

function DesignerUI:EnsureGlowLibrary()
    if self.glowLibraryButton then return end
    local parent = GUI2:CreateFrame(self.glowEditor, { width = 354 })
    parent:SetPoint("TOPLEFT", self.glowEditor, "TOPLEFT", 18, -60)
    parent:SetPoint("BOTTOMRIGHT", self.glowEditor, "BOTTOMRIGHT", -18, 16)
    self.glowMainPage = parent
    self.glowEditorPage = "appearance"
    if self.glowDone then
        self.glowDone:SetParent(parent)
        self.glowDone:ClearAllPoints()
        self.glowDone:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    end
    self.glowLibraryButton = GUI2.Form:CreateButton(parent, {
        text = T("designer.glow.presets", "My Appearances"), width = 150, height = 28,
        onClick = function() DesignerUI:OpenGlowLibrary() end,
    })
    self.glowLibraryButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local save = GUI2.Form:CreateButton(parent, {
        text = T("designer.glow.save", "Save"), width = 62, height = 28,
        tooltip = T("designer.glow.save_tooltip", "Save this appearance as a named account preset."),
        onClick = function() DesignerUI:OpenGlowPresetDialog() end,
    })
    save:SetPoint("LEFT", self.glowLibraryButton, "RIGHT", 6, 0)
    local copy = GUI2.Form:CreateButton(parent, {
        text = T("designer.glow.copy", "Copy"), width = 62, height = 28,
        onClick = function() DesignerUI:CopyGlowAppearance() end,
    })
    copy:SetPoint("LEFT", save, "RIGHT", 6, 0)
    self.glowPasteButton = GUI2.Form:CreateButton(parent, {
        text = T("designer.glow.paste", "Paste"), width = 62, height = 28,
        onClick = function() DesignerUI:ApplyGlowAppearance(DesignerUI.glowAppearanceClipboard) end,
    })
    self.glowPasteButton:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    self.glowLibraryStatus = GUI2:CreateText(parent,
        T("designer.glow.preset_scope", "Presets contain appearance only; conditions and order stay unchanged."),
        "font.size.sm", "color.text.secondary", "LEFT")
    self.glowLibraryStatus:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -36)
    self.glowLibraryStatus:SetWidth(354)
    self.glowLibraryStatus:SetHeight(30)
    self:RefreshGlowLibrary()
end

function DesignerUI:RebuildGlowAppearance()
    if not (self.glowEditor and self.glowEditor:IsShown()) then
        return false
    end
    if self.glowAppearanceControl then
        self.glowAppearanceControl:Hide()
    end
    if self.glowAppearanceHost then self.glowAppearanceHost:Hide() end
    local appearance = self:GetGlowEditAppearance()
    if not appearance then
        self:HideGlowEditor()
        return false
    end

    self:EnsureGlowLibrary()

    self.glowAppearanceCache = self.glowAppearanceCache or {}
    local key = appearance.style .. ":" .. tostring(self.glowAppearanceExpanded == true)
    local cached = self.glowAppearanceCache[key]
    if cached then
        cached.control:SetValue(appearance, true)
        GUI2.Form:RefreshRetainedValues(cached.host, cached.fields)
        cached.host:Show()
        cached.control:Show()
        self.glowAppearanceHost, self.glowAppearanceControl = cached.host, cached.control
        self.glowEditor:SetHeight(math.max(480, 136 + cached.host:GetHeight() + 70))
        return true
    end
    local host = GUI2:CreateFrame(self.glowMainPage, { width = 354 })
    host:SetPoint("TOPLEFT", self.glowMainPage, "TOPLEFT", 0, -76)
    host.yuiRetainedBindings = {}
    local default = YHUD:GetDefaultMonitorGlowAppearance()
    local hint
    if appearance.style == "masque" or appearance.style == "pixel" then
        hint = GUI2:CreateText(host, T("designer.glow.hint." .. appearance.style, ""),
            "font.size.sm", "color.text.secondary", "LEFT")
        hint:SetWidth(354)
        hint:SetHeight(64)
    end
    local control = GUI2.Form:CreateGlowOptions(host, {
        width = 354,
        panelWidth = 354,
        styleOptions = function()
            local options = BuildGlowStyleOptions()
            if DesignerUI.glowEditTarget and DesignerUI.glowEditTarget.kind == "global-activation" then
                local filtered = {}
                for _, option in ipairs(options) do
                    if option.value ~= "none" then filtered[#filtered + 1] = option end
                end
                return filtered
            end
            return options
        end,
        labels = BuildGlowControlLabels(),
        default = default,
        applyStyleDefaultsOnChange = true,
        get = function()
            return DesignerUI:GetGlowEditAppearance() or default
        end,
        set = function(value)
            DesignerUI:SetGlowEditAppearance(value)
        end,
        getExpanded = function()
            return DesignerUI.glowAppearanceExpanded == true
        end,
        setExpanded = function(value)
            DesignerUI.glowAppearanceExpanded = value == true
        end,
        onRequestRefresh = function()
            DesignerUI:RebuildGlowAppearance()
        end,
    })
    control:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    host:SetHeight(control:GetHeight())
    if hint then
        hint:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -10)
        host:SetHeight(control:GetHeight() + 74)
    end
    local fields = {}
    for index, binding in ipairs(host.yuiRetainedBindings) do
        local field = binding.opts
        if field.min ~= nil and field.max ~= nil and field.set then
            local set = field.set
            field.set = function(value)
                DesignerUI.glowSliderPreviewing = true
                set(value)
                DesignerUI.glowSliderPreviewing = nil
            end
            field.onCommit = function() DesignerUI:FinishGlowSliderEdit() end
        end
        fields[index] = field
    end
    self.glowAppearanceCache[key] = { host = host, control = control, fields = fields }
    self.glowEditor:SetHeight(math.max(480, 136 + host:GetHeight() + 70))
    self.glowAppearanceHost, self.glowAppearanceControl = host, control
    return true
end

function DesignerUI:PositionGlowEditor()
    if not (self.glowEditor and self.glowEditor:IsShown()) then
        return false
    end
    self.glowEditor:ClearAllPoints()
    if self.inspectorSide == "left" then
        self.glowEditor:SetPoint(
            "TOPLEFT",
            self.panel,
            "TOPRIGHT",
            12,
            0
        )
    else
        self.glowEditor:SetPoint(
            "TOPRIGHT",
            self.panel,
            "TOPLEFT",
            -12,
            0
        )
    end
    return true
end

function DesignerUI:RefreshGlowEditor(rebuildAppearance)
    if not (self.glowEditor and self.glowEditor:IsShown()) then
        return false
    end
    local monitor, profile = self:GetSelectedGlowMonitor()
    if IsGlobalTarget(self.glowEditTarget) and profile ~= self.glowProfile then
        self:HideGlowEditor()
        return false
    end
    if not IsGlobalTarget(self.glowEditTarget) and (not monitor or monitor.id ~= self.glowMonitorId) then
        self:HideGlowEditor()
        return false
    end
    if self.glowEditTarget then
        if self.glowEditorPage ~= "appearance" then
            self:SyncGlowAppearancePreview()
            return true
        end
        if rebuildAppearance ~= false or not self.glowAppearanceControl then
            self:RebuildGlowAppearance()
        elseif self.glowAppearanceControl.SetValue then
            self.glowAppearanceControl:SetValue(
                self:GetGlowEditAppearance(),
                true
            )
        end
        self:PositionGlowEditor()
        self:RefreshGlowRuleHighlight()
        self:SyncGlowAppearancePreview()
        return true
    end
    local config = self:GetSelectedMonitorGlow()
    self.glowTitle:SetText(string.format(
        T("designer.glow.title_monitor", "%s · 发光"),
        MonitorName(profile, monitor)
    ))
    local rule = config.rules and config.rules[1]
    self.glowEnabledSwitch:SetValue(rule ~= nil, true)
    local condition = rule and rule.condition
    self.glowTriggerDropdown:SetValue(
        condition and condition.type or "self-ready",
        true
    )
    self.glowCombatSwitch:SetValue(rule and rule.combatOnly == true, true)
    if rebuildAppearance ~= false or not self.glowAppearanceControl then
        self:RebuildGlowAppearance()
    elseif self.glowAppearanceControl.SetValue then
        self.glowAppearanceControl:SetValue(
            rule and rule.appearance
                or YHUD:GetDefaultMonitorGlowAppearance(),
            true
        )
    end
    self:PositionGlowEditor()
    return true
end

function DesignerUI:OpenGlowEditor()
    local monitor = self:GetSelectedGlowMonitor()
    if not monitor then
        self:SetStatus(T(
            "designer.glow.unsupported",
            "该监控当前不支持稳定的发光条件。"
        ))
        return nil, "glow-unsupported"
    end
    local ruleIndex = monitor.glow and monitor.glow.rules
        and monitor.glow.rules[1] and 1 or nil
    if not ruleIndex then return nil, "glow-rule-not-found" end
    return self:OpenGlowAppearanceEditor("rule", ruleIndex)
end

function DesignerUI:OpenGlowAppearanceEditor(kind, ruleIndex)
    self:FinishGlowSliderEdit()
    self:CloseGlowLibrary()
    local monitor = self:GetSelectedGlowMonitor()
    if not monitor and kind ~= "global-activation" and kind ~= "global-native" then
        return nil, "glow-unsupported"
    end
    if not Designer:GetProfile() then return nil, "glow-unsupported" end
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    self:HideMonitorPicker()
    self:CloseGlowPresetDialog()
    self.glowSelectedPreset = nil
    if self.glowLibraryStatus then
        self.glowLibraryStatus:SetText(T("designer.glow.preset_scope",
            "Presets contain appearance only; conditions and order stay unchanged."))
    end
    self.glowMonitorId = monitor and monitor.id
    self.glowProfile = Designer:GetProfile()
    self.glowEditTarget = {
        kind = kind,
        ruleIndex = ruleIndex,
    }
    self.glowAppearanceExpanded = true
    for _, control in pairs({
        self.glowEnabledLabel,
        self.glowEnabledSwitch,
        self.glowTriggerLabel,
        self.glowTriggerDropdown,
        self.glowCombatLabel,
        self.glowCombatSwitch,
        self.glowAppearanceLabel,
    }) do
        if control then control:Hide() end
    end
    local titleKey = kind == "global-activation" and "designer.glow.title_global_activation" or kind == "global-native"
        and "designer.glow.title_global_native"
        or (kind == "monitor-native"
            and "designer.glow.title_monitor_native"
            or "designer.glow.title_rule")
    local fallback = kind == "global-activation" and "全局效果激活提示 · 外观" or kind == "global-native"
        and "全局原生触发发光 · 外观"
        or (kind == "monitor-native"
            and "单项原生触发发光 · 外观"
            or "自定义发光条件 %d · 外观")
    self.glowTitle:SetText(ruleIndex
        and string.format(T(titleKey, fallback), ruleIndex)
        or T(titleKey, fallback))
    self.glowEditor:Show()
    self:RefreshGlowRuleHighlight()
    self:SetGlowEditorPage("appearance")
    self:RebuildGlowAppearance()
    self:SyncGlowAppearancePreview()
    self:PositionGlowEditor()
    if GUI2.FadeIn then
        GUI2:FadeIn(self.glowEditor, {
            from = 0.82,
            to = 1,
            duration = 0.12,
            owner = self,
        })
    end
    return true
end

function DesignerUI:HideGlowEditor()
    self:FinishGlowSliderEdit()
    self:CloseGlowLibrary()
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    self:CloseGlowPresetDialog()
    if S.HideConfirmPopup then S:HideConfirmPopup(self) end
    if self.glowEditor then self.glowEditor:Hide() end
    if self.glowAppearanceControl then
        self.glowAppearanceControl:Hide()
    end
    if self.glowAppearanceHost then self.glowAppearanceHost:Hide() end
    self.glowAppearanceControl = nil
    self.glowMonitorId = nil
    self.glowProfile = nil
    self.glowEditTarget = nil
    self.glowAppearanceExpanded = false
    if YHUD.View and YHUD.View.SetDesignGlowPreview then YHUD.View:SetDesignGlowPreview(nil, nil, nil) end
    self:RefreshGlowRuleHighlight()
end

function DesignerUI:RefreshGlowRuleHighlight()
    if not GUI2.SetBorderColor then return end
    local target = self.glowEditor and self.glowEditor:IsShown() and self.glowEditTarget
    for _, row in ipairs(self.monitorGlowRules or {}) do
        local editing = target and target.kind == "rule" and target.ruleIndex == row.index
            and row.stackMonitorId == self.glowMonitorId
        GUI2:SetBorderColor(row, editing and "color.border.focus" or "color.border.default")
    end
end

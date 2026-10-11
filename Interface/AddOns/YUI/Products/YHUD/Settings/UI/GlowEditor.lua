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

function DesignerUI:GetSelectedGlowMonitor()
    local profile = Designer:GetProfile()
    local monitor = Designer:GetSelectedMonitor()
    if not (profile and monitor and Glow and Glow.SupportsMonitor
        and Glow:SupportsMonitor(profile, monitor)) then
        return nil, profile
    end
    return monitor, profile
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
    if not (target and profile) then return nil end
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

function DesignerUI:SetGlowEditAppearance(appearance)
    local target = self.glowEditTarget
    local monitor, profile = self:GetSelectedGlowMonitor()
    if not (target and monitor and profile) then
        return nil, "glow-unsupported"
    end
    local result, code
    if target.kind == "global-native" then
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
        self:ApplyPreview()
        self:Refresh(false, false)
    end
    return result, code
end

function DesignerUI:RebuildGlowAppearance()
    if not (self.glowEditor and self.glowEditor:IsShown()) then
        return false
    end
    if self.glowAppearanceControl then
        self.glowAppearanceControl:Hide()
    end
    local appearance = self:GetGlowEditAppearance()
    if not appearance then
        self:HideGlowEditor()
        return false
    end

    local default = YHUD:GetDefaultMonitorGlowAppearance()
    local control = GUI2.Form:CreateGlowOptions(self.glowEditor, {
        width = 354,
        panelWidth = 354,
        styleOptions = BuildGlowStyleOptions,
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
    control:SetPoint("TOPLEFT", self.glowEditor, "TOPLEFT", 18, -72)
    self.glowAppearanceControl = control
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
    if not monitor or monitor.id ~= self.glowMonitorId then
        self:HideGlowEditor()
        return false
    end
    if self.glowEditTarget then
        if rebuildAppearance ~= false or not self.glowAppearanceControl then
            self:RebuildGlowAppearance()
        elseif self.glowAppearanceControl.SetValue then
            self.glowAppearanceControl:SetValue(
                self:GetGlowEditAppearance(),
                true
            )
        end
        self:PositionGlowEditor()
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
    local monitor = self:GetSelectedGlowMonitor()
    if not monitor then return nil, "glow-unsupported" end
    self:HideMonitorPicker()
    self.glowMonitorId = monitor.id
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
    local titleKey = kind == "global-native"
        and "designer.glow.title_global_native"
        or (kind == "monitor-native"
            and "designer.glow.title_monitor_native"
            or "designer.glow.title_rule")
    local fallback = kind == "global-native"
        and "全局原生触发发光 · 外观"
        or (kind == "monitor-native"
            and "单项原生触发发光 · 外观"
            or "自定义发光条件 %d · 外观")
    self.glowTitle:SetText(ruleIndex
        and string.format(T(titleKey, fallback), ruleIndex)
        or T(titleKey, fallback))
    self.glowEditor:Show()
    self:RebuildGlowAppearance()
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
    if self.glowEditor then self.glowEditor:Hide() end
    if self.glowAppearanceControl then
        self.glowAppearanceControl:Hide()
    end
    self.glowAppearanceControl = nil
    self.glowMonitorId = nil
    self.glowEditTarget = nil
    self.glowAppearanceExpanded = false
end

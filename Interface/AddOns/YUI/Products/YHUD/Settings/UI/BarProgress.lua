local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local UI = YHUD and YHUD.DesignerUI
local I = UI and UI._internal
local GUI2 = YUI and YUI.GUI2
if not (I and GUI2 and GUI2.Form) then return end
local Designer = YHUD.Designer
local function T(key, fallback) return YHUD:T(key, fallback) end
local function Place(control, parent, x, y, width)
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if width then control:SetWidth(width) end
    control:Show()
end
local function Keep(list, control)
    list[#list + 1] = control
    control:Hide()
    return control
end
local function Label(list, body, key, fallback)
    return Keep(list, GUI2:CreateText(body, T(key, fallback), "font.size.md", "color.text.primary", "LEFT"))
end
local function Option(value, key, fallback) return { value = value, text = T(key, fallback) } end
local function Selected()
    local session, profile = Designer:GetSession(), Designer:GetProfile()
    local monitor = session and profile and profile.monitors[session.selectedMonitorId]
    return monitor, profile
end
local function CanSelectCharges(entry, monitor)
    if not YHUD:CanUseBarChargeProgress(entry, monitor) then return false end
    local saved = monitor.appearanceOverride and monitor.appearanceOverride.barProgress
    if saved and saved.source == "spell-charges" then
        return true
    end
    local spellID = monitor._yhudRuntimeSpellID or entry.overrideSpellId or entry.spellId
        or entry.spellID or entry.sourceParams and entry.sourceParams.spellID
    local spell = YUI.API and YUI.API.Spell
    local state = spell and spell.ReadChargeResourceDisplay and spell.ReadChargeResourceDisplay(spellID, {})
    local maximum = state and state.maxValue
    local supported = state and state.available and not (_G.issecretvalue and _G.issecretvalue(maximum))
        and type(maximum) == "number" and maximum > 1 and maximum <= 100
    if state then state.valueRaw, state.rechargeDurationRaw = nil, nil end
    return supported == true
end

local function TimeDescription(entry, monitor)
    if entry and entry.sourceType == "class-extra-monitor" and entry.presetId == "devourer-transform" then
        return T("designer.bar.transform_elapsed", "变身已持续时间"),
            T("designer.bar.transform_elapsed_hint", "从变身开始累计，达到提醒秒数时满条；具体逻辑见上方预设说明。")
    elseif entry and entry.sourceType == YHUD.PLAYER_AURA_SOURCE_TYPE then
        return T("designer.bar.aura_duration", "光环持续时间"),
            T("designer.bar.aura_duration_hint", "显示光环剩余持续时间，随时间减少；光环结束时归零。")
    elseif CanSelectCharges(entry, monitor) then
        return T("designer.bar.charge_duration", "单次充能恢复时间"),
            T("designer.bar.charge_duration_hint", "显示下一次充能的剩余恢复时间，随时间减少；要累计可用次数和恢复进度，请选择技能充能。")
    elseif entry and (entry.sourceType == "spell-cooldown" or entry.origin == "official-cdm"
        or entry.sourceType == "class-extra-monitor" and entry.presetId == "brewmaster-elixir") then
        return T("designer.bar.cooldown_duration", "技能冷却时间"),
            T("designer.bar.cooldown_duration_hint", "显示技能剩余冷却时间，随时间减少；技能就绪时归零。")
    elseif entry and (entry.sourceType == "item-cooldown" or entry.sourceType == "slot-cooldown") then
        return T("designer.bar.item_duration", "物品冷却时间"),
            T("designer.bar.cooldown_duration_hint", "显示技能剩余冷却时间，随时间减少；技能就绪时归零。")
    end
    return T("designer.bar.effect_duration", "效果持续时间"),
        T("designer.bar.effect_duration_hint", "显示当前监控效果或触发窗口的剩余时间，随时间减少；效果结束时归零。")
end

function I.BuildBarProgressUI(self, width, callbacks)
    if self.barProgressUI then return end
    local controls, ui, body = {}, {}, self.monitorInspectorBody
    self.monitorBarProgressControls, self.barProgressUI = controls, ui
    local function Set(field, value, control, preview)
        if self.v2Refreshing then return end
        local monitor, profile = Selected()
        local id = control and callbacks.resolveTarget(control) or monitor and monitor.id
        monitor = profile and profile.monitors[id]
        if not monitor then return end
        local progress = YHUD:NormalizeBarProgress(monitor.appearanceOverride and monitor.appearanceOverride.barProgress)
        if control and control._barProgressSource
            and (control._barProgressSource ~= progress.source or control._barProgressProfile ~= profile) then return end
        if field == "source" then
            local entry = profile.entries[monitor.entryKey]
            if value ~= "time" and not (value == "aura-stacks" and YHUD:CanUseBarAuraProgress(entry, monitor))
                and not (value == "spell-charges" and CanSelectCharges(entry, monitor)) then return end
            progress = YHUD:SwitchBarProgressSource(progress, value)
            ui.positions._barProgressTarget = nil
            ui.positions:ClearFocus()
        elseif field == "maximumMode" or field == "maximum" then
            if progress.source ~= "aura-stacks" then return end
            progress[field] = value
        elseif field:sub(1, 6) == "ticks." then
            if field == "ticks.mode" and not YHUD:IsBarTickModeAllowed(progress.source, value) then return end
            if field == "ticks.step" and progress.ticks.mode ~= "aura-stacks" then return end
            if field == "ticks.positions" and progress.ticks.mode ~= "custom" then return end
            progress.ticks[field:sub(7)] = value
        else return end
        local appearance = Designer:SetMonitorAppearanceOverride(id, { barProgress = progress })
        if appearance then
            if preview then callbacks.reapply(id, appearance)
            else callbacks.finish(control, id, appearance) end
        end
    end
    local function Dropdown(field, options)
        return Keep(controls, GUI2.Form:CreateDropdown(body, {
            width = width - 112, options = options,
            set = function(value) Set(field, value) end,
        }))
    end
    local function Slider(field, minimum, maximum)
        local control
        control = Keep(controls, GUI2.Form:CreateSlider(body, {
            width = width - 112, min = minimum, max = maximum, step = 1, precision = 0,
            inline = true, inputWidth = 44,
            set = function(value) Set(field, value, nil, true) end,
            onCommit = function() self:Refresh(false, false) end,
        }))
        return control
    end
    ui.heading = Label(controls, body, "designer.bar.progress", "进度")
    ui.sourceLabel = Label(controls, body, "designer.bar.source", "进度来源")
    ui.source = Dropdown("source", function()
        local monitor, profile = Selected()
        local entry = monitor and profile.entries[monitor.entryKey]
        local options = { { value = "time", text = TimeDescription(entry, monitor) } }
        if YHUD:CanUseBarAuraProgress(entry, monitor) then
            options[#options + 1] = Option("aura-stacks", "designer.bar.aura_stacks", "光环层数")
        elseif CanSelectCharges(entry, monitor) then
            options[#options + 1] = Option("spell-charges", "designer.bar.spell_charges", "技能充能（含恢复进度）")
        end
        return options
    end)
    ui.sourceHint = Keep(controls, GUI2:CreateText(body, "", "font.size.sm", "color.text.secondary", "LEFT"))
    ui.sourceHint:SetWordWrap(true)
    ui.maximumLabel = Label(controls, body, "designer.bar.maximum_mode", "满条层数")
    ui.maximumMode = Dropdown("maximumMode", {
        Option("auto", "designer.bar.maximum_auto", "自动识别"),
        Option("custom", "designer.bar.maximum_custom", "手动设置"),
    })
    ui.maximumValueLabel = Label(controls, body, "designer.bar.maximum", "最大层数")
    ui.maximum = Slider("maximum", 1, 100)
    ui.status = Keep(controls, GUI2:CreateText(body, "", "font.size.sm", "color.text.secondary", "LEFT"))
    ui.status:SetWordWrap(true)
    ui.tickLabel = Label(controls, body, "designer.bar.ticks", "刻度线")
    ui.ticks = Dropdown("ticks.mode", function()
        local monitor = Selected()
        local progress = YHUD:NormalizeBarProgress(monitor and monitor.appearanceOverride and monitor.appearanceOverride.barProgress)
        local options = { Option("off", "designer.bar.ticks_off", "关闭") }
        if progress.source == "aura-stacks" then
            options[#options + 1] = Option("aura-stacks", "designer.bar.ticks_stacks", "按光环层数")
        elseif progress.source == "spell-charges" then
            options[#options + 1] = Option("spell-charges", "designer.bar.ticks_charges", "按充能次数")
        end
        options[#options + 1] = Option("custom", "designer.bar.ticks_custom", "自定义百分比")
        return options
    end)
    ui.stepLabel = Label(controls, body, "designer.bar.tick_step", "每隔层数")
    ui.step = Slider("ticks.step", 1, 100)
    ui.positionsLabel = Label(controls, body, "designer.bar.positions", "位置（%）")
    ui.positions = Keep(controls, GUI2.Form:CreateEditBox(body, {
        width = width - 112, autoFocus = false,
        tooltip = T("designer.bar.positions_hint", "填写 0 到 100 之间的百分比，用逗号分隔；最多 32 个位置。"),
        onFocusGained = function(control)
            local monitor, profile = Selected()
            control._barProgressTarget, control._barProgressProfile = monitor and monitor.id, profile
            control._barProgressSource = YHUD:NormalizeBarProgress(monitor and monitor.appearanceOverride
                and monitor.appearanceOverride.barProgress).source
        end,
        onFocusLost = function(control)
            local id, profile, source = control._barProgressTarget, control._barProgressProfile, control._barProgressSource
            control._barProgressTarget, control._barProgressProfile, control._barProgressSource = nil, nil, nil
            local selected = Selected()
            if not id or not selected or selected.id ~= id or profile ~= Designer:GetProfile() then return end
            local progress = YHUD:NormalizeBarProgress(selected.appearanceOverride and selected.appearanceOverride.barProgress)
            if progress.source ~= source or progress.ticks.mode ~= "custom" then return end
            local positions, valid = {}, true
            for part in control:GetText():gsub("，", ","):gmatch("[^,%s]+") do
                local value = tonumber(part)
                if not value or value ~= value or value <= 0 or value >= 100 or #positions >= 32 then
                    valid = false; break
                end
                positions[#positions + 1] = value
            end
            if valid then Set("ticks.positions", positions) else
                control:SetValue(table.concat(progress.ticks.positions, ", "), true)
            end
        end,
    }))
    ui.positions:SetScript("OnEnterPressed", function(control) control:ClearFocus() end)
    ui.positions:SetScript("OnEscapePressed", function(control)
        control._barProgressTarget = nil
        control:ClearFocus()
        self:Refresh(false, false)
    end)
    ui.thicknessLabel = Label(controls, body, "designer.bar.tick_thickness", "刻度粗细")
    ui.thickness = Slider("ticks.thickness", 1, 8)
    ui.colorLabel = Label(controls, body, "designer.bar.tick_color", "刻度颜色")
    ui.color = Keep(controls, GUI2.Form:CreateColorPicker(body, {
        width = 44, field = true, hasAlpha = true,
        commit = function(value, control) Set("ticks.color", value, control) end,
    }))
    callbacks.bindTarget(ui.color)
    if ui.color.HookScript then
        ui.color:HookScript("OnClick", function(control)
            local monitor, profile = Selected()
            control._yhudMonitorAppearanceTarget = monitor and monitor.id
            control._barProgressProfile = profile
            control._barProgressSource = YHUD:NormalizeBarProgress(monitor and monitor.appearanceOverride
                and monitor.appearanceOverride.barProgress).source
        end)
    end
    local function RechargeTarget(control)
        local _, profile = Selected()
        local id = callbacks.resolveTarget(control)
        local monitor = profile and profile.monitors[id]
        if not monitor or control and control._barRechargeProfile and control._barRechargeProfile ~= profile
            or not (monitor.appearanceOverride and monitor.appearanceOverride.barProgress
                and monitor.appearanceOverride.barProgress.source == "spell-charges") then return end
        return id
    end
    ui.rechargeLabel = Label(controls, body, "designer.bar.recharge_color", "恢复段颜色")
    ui.rechargeColor = Keep(controls, GUI2.Form:CreateColorPicker(body, {
        width = 84, field = true, hasAlpha = true,
        tooltip = T("designer.bar.recharge_color_hint", "默认跟随当前填充色，不透明度减半；自定义后独立于阈值变色。"),
        preview = function(value, control)
            local id = RechargeTarget(control)
            if id and YHUD.View and YHUD.View.PreviewMonitorColor then
                YHUD.View:PreviewMonitorColor(id, "rechargeColor", value)
            end
        end,
        commit = function(value, control)
            if self.v2Refreshing then return end
            local id = RechargeTarget(control)
            if not id then return end
            local appearance = Designer:SetMonitorAppearanceOverride(id, { rechargeColor = value })
            if appearance then callbacks.finish(control, id, appearance) end
        end,
        cancel = function(_, control)
            local id = RechargeTarget(control)
            if id then callbacks.finish(control, id) end
        end,
    }))
    callbacks.bindTarget(ui.rechargeColor)
    ui.rechargeColor:HookScript("OnClick", function(control)
        local monitor, profile = Selected()
        control._yhudMonitorAppearanceTarget = monitor and monitor.id
        control._barRechargeProfile = profile
    end)
    ui.rechargeFollow = Keep(controls, GUI2.Form:CreateButton(body, {
        text = T("designer.bar.recharge_follow", "跟随填充"),
        onClick = function()
            if self.v2Refreshing then return end
            local id = RechargeTarget()
            if not id then return end
            local appearance = Designer:SetMonitorAppearanceOverride(id, { rechargeColor = false })
            if appearance then callbacks.finish(nil, id, appearance) end
        end,
    }))
end

function I.PlaceBarRechargeAppearanceUI(self, monitor, style, top, width)
    local ui = self.barProgressUI
    if not ui then return top end
    ui.rechargeLabel:Hide(); ui.rechargeColor:Hide(); ui.rechargeFollow:Hide()
    local appearance = monitor.appearanceOverride or {}
    local progress = appearance.barProgress
    if monitor.view ~= "bar" or not progress or progress.source ~= "spell-charges" then return top end
    local color = appearance.rechargeColor or appearance.fillColor or style.fillColor
    local alpha = (color.a or color[4] or 1) * (appearance.rechargeColor and 1 or .5)
    Place(ui.rechargeLabel, self.monitorInspectorBody, 0, top + 5, 104)
    Place(ui.rechargeColor, self.monitorInspectorBody, 112, top, 84)
    Place(ui.rechargeFollow, self.monitorInspectorBody, 204, top, width - 204)
    ui.rechargeColor:SetValue({ color.r or color[1], color.g or color[2], color.b or color[3], alpha }, true)
    ui.rechargeFollow:SetDisabled(appearance.rechargeColor == nil)
    return top + 36
end

function I.PlaceBarProgressUI(self, group, monitor, top, width)
    for _, control in ipairs(self.monitorBarProgressControls or {}) do control:Hide() end
    if not (group and group.layout == "bars" and monitor and self.barProgressUI) then return top end
    local ui, body = self.barProgressUI, self.monitorInspectorBody
    local profile = Designer:GetProfile()
    local entry = profile.entries[monitor.entryKey]
    local progress = YHUD:NormalizeBarProgress(monitor.appearanceOverride and monitor.appearanceOverride.barProgress)
    Place(ui.heading, body, 0, top, width)
    top = top + 28
    local function Row(label, control, value, dynamic)
        Place(label, body, 0, top + 5, 104)
        Place(control, body, 112, top, width - 112)
        control:SetValue(value, dynamic and { silent = true, force = true } or true)
        top = top + 36
    end
    Row(ui.sourceLabel, ui.source, progress.source, true)
    if progress.source ~= "aura-stacks" then
        local _, hint = TimeDescription(entry, monitor)
        if progress.source == "spell-charges" then
            hint = T("designer.bar.charges_hint", "显示可用充能次数＋下一次恢复进度，随恢复增加；全部充能可用时满条。阈值变色按可用次数判断。")
        end
        ui.sourceHint:SetText(hint)
        Place(ui.sourceHint, body, 0, top, width)
        top = top + (ui.sourceHint.GetStringHeight and math.max(22, math.ceil(ui.sourceHint:GetStringHeight())) or 30) + 8
    end
    if progress.source == "aura-stacks" then
        Row(ui.maximumLabel, ui.maximumMode, progress.maximumMode)
        if progress.maximumMode == "custom" then Row(ui.maximumValueLabel, ui.maximum, progress.maximum) end
    end
    if progress.source == "spell-charges" or progress.source == "aura-stacks" and progress.maximumMode == "auto" then
        local maximum = YHUD.View and YHUD.View.ReadBarProgressMaximum
            and YHUD.View:ReadBarProgressMaximum(entry, monitor, progress)
        GUI2:SetTextColorKey(ui.status, maximum and "color.text.secondary" or "color.state.danger")
        if progress.source == "spell-charges" then
            ui.status:SetText(maximum and string.format(T("designer.bar.charge_maximum", "最大充能：%d 次（技能实际值）"), maximum)
                or T("designer.bar.charge_unavailable", "充能信息暂不可用"))
        else
            ui.status:SetText(maximum and string.format(T("designer.bar.resolved_maximum", "当前识别：%d 层"), maximum)
                or T("designer.bar.maximum_unavailable", "未识别到层数上限，请改用手动设置。"))
        end
        Place(ui.status, body, 0, top, width)
        local height = ui.status.GetStringHeight and math.max(22, math.ceil(ui.status:GetStringHeight())) or 30
        ui.status:SetHeight(height)
        top = top + height + 4
    end
    Row(ui.tickLabel, ui.ticks, progress.ticks.mode, true)
    if progress.ticks.mode == "aura-stacks" then Row(ui.stepLabel, ui.step, progress.ticks.step)
    elseif progress.ticks.mode == "custom" then Row(ui.positionsLabel, ui.positions, table.concat(progress.ticks.positions, ", ")) end
    if progress.ticks.mode ~= "off" then
        Row(ui.thicknessLabel, ui.thickness, progress.ticks.thickness)
        Place(ui.colorLabel, body, 0, top + 5, 104)
        Place(ui.color, body, 112, top, 44)
        ui.color:SetValue(progress.ticks.color, true)
        top = top + 36
    end
    return top
end

function I.GetBarThresholdInfo(entry, monitor, policy)
    local progress = YHUD:NormalizeBarProgress(monitor.appearanceOverride and monitor.appearanceOverride.barProgress)
    local charges = progress.source == "spell-charges"
    local basis = charges and T("designer.bar.threshold_charges", "按可用充能数变色")
        or T("designer.bar.threshold_stacks", "按光环层数变色")
    local unit = charges and T("designer.bar.threshold_charge_unit", "可用次数")
        or T("designer.bar.threshold_stack_unit", "层数")
    local warning
    if YHUD:BarStackThresholdsOverlap(policy) then
        warning = T("designer.bar.threshold_overlap", "低阈值必须小于高阈值。")
    elseif policy.enabled and progress.source ~= "time" then
        local maximum = YHUD.View and YHUD.View.ReadBarProgressMaximum
            and YHUD.View:ReadBarProgressMaximum(entry, monitor, progress)
        if maximum and (policy.low.enabled and policy.low.value > maximum
            or policy.high.enabled and policy.high.value > maximum) then
            warning = T("designer.bar.threshold_out_of_range", "部分阈值超过当前上限，请检查；已保留原值。")
        end
    end
    return basis, unit, warning
end

function I.BuildBarWidthUI(self, width)
    if self.barWidthUI then return end
    local controls, ui, body = {}, {}, self.groupInspectorBody
    self.barWidthControls, self.barWidthUI = controls, ui
    local function Set(field, value)
        if self.v2Refreshing then return end
        if self:ApplyV2SliderPatch("durationLayout", field, value) then self:Refresh(false, false) end
    end
    ui.modeLabel = Label(controls, body, "designer.resource.width_mode", "宽度模式")
    ui.mode = Keep(controls, GUI2.Form:CreateDropdown(body, {
        width = width, options = {
            Option("fixed", "designer.bar.width_fixed", "手动宽度"),
            Option("auto", "designer.bar.width_auto", "对齐分组"),
        }, set = function(value) Set("widthMode", value) end,
    }))
    ui.targetLabel = Label(controls, body, "designer.bar.width_target", "对齐目标")
    ui.target = Keep(controls, GUI2.Form:CreateDropdown(body, {
        width = width, options = function()
            local profile, session = Designer:GetProfile(), Designer:GetSession()
            local options = {}
            for _, id in ipairs(profile.groups.order) do
                local group = profile.groups.items[id]
                if group and YHUD:CanAlignBarWidth(profile, session.selectedGroupId, id) then
                    options[#options + 1] = { value = id, text = I.GroupName(group) }
                end
            end
            return options
        end, set = function(value) Set("widthGroupId", value) end,
    }))
end

function I.PlaceBarWidthUI(self, group, layout, width, columnX)
    for _, control in ipairs(self.barWidthControls or {}) do control:Hide() end
    if group.layout ~= "bars" or layout.orientation == "vertical" then return end
    local ui, body = self.barWidthUI, self.groupInspectorBody
    Place(ui.modeLabel, body, 0, 440, width)
    Place(ui.mode, body, 0, 460, width)
    ui.mode:SetValue(layout.widthMode, true)
    if layout.widthMode == "auto" then
        Place(ui.targetLabel, body, columnX, 440, width)
        Place(ui.target, body, columnX, 460, width)
        ui.target:SetValue(layout.widthGroupId, { silent = true, force = true })
        ui.target:SetDisabled(false)
    end
end

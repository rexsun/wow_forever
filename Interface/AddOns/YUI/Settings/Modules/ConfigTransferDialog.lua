local ADDON_NAME, YUI = ...
if not YUI or not YUI.Settings or not YUI.GUI2 then return end

local S = YUI.Settings
local GUI2 = YUI.GUI2
local Transfer = S.ConfigTransfer
local L = YUI.Locale and YUI.Locale:Get("Core") or {}
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API
local FRAME_WIDTH = 720
local FRAME_HEIGHT = 560
local FRAME_LEVEL = 700
local CONTENT_MARGIN = 22
local CONTENT_WIDTH = FRAME_WIDTH - (CONTENT_MARGIN * 2)
local MODULE_INSET = 12
local SCROLL_WIDTH = CONTENT_WIDTH - (MODULE_INSET * 2)
local SCROLL_CHILD_WIDTH = SCROLL_WIDTH - 10
local PASTE_INPUT_CAP_BYTES = 2048
local GetDialogProfileName
local ShowImportReloadPrompt
local ShowImportCompletePrompt
local RefreshPersonalDataOption
local SetParseBusy
local CancelImport
local Trim

local function T(key, fallback, ...)
    local value = L[key]
    if type(value) ~= "string" or value == "" or value == key then
        value = fallback or key
    end
    if select("#", ...) == 0 then return value end
    local ok, formatted = pcall(string.format, value, ...)
    return ok and formatted or value
end

local function CreateButton(parent, text, width, onClick, tone)
    return GUI2.Form:CreateButton(parent, {
        text = text,
        width = width,
        height = 26,
        tone = tone or "default",
        onClick = onClick,
    })
end

local function TraceNowMS()
    if debugprofilestop then return debugprofilestop() end
    if GetTime then return GetTime() * 1000 end
    return 0
end

local function AttachImportPasteCapture(editBox, callbacks)
    callbacks = type(callbacks) == "table" and callbacks or {}
    editBox:SetMaxLetters(0)
    editBox:SetMaxBytes(PASTE_INPUT_CAP_BYTES)

    local parts = {}
    local partCount = 0
    local byteCount = 0
    local active = false
    local generation = 0
    local settleTimer
    local traceRecord
    local startedAt

    local function ClearParts()
        for index = 1, partCount do parts[index] = nil end
        partCount = 0
        byteCount = 0
    end

    local function BeginTrace()
        if traceRecord then return end
        local Trace = YUI.Trace
        if Trace and Trace.Begin then
            traceRecord = Trace:Begin(
                "Settings",
                "ConfigTransfer:paste-capture",
                nil,
                { durationKind = "async", blocking = false }
            )
            if traceRecord and startedAt then traceRecord.start = startedAt end
        end
    end

    local function FinishTrace(status, code, characters, captured)
        local Trace = YUI.Trace
        if traceRecord and Trace and Trace.Finish then
            Trace:Finish(
                traceRecord,
                status,
                code,
                string.format(
                    "characters=%d; captured=%s",
                    tonumber(characters) or 0,
                    captured and "true" or "false"
                )
            )
        end
        traceRecord = nil
        startedAt = nil
    end

    local function Finalize(expectedGeneration)
        settleTimer = nil
        if not active or expectedGeneration ~= generation then return end

        local value = Trim(table.concat(parts, "", 1, partCount))
        local characters = #value
        local boxText = Trim(editBox:GetText() or "")
        active = false
        ClearParts()

        if characters > #boxText then
            BeginTrace()
            FinishTrace("ok", nil, characters, true)
            if type(callbacks.onCaptured) == "function" then
                callbacks.onCaptured(value, characters)
            end
            return
        end
        if #boxText >= PASTE_INPUT_CAP_BYTES then
            BeginTrace()
            FinishTrace("error", "paste_incomplete", characters, false)
            if type(callbacks.onError) == "function" then
                callbacks.onError("paste_incomplete")
            end
            return
        end
        FinishTrace("skip", nil, characters, false)
        if type(callbacks.onShortText) == "function" then
            callbacks.onShortText(boxText)
        end
    end

    local function ScheduleFinalize()
        if settleTimer or not (C_Timer and C_Timer.NewTimer) then return end
        local expectedGeneration = generation
        settleTimer = C_Timer.NewTimer(0, function()
            Finalize(expectedGeneration)
        end)
    end

    editBox:HookScript("OnChar", function(_, value)
        if type(value) ~= "string" or value == "" then return end
        if not active then
            active = true
            generation = generation + 1
            startedAt = TraceNowMS()
            ClearParts()
        end
        partCount = partCount + 1
        parts[partCount] = value
        byteCount = byteCount + #value
        if byteCount > PASTE_INPUT_CAP_BYTES then BeginTrace() end
        ScheduleFinalize()
    end)

    local handle = {}

    function handle:IsCapturing()
        return active
    end

    function handle:Cancel()
        local wasActive = active or settleTimer ~= nil or traceRecord ~= nil
        generation = generation + 1
        if settleTimer and settleTimer.Cancel then settleTimer:Cancel() end
        settleTimer = nil
        active = false
        FinishTrace("skip", "cancelled", byteCount, false)
        ClearParts()
        return wasActive
    end

    handle.Reset = handle.Cancel
    return handle
end

local function CancelParse(frame)
    local active = frame.parseState == "debounce" or frame.parseState == "parsing"
    frame.parseGeneration = (frame.parseGeneration or 0) + 1
    if frame.parseTimer and frame.parseTimer.Cancel then frame.parseTimer:Cancel() end
    frame.parseTimer = nil
    if frame.parseJob and frame.parseJob.Cancel then frame.parseJob:Cancel() end
    frame.parseJob = nil
    frame.parseState = "idle"
    if SetParseBusy then SetParseBusy(frame, false) end
    return active
end

local function SetButtonText(button, value)
    if button and button.text and button.text.SetText then button.text:SetText(value or "") end
end

local function SetStatus(frame, value, colorKey)
    frame.status:SetText(value or "")
    if GUI2.SetTextColorKey then GUI2:SetTextColorKey(frame.status, colorKey or "color.text.secondary") end
end

local PARSE_PHASE_TEXT = {
    capture = { "settings.config_transfer.progress.capture", "已接收配置，正在准备解析……" },
    input = { "settings.config_transfer.progress.input", "正在检查输入……" },
    decode = { "settings.config_transfer.progress.decode", "正在解码配置……" },
    decompress = { "settings.config_transfer.progress.decompress", "正在解压配置……" },
    deserialize = { "settings.config_transfer.progress.deserialize", "正在读取配置……" },
    ["portable-validation"] = { "settings.config_transfer.progress.validate", "正在检查配置……" },
    ["portable-copy"] = { "settings.config_transfer.progress.copy", "正在准备配置……" },
    classify = { "settings.config_transfer.progress.classify", "正在识别模块……" },
    complete = { "settings.config_transfer.progress.complete", "解析完成。" },
    profile = { "settings.config_transfer.progress.profile", "正在准备目标配置……" },
    ["prepare-payload"] = { "settings.config_transfer.progress.prepare_payload", "正在复制所选模块……" },
    ["prepare-normalize"] = { "settings.config_transfer.progress.prepare_normalize", "正在规范化配置……" },
    ["prepare-snapshot"] = { "settings.config_transfer.progress.prepare_snapshot", "正在备份现有配置……" },
    ["prepare-config-sets"] = { "settings.config_transfer.progress.prepare_config_sets", "正在准备配置方案……" },
    ["prepare-module"] = { "settings.config_transfer.progress.prepare_module", "正在整理所选模块……" },
    ["prepare-complete"] = { "settings.config_transfer.progress.prepare_complete", "准备完成，即将应用……" },
    commit = { "settings.config_transfer.progress.commit", "正在应用配置，请勿关闭……" },
    ["import-complete"] = { "settings.config_transfer.progress.import_complete", "导入完成。" },
}

SetParseBusy = function(frame, active, detail)
    local panel = frame and frame.parseBusyPanel
    if not panel then return end
    if not active then
        panel:Hide()
        return
    end
    local phase = detail and detail.phase or "input"
    local progress = detail and detail.progress or 0
    local text = PARSE_PHASE_TEXT[phase] or PARSE_PHASE_TEXT.input
    frame.parseBusyText:SetText(T(text[1], text[2]))
    if frame.parseProgress then frame.parseProgress:SetValue(progress, true) end
    panel:Show()
end

Trim = function(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function DiagnosticReason(value)
    if value == nil then return "-" end
    value = tostring(value):match("^[^\r\n]*") or ""
    value = value:gsub("%c", " "):match("^%s*(.-)%s*$") or ""
    if value == "" then return "-" end
    if #value > 512 then value = value:sub(1, 509) .. "..." end
    return value
end

local function DiagnosticPhaseText(phase)
    local phases = {
        parse = T("settings.config_transfer.phase.parse", "解析阶段"),
        prepare = T("settings.config_transfer.phase.prepare", "准备阶段"),
        profile = T("settings.config_transfer.phase.profile", "配置档阶段"),
        commit = T("settings.config_transfer.phase.commit", "提交阶段"),
        rollback = T("settings.config_transfer.phase.rollback", "回滚阶段"),
    }
    return phases[phase] or tostring(phase or "-")
end

local function DiagnosticModuleText(frame, diagnostic, original)
    local field = original and "originalModuleId" or "moduleId"
    local moduleId = type(diagnostic) == "table" and diagnostic[field] or nil
    if type(moduleId) ~= "string" or moduleId == "" then return "-" end
    local label = frame.moduleLabels and frame.moduleLabels[moduleId]
    if type(label) == "string" and label ~= "" and label ~= moduleId then
        return label .. " [" .. moduleId .. "]"
    end
    return moduleId
end

local function IsRoutineImportError(code)
    return code == "profile_name_required"
        or code == "profile_exists"
        or code == "combat_lockdown"
        or code == "stale_preview"
        or code == "profile_changed"
end

local function ImportErrorText(frame, code, phase, diagnostic)
    if code == "input_too_large" then
        return T("settings.config_transfer.error.input_too_large", "字符串过大，无法导入。")
    end
    if code == "combat_lockdown" then
        return T("settings.config_transfer.error.combat_lockdown", "战斗中无法导入。")
    end
    if code == "profile_name_required" then
        return T("settings.config_transfer.error.profile_name_required", "请输入新配置名称。")
    end
    if code == "profile_exists" then
        return T("settings.config_transfer.error.profile_exists", "同名配置已存在，请使用其他名称。")
    end
    if (code == "profile_switch_failed" or code == "profile_unavailable")
        and type(diagnostic) ~= "table" then
        return T("settings.config_transfer.error.profile_unavailable", "无法创建或切换配置。")
    end
    if code == "stale_preview" or code == "profile_changed" then
        return T("settings.config_transfer.error.state_changed", "配置已变化，请重新导入。")
    end
    if phase == "parse" then
        return T("settings.config_transfer.error.unrecognized", "无法识别此配置字符串。")
    end
    if type(diagnostic) == "table" then
        local diagnosticPhase = DiagnosticPhaseText(diagnostic.phase or phase)
        local moduleText = DiagnosticModuleText(frame, diagnostic)
        if code == "rollback_failed" or diagnostic.rollbackRestored == false then
            return T(
                "settings.config_transfer.error.diagnostic_rollback_failed",
                "导入失败且恢复不完整（%s；%s；错误码：%s），请重载界面。",
                diagnosticPhase,
                moduleText,
                tostring(code or "-")
            )
        end
        if diagnostic.rollbackRestored == true then
            return T(
                "settings.config_transfer.error.diagnostic_restored",
                "导入失败（%s；%s；错误码：%s），更改已恢复。",
                diagnosticPhase,
                moduleText,
                tostring(code or "-")
            )
        end
        return T(
            "settings.config_transfer.error.diagnostic_summary",
            "导入失败（%s；%s；错误码：%s）。",
            diagnosticPhase,
            moduleText,
            tostring(code or "-")
        )
    end
    if code == "rollback_failed" then
        return T(
            "settings.config_transfer.error.rollback_failed",
            "导入失败，部分配置可能未恢复，请重载界面。"
        )
    end
    return T("settings.config_transfer.error.import_failed", "导入失败，未修改配置。")
end

local function PrintImportDiagnostic(frame, code, phase, diagnostic)
    if type(diagnostic) ~= "table" or IsRoutineImportError(code) or not YUI.Print then return end
    local text = T(
        "settings.config_transfer.error.diagnostic_chat",
        "配置导入诊断：阶段=%s；模块=%s；错误码=%s；原因=%s",
        DiagnosticPhaseText(diagnostic.phase or phase),
        DiagnosticModuleText(frame, diagnostic),
        tostring(code or "-"),
        DiagnosticReason(diagnostic.reason)
    )
    if diagnostic.originalCode ~= nil then
        text = text .. T(
            "settings.config_transfer.error.diagnostic_original",
            "；原始阶段=%s；原始模块=%s；原始错误码=%s；原始原因=%s",
            DiagnosticPhaseText(diagnostic.originalPhase),
            DiagnosticModuleText(frame, diagnostic, true),
            tostring(diagnostic.originalCode),
            DiagnosticReason(diagnostic.originalReason)
        )
    end
    YUI:Print(text)
end

local function SelectedIds(frame)
    local ids = {}
    for id, selected in pairs(frame.selection or {}) do
        if selected == true then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function SelectedModuleSummary(frame)
    local ids = SelectedIds(frame)
    local labels = {}
    local visibleCount = math.min(#ids, 5)
    for index = 1, visibleCount do
        local id = ids[index]
        labels[index] = frame.moduleLabels[id] or id
    end
    local summary = table.concat(labels, T("settings.config_transfer.selection_separator", ", "))
    if #ids > visibleCount then
        summary = T(
            "settings.config_transfer.selection_more",
            "%s and %d more",
            summary,
            #ids - visibleCount
        )
    end
    return summary
end

local function RefreshFooter(frame)
    if frame.options and frame.options.refreshImportUI and frame.mode == "import" then
        frame.options.refreshImportUI(frame)
    end
    local selected = #SelectedIds(frame)
    local total = frame.selectableCount or 0
    frame.count:SetText(frame.options and frame.options.simpleImport and ""
        or T("settings.config_transfer.selected", "已选择 %d / %d 个模块", selected, total))
    local disabled = selected == 0 or frame.scopeInvalid == true
    if frame.mode == "import" and frame.legacy then
        disabled = not frame.legacyName or frame.legacyName == ""
    elseif frame.mode == "import" then
        disabled = disabled or frame.parseState == "debounce" or frame.parseState == "parsing"
            or frame.importState == "preparing" or frame.importState == "committing" or frame.importState == "review"
            or not frame.parsed or (InCombatLockdown and InCombatLockdown())
        if frame.importTargetMode == "new" then
            disabled = disabled or Trim(frame.importProfileName) == ""
        end
    end
    frame.primary:SetDisabled(disabled)
    if RefreshPersonalDataOption then RefreshPersonalDataOption(frame) end
end

CancelImport = function(frame)
    local job = frame and frame.importJob
    if not job then return true end
    local cancelled = not job.Cancel or job:Cancel()
    if cancelled ~= true then return false end
    frame.importGeneration = (frame.importGeneration or 0) + 1
    frame.importJob = nil
    frame.importState = frame.parsed and "ready" or "idle"
    SetParseBusy(frame, false)
    if frame.modify and frame.modify.SetDisabled then frame.modify:SetDisabled(false) end
    if frame.close and frame.close.SetDisabled then frame.close:SetDisabled(false) end
    RefreshFooter(frame)
    return true
end

RefreshPersonalDataOption = function(frame)
    local option = frame.personalDataOption
    if not option then return end
    if frame.options and frame.options.soundScopeOption and frame.mode == "export" then
        local available = frame.selection and frame.selection['core.sound'] == true
        if not available then option:SetChecked(false, true) end
        option:SetDisabled(not available, true)
        option.text:SetText(T("sound.share.include_general", "同时包含不限专精的声音规则"))
        option:SetShown(true)
        return
    end
    local available = false
    for id, selected in pairs(frame.selection or {}) do
        if selected == true and frame.personalDataAvailable and frame.personalDataAvailable[id] then
            available = true
            break
        end
    end
    if not available then option:SetChecked(false, true) end
    option:SetDisabled(not available, true)
    option.text:SetText(frame.mode == "import"
        and T("settings.config_transfer.personal_data.import", "Import included personal data")
        or T("settings.config_transfer.personal_data.export", "Include personal data for selected modules"))
    option:SetShown(available)
end

local function BuildPersonalDataContext(frame, field)
    local selected = {}
    if frame.personalDataOption and frame.personalDataOption:GetChecked() then
        for id, enabled in pairs(frame.selection or {}) do
            if enabled == true and frame.personalDataAvailable and frame.personalDataAvailable[id] then
                selected[id] = true
            end
        end
    end
    local context = {}
    for key, value in pairs((frame.options and frame.options.context) or {}) do context[key] = value end
    context[field] = selected
    if frame.options and frame.options.soundScopeOption and frame.mode == "export" then
        context.includeGeneralSounds = frame.selection['core.sound'] == true
            and frame.personalDataOption:GetChecked() == true
    end
    return context
end

local function RefreshImportTarget(frame)
    if frame.options and frame.options.localShare then
        frame.importTarget:Hide()
        frame.importName:Hide(); frame.importNameLabel:Hide(); frame.importCurrentLabel:Hide()
        frame.reserveShare:Show(); frame.soundShareMode:Show()
        SetButtonText(frame.primary, T("sound.share.preview", "预览导入"))
        return
    end
    frame.importTarget:Show()
    frame.reserveShare:Hide(); frame.soundShareMode:Hide()
    if frame.importTargetMode == "current" then
        frame.importNameLabel:Hide()
        frame.importName:Hide()
        frame.importCurrentLabel:SetText(T(
            "settings.config_transfer.target.current_name",
            "当前配置：%s",
            GetDialogProfileName and GetDialogProfileName(frame.options) or "?"
        ))
        frame.importCurrentLabel:Show()
        SetButtonText(
            frame.primary,
            T("settings.config_transfer.import_overwrite", "覆盖当前配置")
        )
    else
        frame.importCurrentLabel:Hide()
        frame.importNameLabel:Show()
        frame.importName:Show()
        SetButtonText(
            frame.primary,
            T("settings.config_transfer.import_new", "新建并导入")
        )
    end
    RefreshFooter(frame)
end

local STATUS_TOOLTIPS = {
    unknown = "settings.config_transfer.status.unknown",
    client_incompatible = "settings.config_transfer.status.client_incompatible",
    schema_newer = "settings.config_transfer.status.schema_newer",
    schema_unsupported = "settings.config_transfer.status.schema_unsupported",
    invalid_payload = "settings.config_transfer.status.invalid_payload",
    invalid_module_payload = "settings.config_transfer.status.invalid_payload",
    unexpected_data_path = "settings.config_transfer.status.invalid_payload",
    unexpected_data_field = "settings.config_transfer.status.invalid_payload",
    unexpected_layout = "settings.config_transfer.status.invalid_payload",
    unexpected_config_sets = "settings.config_transfer.status.invalid_payload",
    unexpected_personal_data = "settings.config_transfer.status.invalid_payload",
}

local function EnsureCheckbox(frame, index)
    local checkbox = frame.checkboxPool[index]
    if checkbox then return checkbox end
    checkbox = GUI2.Form:CreateCheckbox(frame.scroll.child, {
        width = 196,
        height = 28,
        text = "",
        checked = false,
        onClick = function(control, checked)
            local item = control.transferItem
            if not item or item.disabled then return end
            frame.selection[item.id] = checked == true
            RefreshFooter(frame)
        end,
    })
    checkbox:HookScript("OnEnter", function(control)
        if not control.transferTooltip or not GameTooltip then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(control.transferTooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame.checkboxPool[index] = checkbox
    return checkbox
end

local function EnsureGroupDivider(frame, kind)
    local divider = frame.groupDividers[kind]
    if divider then return divider end
    divider = GUI2:CreateDivider(frame.scroll.child, {
        width = SCROLL_CHILD_WIDTH,
        height = 22,
        label = T("settings.config_transfer.group." .. kind, kind),
        alignLeft = true,
    })
    local selectGroup = CreateButton(divider, T("settings.config_transfer.select_all", "全选"), 48, function()
        for _, checkbox in ipairs(frame.checkboxPool) do
            local item = checkbox:IsShown() and checkbox.transferItem or nil
            if item and item.kind == kind and not item.disabled then
                frame.selection[item.id] = true
                checkbox:SetChecked(true, true)
            end
        end
        RefreshFooter(frame)
    end)
    selectGroup:SetSize(48, 20)
    selectGroup:SetFrameLevel((divider:GetFrameLevel() or 0) + 2)
    if GUI2.ApplyButtonStyle then GUI2:ApplyButtonStyle(selectGroup, "grayFilled") end
    selectGroup:SetPoint("RIGHT", divider, "RIGHT", -52, 0)
    local invertGroup = CreateButton(divider, T("settings.config_transfer.invert", "反选"), 48, function()
        for _, checkbox in ipairs(frame.checkboxPool) do
            local item = checkbox:IsShown() and checkbox.transferItem or nil
            if item and item.kind == kind and not item.disabled then
                local selected = frame.selection[item.id] ~= true
                frame.selection[item.id] = selected
                checkbox:SetChecked(selected, true)
            end
        end
        RefreshFooter(frame)
    end)
    invertGroup:SetSize(48, 20)
    invertGroup:SetFrameLevel((divider:GetFrameLevel() or 0) + 2)
    if GUI2.ApplyButtonStyle then GUI2:ApplyButtonStyle(invertGroup, "grayFilled") end
    invertGroup:SetPoint("RIGHT", divider, "RIGHT", 0, 0)
    if divider.gui2DividerLine and divider.gui2DividerText then
        divider.gui2DividerLine:ClearAllPoints()
        divider.gui2DividerLine:SetPoint("LEFT", divider.gui2DividerText, "RIGHT", 8, 0)
        divider.gui2DividerLine:SetPoint("RIGHT", divider, "RIGHT", -112, 0)
    end
    frame.groupDividers[kind] = divider
    frame.groupActions[kind] = { selectAll = selectGroup, invert = invertGroup }
    return divider
end

local function RenderModules(frame, modules, importMode)
    frame.scroll:Show()
    if frame.yhudSimpleImport then frame.yhudSimpleImport:Hide() end
    if importMode and frame.options and frame.options.context and frame.options.context.moduleIds then
        local allowed, filtered = {}, {}
        for _, id in ipairs(frame.options.context.moduleIds) do allowed[id] = true end
        for _, item in ipairs(modules) do
            if allowed[item.id] then filtered[#filtered + 1] = item end
        end
        modules = filtered
    end
    if YUI.IsForever then
        local visible = {}
        for _, item in ipairs(modules) do
            if Transfer:IsModuleVisible(item.id) then visible[#visible + 1] = item end
        end
        modules = visible
    end
    frame.selection = {}
    frame.personalDataAvailable = {}
    frame.selectableCount = 0
    local count = #modules
    local columns = 3
    local itemWidth = 196
    local itemHeight = 28
    local gapX = 14
    local contentOffsetX = math.floor((SCROLL_CHILD_WIDTH - ((itemWidth * columns) + (gapX * (columns - 1)))) / 2)
    frame.moduleLabels = {}
    frame.groupSelectable = {}
    for kind, divider in pairs(frame.groupDividers) do
        divider:Hide()
        local actions = frame.groupActions[kind]
        if actions then
            actions.selectAll:Hide()
            actions.invert:Hide()
        end
    end
    local currentKind
    local groupRow = 0
    local groupIndex = 0
    for index = 1, count do
        local item = modules[index]
        if item.kind ~= currentKind then
            if currentKind ~= nil then groupRow = groupRow + math.ceil(groupIndex / columns) end
            currentKind = item.kind
            groupIndex = 0
            local divider = EnsureGroupDivider(frame, currentKind)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", 0, -(groupRow * itemHeight))
            divider:Show()
            groupRow = groupRow + 1
        end
        groupIndex = groupIndex + 1
        frame.moduleLabels[item.id] = item.label or item.id
        frame.personalDataAvailable[item.id] = importMode
            and item.hasPersonalData == true
            or (not importMode and item.supportsPersonalData == true)
        local checkbox = EnsureCheckbox(frame, index)
        local disabled = importMode and item.status ~= "ready" or item.compatible == false
        checkbox.transferItem = { id = item.id, kind = item.kind, disabled = disabled }
        checkbox.text:SetText(item.label or item.id)
        checkbox:SetDisabled(disabled, true)
        local checked = not disabled and item.selectedByDefault ~= false
        checkbox:SetChecked(checked, true)
        frame.selection[item.id] = checked
        if not disabled then
            frame.selectableCount = frame.selectableCount + 1
            frame.groupSelectable[item.kind] = true
        end
        checkbox:ClearAllPoints()
        local column = (groupIndex - 1) % columns
        local row = groupRow + math.floor((groupIndex - 1) / columns)
        checkbox:SetPoint("TOPLEFT", contentOffsetX + (column * (itemWidth + gapX)), -row * itemHeight)
        checkbox:SetSize(itemWidth, itemHeight)
        local tooltipKey = disabled and STATUS_TOOLTIPS[item.status]
        checkbox.transferTooltip = tooltipKey and T(tooltipKey, item.status) or nil
        checkbox:Show()
    end
    for index = count + 1, #frame.checkboxPool do
        frame.checkboxPool[index]:Hide()
        frame.checkboxPool[index].transferItem = nil
    end
    for kind, divider in pairs(frame.groupDividers) do
        if divider:IsShown() then
            local actions = frame.groupActions[kind]
            local disabled = frame.groupSelectable[kind] ~= true
            actions.selectAll:SetDisabled(disabled, true)
            actions.invert:SetDisabled(disabled, true)
            actions.selectAll:Show()
            actions.invert:Show()
        end
    end
    local rows = math.max(1, groupRow + math.ceil(groupIndex / columns))
    frame.scroll.child:SetSize(SCROLL_CHILD_WIDTH, rows * itemHeight)
    frame.scroll:SetVerticalScroll(0)
    if count > 0 then frame.moduleArea:Show() else frame.moduleArea:Hide() end
    RefreshFooter(frame)
end

local function CollapseInput(frame)
    if not frame.rawString or frame.rawString == "" then return end
    frame.input:Hide()
    frame.inputSummary:Show()
    local summaryKey = frame.largePasteCaptured
        and "settings.config_transfer.captured_summary"
        or "settings.config_transfer.pasted_summary"
    local summaryFallback = frame.largePasteCaptured
        and "已接收 %s 字符"
        or "已粘贴 %s 字符"
    frame.summaryText:SetText(T(summaryKey, summaryFallback, tostring(#frame.rawString)))
    SetButtonText(frame.modify, frame.largePasteCaptured
        and T("settings.config_transfer.repaste", "重新粘贴")
        or T("settings.config_transfer.modify", "修改"))
end

local function ResetImportResult(frame)
    if frame.yhudSimpleImport then frame.yhudSimpleImport:Hide() end
    frame.parsed = nil
    frame.legacy = false
    frame.selection = {}
    frame.personalDataAvailable = {}
    frame.selectableCount = 0
    frame.moduleArea:Hide()
    frame.legacyArea:Hide()
    if frame.importTargetArea then frame.importTargetArea:Hide() end
    if frame.personalDataOption then
        frame.personalDataOption:SetChecked(false, true)
        frame.personalDataOption:Hide()
    end
    SetStatus(frame, "")
    RefreshFooter(frame)
end

local function CompleteParseImport(frame, value, parsed, code)
    frame.parseState = parsed and "ready" or "error"
    SetParseBusy(frame, false)
    frame.parseJob = nil
    RefreshFooter(frame)
    if parsed then
        frame.parsed = parsed
        CollapseInput(frame)
        SetStatus(frame, "")
        frame.importTargetArea:Show()
        RenderModules(frame, parsed.modules, true)
        RefreshImportTarget(frame)
        if frame.options and frame.options.configureImport then frame.options.configureImport(frame, parsed) end
        return
    end
    frame.inputSummary:Hide()
    frame.input:Show()
    if code == "unsupported_prefix" and frame.options and frame.options.isLegacyString
        and frame.options.isLegacyString(value) then
        frame.legacy = true
        CollapseInput(frame)
        frame.importTargetArea:Hide()
        frame.legacyArea:Show()
        SetStatus(frame, T(
            "settings.config_transfer.legacy_detected",
            "检测到旧版配置，将按完整配置导入。"
        ), "color.state.warning")
        SetButtonText(frame.primary, T("settings.config_transfer.import_legacy", "导入完整配置"))
        RefreshFooter(frame)
        return
    end
    if value:find("^!YUI%-SET:") then
        SetStatus(frame, T(
            "settings.config_transfer.config_set_redirect",
            "请在对应产品的方案管理中导入此字符串。"
        ), "color.state.warning")
    else
        SetStatus(frame, ImportErrorText(frame, code, "parse"), "color.state.error")
    end
    if frame.largePasteCaptured then
        frame.largePasteCaptured = false
        frame.rawString = ""
        frame.input.transferSuppress = true
        frame.input:SetText("")
        frame.input.transferSuppress = nil
        SetButtonText(frame.modify, T("settings.config_transfer.modify", "修改"))
    end
end

local function ParseImport(frame)
    frame.parseTimer = nil
    local value = frame.rawString or ""
    ResetImportResult(frame)
    if value == "" then return end
    if frame.options and frame.options.convertImportString then
        local converted, code = frame.options.convertImportString(value)
        if not converted then CompleteParseImport(frame, value, nil, code); return end
        value = converted
    end
    CollapseInput(frame)
    frame.parseState = "parsing"
    SetParseBusy(frame, true, { phase = "input", progress = 0 })
    RefreshFooter(frame)
    local generation = frame.parseGeneration
    if type(Transfer.StartParseImportString) ~= "function" then
        local parsed, code = Transfer:ParseImportString(value)
        CompleteParseImport(frame, value, parsed, code)
        return
    end
    local job = Transfer:StartParseImportString(value, nil, {
        onProgress = function(detail)
            if not frame:IsShown() or generation ~= frame.parseGeneration then return end
            SetParseBusy(frame, true, detail)
        end,
        onComplete = function(parsed, code)
            if not frame:IsShown() or generation ~= frame.parseGeneration then return end
            CompleteParseImport(frame, value, parsed, code)
        end,
    })
    frame.parseJob = job
    if job and job.finished then frame.parseJob = nil end
end

local function ScheduleParse(frame)
    CancelParse(frame)
    frame.parseState = "debounce"
    local generation = frame.parseGeneration
    local function Run()
        if not frame:IsShown() or generation ~= frame.parseGeneration then return end
        ParseImport(frame)
    end
    if C_Timer and C_Timer.NewTimer then
        frame.parseTimer = C_Timer.NewTimer(0.12, Run)
    else
        Run()
    end
end

local function HandleShortInput(frame, value)
    frame.largePasteCaptured = false
    SetButtonText(frame.modify, T("settings.config_transfer.modify", "修改"))
    frame.rawString = value or ""
    ResetImportResult(frame)
    if frame.rawString == "" then
        CancelParse(frame)
        RefreshFooter(frame)
        return
    end
    ScheduleParse(frame)
end

local function HandleCapturedInput(frame, value)
    CancelParse(frame)
    frame.largePasteCaptured = true
    frame.rawString = value
    ResetImportResult(frame)
    frame.input.transferSuppress = true
    frame.input:SetText("")
    frame.input.transferSuppress = nil
    frame.input:ClearFocus()
    CollapseInput(frame)
    ScheduleParse(frame)
    SetParseBusy(frame, true, { phase = "capture", progress = 0 })
end

local function HandlePasteCaptureError(frame)
    CancelParse(frame)
    frame.largePasteCaptured = false
    frame.rawString = ""
    ResetImportResult(frame)
    frame.input.transferSuppress = true
    frame.input:SetText("")
    frame.input.transferSuppress = nil
    frame.inputSummary:Hide()
    frame.input:Show()
    frame.input:SetFocus()
    SetButtonText(frame.modify, T("settings.config_transfer.modify", "修改"))
    SetStatus(frame, T(
        "settings.config_transfer.error.paste_incomplete",
        "粘贴内容未能完整接收，请重新粘贴。"
    ), "color.state.error")
end

local function LayoutDialog(frame, mode)
    local owner=frame.options and frame.options.layoutOwner
    local ownerStrata=owner and owner:GetFrameStrata()
    -- Keep the shared modal above ordinary settings, even when its owner uses DIALOG.
    frame:SetFrameStrata(ownerStrata == "TOOLTIP" and ownerStrata or "FULLSCREEN_DIALOG")
    frame:SetFrameLevel(owner and math.max(FRAME_LEVEL,owner:GetFrameLevel()+40) or FRAME_LEVEL)
    if frame.parseBusyPanel then frame.parseBusyPanel:SetFrameLevel(frame:GetFrameLevel()+20) end
    local height=owner and math.min(FRAME_HEIGHT,owner:GetHeight()-28) or FRAME_HEIGHT
    frame:SetHeight(height)
    S:SyncOwnedWindowScale(frame, owner or S:GetVisibleScaleOwner())
    if not frame.yuiSettingsScaleRoot then
        frame:SetScale(owner and owner:GetEffectiveScale()/UIParent:GetEffectiveScale() or 1)
    end
    frame:ClearAllPoints(); frame:SetPoint("CENTER",owner or UIParent,"CENTER")
    if owner and not (frame.soundLayoutOwners and frame.soundLayoutOwners[owner]) then
        frame.soundLayoutOwners=frame.soundLayoutOwners or setmetatable({}, {__mode='k'})
        frame.soundLayoutOwners[owner]=true
        owner:HookScript('OnSizeChanged',function()
            if frame:IsShown() and frame.options and frame.options.layoutOwner==owner then LayoutDialog(frame,frame.mode) end
        end)
        owner:HookScript('OnHide',function()
            if frame.options and frame.options.layoutOwner==owner then frame:Hide() end
        end)
    end
    frame.status:ClearAllPoints()
    frame.moduleArea:ClearAllPoints()
    frame.legacyArea:ClearAllPoints()
    frame.importTargetArea:ClearAllPoints()
    if mode == "export" then
        local contentTop = 58 + (frame.options.exportHeaderHeight or 0)
        frame.status:SetPoint("BOTTOMLEFT", CONTENT_MARGIN, 56)
        frame.moduleArea:SetPoint("TOPLEFT", CONTENT_MARGIN, -contentTop)
        frame.moduleArea:SetSize(CONTENT_WIDTH, height-contentTop-78)
    else
        frame.status:SetPoint("TOPLEFT", CONTENT_MARGIN, -102)
        frame.importTargetArea:SetPoint("TOPLEFT", CONTENT_MARGIN, -120)
        local contentTop = frame.options.simpleImport and 120 or 178
        frame.moduleArea:SetPoint("TOPLEFT", CONTENT_MARGIN, -contentTop)
        frame.moduleArea:SetSize(CONTENT_WIDTH, height-contentTop-72)
        frame.legacyArea:SetPoint("TOPLEFT", CONTENT_MARGIN, -110)
    end
    frame.scroll:SetSize(SCROLL_WIDTH, frame.moduleArea:GetHeight() - (MODULE_INSET * 2))
end

local function CompletePackageImport(frame, ok, detail, diagnostic, phase)
    if not ok and detail == "review_canceled" then SetStatus(frame, ""); return end
    if not ok then
        SetStatus(
            frame,
            ImportErrorText(frame, detail, phase or "commit", diagnostic),
            "color.state.error"
        )
        PrintImportDiagnostic(frame, detail, phase or "commit", diagnostic)
        return
    end
    local completed = frame.options and frame.options.onComplete
    if completed then completed(detail) end
    frame:Hide()
    if detail.requiresReload then
        ShowImportReloadPrompt()
    else
        ShowImportCompletePrompt(detail.moduleCount)
    end
end

local function StartDefaultPackageImport(parsed, moduleIds, owner, context, callbacks)
    local handle = { state = "preparing", finished = false }

    local function EmitProgress(detail)
        if handle.finished then return end
        if type(callbacks.onProgress) == "function" then
            pcall(callbacks.onProgress, detail)
        end
    end

    local function Finish(ok, detail, diagnostic, phase)
        if handle.finished then return end
        handle.finished = true
        if handle.timer and handle.timer.Cancel then handle.timer:Cancel() end
        handle.timer = nil
        handle.prepareJob = nil
        local callback = callbacks.onComplete
        callbacks = {}
        if type(callback) == "function" then
            pcall(callback, ok, detail, diagnostic, phase)
        end
    end

    local function Schedule(callback)
        if C_Timer and C_Timer.NewTimer then
            handle.timer = C_Timer.NewTimer(0, function()
                handle.timer = nil
                if not handle.finished then callback() end
            end)
        else
            callback()
        end
    end

    local function Prepared(prepared, code, diagnostic)
        handle.prepareJob = nil
        if handle.finished then return end
        if not prepared then return Finish(nil, code, diagnostic, "prepare") end
        handle.prepared = prepared
        local function Commit()
          if handle.finished or handle.state == "commit-pending" or handle.state == "committing" then return end
          handle.state = "commit-pending"
          EmitProgress({ phase = "commit", progress = 0.94 })
          Schedule(function()
            handle.state = "committing"
            EmitProgress({ phase = "commit", progress = 0.96 })
            local ok, detail, commitDiagnostic = Transfer:CommitImport(
                handle.prepared,
                owner
            )
            handle.prepared = nil
            if ok then EmitProgress({ phase = "import-complete", progress = 1 }) end
            Finish(ok, detail, commitDiagnostic, "commit")
          end)
        end
        if type(callbacks.onPrepared) == "function" then
            handle.state = "review"
            local called, reason = pcall(callbacks.onPrepared, prepared, Commit,
                function() Finish(nil, "review_canceled", nil, "review") end)
            if not called then Finish(nil, "review_failed", nil, "review") end
        else Commit() end
    end

    function handle:Cancel()
        if self.finished or self.state == "committing" then return false end
        if self.timer and self.timer.Cancel then self.timer:Cancel() end
        self.timer = nil
        if self.prepareJob and self.prepareJob.Cancel then self.prepareJob:Cancel() end
        self.finished = true
        self.prepareJob = nil
        self.prepared = nil
        callbacks = {}
        return true
    end

    if type(Transfer.StartPrepareImport) == "function" then
        handle.prepareJob = Transfer:StartPrepareImport(
            parsed,
            moduleIds,
            context,
            {
                onProgress = EmitProgress,
                onComplete = Prepared,
            }
        )
    else
        Schedule(function()
            Prepared(Transfer:PrepareImport(parsed, moduleIds, context))
        end)
    end
    return handle
end

local function RunPackageImport(frame)
    local target = {
        mode = frame.importTargetMode or "new",
        profileName = frame.importTargetMode == "current"
            and GetDialogProfileName(frame.options)
            or Trim(frame.importProfileName),
    }
    if target.mode == "new" then
        if target.profileName == "" then
            SetStatus(frame, T(
                "settings.config_transfer.error.profile_name_required",
                "请输入新配置名称。"
            ), "color.state.error")
            return
        end
        local exists = frame.options and frame.options.profileExists
            and frame.options.profileExists(target.profileName)
        if exists then
            SetStatus(frame, T(
                "settings.config_transfer.error.profile_exists",
                "同名配置已存在，请使用其他名称。"
            ), "color.state.error")
            return
        end
    end

    local context = BuildPersonalDataContext(frame, "importPersonalData")
    local parsed = frame.parsed
    local moduleIds = SelectedIds(frame)
    frame.importGeneration = (frame.importGeneration or 0) + 1
    local generation = frame.importGeneration
    frame.importState = "preparing"
    SetParseBusy(frame, true, { phase = "profile", progress = 0 })
    RefreshFooter(frame)

    local callbacks = {
        onPrepared = frame.options and frame.options.reviewPrepared and function(prepared, accept, cancel)
            if generation ~= frame.importGeneration or not frame:IsShown() then cancel(); return end
            frame.importState = "review"
            SetParseBusy(frame, false)
            RefreshFooter(frame)
            frame.options.reviewPrepared(prepared, function()
                if generation == frame.importGeneration and frame:IsShown() then accept() else cancel() end
            end, cancel, frame)
        end,
        onProgress = function(detail)
            if generation ~= frame.importGeneration then return end
            detail = type(detail) == "table" and detail or {}
            frame.importState = (detail.phase == "commit"
                or detail.phase == "import-complete")
                and "committing"
                or "preparing"
            local committing = frame.importState == "committing"
            if frame.modify and frame.modify.SetDisabled then
                frame.modify:SetDisabled(committing)
            end
            if frame.close and frame.close.SetDisabled then
                frame.close:SetDisabled(committing)
            end
            SetParseBusy(frame, true, detail)
            RefreshFooter(frame)
        end,
        onComplete = function(ok, detail, diagnostic, phase)
            if generation ~= frame.importGeneration then return end
            frame.importJob = nil
            frame.importState = ok and "complete" or "ready"
            SetParseBusy(frame, false)
            if frame.modify and frame.modify.SetDisabled then frame.modify:SetDisabled(false) end
            if frame.close and frame.close.SetDisabled then frame.close:SetDisabled(false) end
            RefreshFooter(frame)
            CompletePackageImport(frame, ok, detail, diagnostic, phase or "commit")
        end,
    }

    local startCallback = frame.options and frame.options.startImportPackage
    local callback = frame.options and frame.options.importPackage
    local job
    if startCallback then
        job = startCallback(parsed, moduleIds, target, frame, context, callbacks)
    elseif callback then
        job = { state = "commit-pending", finished = false }
        function job:Cancel()
            if self.finished or self.state == "committing" then return false end
            if self.timer and self.timer.Cancel then self.timer:Cancel() end
            self.finished = true
            callbacks = {}
            return true
        end
        local function RunSynchronousCallback()
            if job.finished then return end
            job.state = "committing"
            callbacks.onProgress({ phase = "commit", progress = 0.96 })
            local ok, detail, diagnostic = callback(
                parsed,
                moduleIds,
                target,
                frame,
                context
            )
            job.finished = true
            callbacks.onComplete(ok, detail, diagnostic, "commit")
        end
        if C_Timer and C_Timer.NewTimer then
            job.timer = C_Timer.NewTimer(0, function()
                job.timer = nil
                RunSynchronousCallback()
            end)
        else
            RunSynchronousCallback()
        end
    else
        job = StartDefaultPackageImport(parsed, moduleIds, frame, context, callbacks)
    end
    if frame.importState == "preparing" or frame.importState == "committing" or frame.importState == "review" then
        frame.importJob = job
    end
end

ShowImportReloadPrompt = function()
    local function Reload()
        if FrameAPI and FrameAPI.ReloadUI then FrameAPI.ReloadUI() end
    end
    if S.ShowConfirmPopup then
        S:ShowConfirmPopup(
            T("settings.config_transfer.reload_required", "配置已导入，需要重载界面才能生效。"),
            Reload,
            {
                titleText = T("settings.config_transfer.complete_title", "导入完成"),
                buttons = {
                    {
                        text = T("settings.config_transfer.reload_now", "立即重载"),
                        tone = "warning",
                        width = 120,
                        callback = Reload,
                    },
                },
            }
        )
    elseif FrameAPI and FrameAPI.ReloadUI then
        FrameAPI.ReloadUI()
    elseif S.ShowReload then
        S:ShowReload()
    end
end

ShowImportCompletePrompt = function(moduleCount)
    local message = T("settings.config_transfer.import_done", "已导入 %d 个模块。", moduleCount)
    if S.ShowConfirmPopup then
        S:ShowConfirmPopup(message, nil, {
            titleText = T("settings.config_transfer.complete_title", "导入完成"),
            buttons = {
                {
                    text = T("common.confirm", "确定"),
                    tone = "success",
                    width = 100,
                },
            },
        })
    elseif YUI.Print then
        YUI:Print(message)
    end
end

GetDialogProfileName = function(options)
    local name = type(options) == "table" and options.profileName or nil
    if type(name) == "string" and name ~= "" then return name end
    return T("settings.profiles.unknown", "未知")
end

local function BuildFrame()
    local frame = GUI2:CreatePanel(UIParent, {
        name = "YUI_ConfigTransferDialog",
        width = FRAME_WIDTH,
        height = FRAME_HEIGHT,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(FRAME_LEVEL)
    frame:EnableMouse(true)
    frame:Hide()
    frame.checkboxPool = {}
    frame.groupDividers = {}
    frame.groupActions = {}
    frame.moduleLabels = {}
    frame.selection = {}

    frame.title = GUI2:CreateText(frame, "", "font.size.title", "color.text.heading")
    frame.title:SetPoint("TOPLEFT", CONTENT_MARGIN, -18)
    frame.title:SetWidth(CONTENT_WIDTH - 36)
    frame.title:SetWordWrap(false)
    frame.close = GUI2:CreateCloseButton(frame, function()
        if frame.importState ~= "committing" then frame:Hide() end
    end)
    frame.close:SetPoint("TOPRIGHT", -14, -14)

    frame.input = GUI2.Form:CreateEditBox(frame, { width = CONTENT_WIDTH, height = 30, text = "" })
    frame.input:SetPoint("TOPLEFT", CONTENT_MARGIN, -60)
    frame.input:SetScript("OnTextChanged", function(edit)
        if edit.transferSuppress then return end
        if frame.pasteCapture and frame.pasteCapture:IsCapturing() then return end
        HandleShortInput(frame, edit:GetText() or "")
    end)
    frame.input:HookScript("OnEditFocusLost", function()
        frame.editingRaw = false
        CollapseInput(frame)
    end)

    frame.inputSummary = GUI2:CreatePanel(frame, { width = CONTENT_WIDTH, height = 34, surface = "color.control.bg", border = "color.border.default" })
    frame.inputSummary:SetPoint("TOPLEFT", CONTENT_MARGIN, -60)
    frame.summaryText = GUI2:CreateText(frame.inputSummary, "", "font.size.md", "color.text.primary")
    frame.summaryText:SetPoint("LEFT", 12, 0)
    frame.modify = CreateButton(frame.inputSummary, T("settings.config_transfer.modify", "修改"), 78, function()
        if frame.importState == "preparing" or frame.importState == "committing" then
            if not CancelImport(frame) then return end
        end
        if frame.pasteCapture then frame.pasteCapture:Cancel() end
        local cancelled = CancelParse(frame)
        ResetImportResult(frame)
        frame.inputSummary:Hide()
        frame.input:Show()
        frame.editingRaw = true
        frame.input.transferSuppress = true
        if frame.largePasteCaptured then
            frame.rawString = ""
            frame.largePasteCaptured = false
            frame.input:SetText("")
        else
            frame.input:SetText(frame.rawString or "")
        end
        frame.input.transferSuppress = nil
        frame.input:SetFocus()
        if frame.rawString ~= "" then frame.input:HighlightText() end
        SetButtonText(frame.modify, T("settings.config_transfer.modify", "修改"))
        if frame.rawString == "" then
            SetStatus(frame, T(
                "settings.config_transfer.repaste_hint",
                "请重新粘贴完整配置字符串。"
            ), "color.text.secondary")
        elseif cancelled then
            SetStatus(frame, T(
                "settings.config_transfer.progress.cancelled",
                "解析已取消，可修改后重试。"
            ), "color.text.secondary")
        end
    end)
    frame.modify:SetPoint("RIGHT", -4, 0)
    frame.inputSummary:Hide()

    frame.pasteCapture = AttachImportPasteCapture(frame.input, {
        onShortText = function(value)
            if frame:IsShown() and frame.mode == "import" then
                HandleShortInput(frame, value)
            end
        end,
        onCaptured = function(value)
            if frame:IsShown() and frame.mode == "import" then
                HandleCapturedInput(frame, value)
            end
        end,
        onError = function()
            if frame:IsShown() and frame.mode == "import" then
                HandlePasteCaptureError(frame)
            end
        end,
    })

    frame.status = GUI2:CreateText(frame, "", "font.size.sm", "color.text.secondary")
    frame.status:SetPoint("TOPLEFT", CONTENT_MARGIN, -102)
    frame.status:SetWidth(CONTENT_WIDTH)

    frame.legacyArea = GUI2:CreatePanel(frame, { width = CONTENT_WIDTH, height = 48, surface = "color.surface.sunken", border = "color.border.subtle" })
    frame.legacyArea:SetPoint("TOPLEFT", CONTENT_MARGIN, -110)
    local legacyLabel = GUI2:CreateText(frame.legacyArea, T("settings.profiles.profile_name", "配置名称"), "font.size.md", "color.text.primary")
    legacyLabel:SetPoint("LEFT", 12, 0)
    frame.legacyInput = GUI2.Form:CreateEditBox(frame.legacyArea, { width = 220, height = 28, text = "" })
    frame.legacyInput:SetPoint("LEFT", legacyLabel, "RIGHT", 12, 0)
    frame.legacyInput:SetScript("OnTextChanged", function(edit)
        frame.legacyName = edit:GetText() or ""
        RefreshFooter(frame)
    end)
    frame.legacyArea:Hide()

    frame.importTargetArea = GUI2:CreatePanel(frame, {
        width = CONTENT_WIDTH,
        height = 48,
        surface = "color.surface.sunken",
        border = "color.border.subtle",
    })
    frame.importTarget = GUI2.Form:CreateSegmentedControl(frame.importTargetArea, {
        width = 210,
        height = 28,
        items = {
            {
                text = T("settings.config_transfer.target.new", "新建配置"),
                value = "new",
            },
            {
                text = T("settings.config_transfer.target.current", "覆盖当前"),
                value = "current",
            },
        },
        value = "new",
        set = function(value)
            frame.importTargetMode = value == "current" and "current" or "new"
            RefreshImportTarget(frame)
        end,
    })
    frame.importTarget:SetPoint("LEFT", 10, 0)
    frame.reserveShare = GUI2.Form:CreateCheckbox(frame.importTargetArea, {
        width = 330, height = 28, text = T("sound.share.reserve", "图形方案仅保存为备用"), checked = false,
        set = function(value) if frame.options and frame.options.context then
            frame.options.context.yhudReserve = value == true
        end end,
    })
    frame.reserveShare:SetPoint("LEFT", 10, 0); frame.reserveShare:Hide()
    frame.soundShareMode = GUI2.Form:CreateDropdown(frame.importTargetArea, {
        width = 270, height = 28, value = 'incremental', options = {
            { text = T("sound.share.incremental", "声音：增量更新"), value = 'incremental' },
            { text = T("sound.share.replace", "声音：替换全部规则"), value = 'replace' },
        }, set = function(value) if frame.options and frame.options.context then
            frame.options.context.soundImportMode = value
        end end,
    })
    frame.soundShareMode:SetPoint("RIGHT", -10, 0); frame.soundShareMode:Hide()
    frame.importNameLabel = GUI2:CreateText(
        frame.importTargetArea,
        T("settings.config_transfer.target.new_name", "新配置名称"),
        "font.size.md",
        "color.text.primary"
    )
    frame.importNameLabel:SetPoint("LEFT", frame.importTarget, "RIGHT", 16, 0)
    frame.importName = GUI2.Form:CreateEditBox(frame.importTargetArea, {
        width = 220,
        height = 28,
        text = "",
    })
    frame.importName:SetPoint("LEFT", frame.importNameLabel, "RIGHT", 10, 0)
    frame.importName:SetMaxLetters(128)
    frame.importName:SetScript("OnTextChanged", function(edit)
        frame.importProfileName = edit:GetText() or ""
        RefreshFooter(frame)
    end)
    frame.importCurrentLabel = GUI2:CreateText(
        frame.importTargetArea,
        "",
        "font.size.md",
        "color.state.warning"
    )
    frame.importCurrentLabel:SetPoint("LEFT", frame.importTarget, "RIGHT", 16, 0)
    frame.importCurrentLabel:Hide()
    frame.importTargetArea:Hide()

    frame.moduleArea = GUI2:CreatePanel(frame, { width = CONTENT_WIDTH, height = 378, surface = "color.surface.sunken", border = "color.border.subtle" })
    frame.moduleArea:SetPoint("TOPLEFT", CONTENT_MARGIN, -110)
    frame.scroll = GUI2:CreateScrollFrame(frame.moduleArea, {
        width = SCROLL_WIDTH,
        height = 354,
        autoHide = true,
        childWidth = SCROLL_CHILD_WIDTH,
        childHeight = 354,
    })
    frame.scroll:SetPoint("TOPLEFT", MODULE_INSET, -MODULE_INSET)
    frame.moduleArea:Hide()

    frame.personalDataOption = GUI2.Form:CreateCheckbox(frame, {
        width = 330,
        height = 28,
        text = "",
        checked = false,
    })
    frame.personalDataOption:SetPoint("BOTTOM", frame, "BOTTOM", -8, 14)
    frame.personalDataOption:Hide()

    frame.count = GUI2:CreateText(frame, "", "font.size.sm", "color.text.secondary")
    frame.count:SetPoint("BOTTOMLEFT", CONTENT_MARGIN, 22)
    frame.primary = CreateButton(frame, "", 146, function()
        if frame.mode == "export" then
            local context = BuildPersonalDataContext(frame, "includePersonalData")
            local value, detail, moduleId = Transfer:BuildExport(SelectedIds(frame), context)
            if not value then
                if detail == "package_too_large" then
                    SetStatus(frame, T(
                        "settings.config_transfer.export_package_too_large",
                        "内容过大，请减少模块。"
                    ), "color.state.error")
                elseif detail == "capacity-exceeded" and moduleId then
                    SetStatus(frame, T(
                        "settings.config_transfer.export_capacity_exceeded",
                        "“%s”的配置方案过大，请在产品设置中分别导出方案。",
                        frame.moduleLabels[moduleId] or moduleId
                    ), "color.state.error")
                elseif detail == 'legacy-sounds-pending' then
                    SetStatus(frame, T('sound.share.legacy_pending', '请先在声音提醒中处理待恢复的历史规则，再导出声音。'), 'color.state.warning')
                elseif moduleId then
                    if type(YUI.Print) == "function" then
                        YUI:Print("配置导出失败（" .. tostring(moduleId) .. "）：" .. tostring(detail))
                    end
                    SetStatus(frame, T(
                        "settings.config_transfer.export_module_failed",
                        "“%s”无法导出。",
                        frame.moduleLabels[moduleId] or moduleId
                    ), "color.state.error")
                else
                    SetStatus(frame, T(
                        "settings.config_transfer.export_failed",
                        "导出失败，请重试。"
                    ), "color.state.error")
                end
                return
            end
            frame:Hide()
            S:ShowCopyPopup(
                T("settings.config_transfer.export_result", "导出配置 · %d 字符", detail.characterCount),
                value
            )
            return
        end
        if frame.legacy then
            local callback = frame.options and frame.options.importLegacy
            if callback and callback(frame.rawString, frame.legacyName) ~= false then frame:Hide() end
            return
        end
        if frame.importTargetMode == "current" and not (frame.options and frame.options.localShare) and S.ShowConfirmPopup then
            S:ShowConfirmPopup(
                T(
                    "settings.config_transfer.confirm_overwrite",
                    "当前配置：%s\n覆盖模块：%s\n\n这些模块的现有设置将被替换。",
                    GetDialogProfileName(frame.options),
                    SelectedModuleSummary(frame)
                ),
                function()
                    if frame:IsShown() then RunPackageImport(frame) end
                end,
                {
                    titleText = T(
                        "settings.config_transfer.confirm_overwrite_title",
                        "确认覆盖"
                    ),
                    acceptText = T(
                        "settings.config_transfer.confirm_overwrite_accept",
                        "覆盖并导入"
                    ),
                    acceptTone = "danger",
                    acceptWidth = 120,
                    height = 180,
                    ownerFrame = frame,
                }
            )
            return
        end
        RunPackageImport(frame)
    end, "accent")
    GUI2.Form:StyleDialogPrimary(frame.primary)
    frame.primary:SetPoint("BOTTOMRIGHT", -CONTENT_MARGIN, 16)

    frame.parseBusyPanel = GUI2:CreatePanel(frame, {
        width = CONTENT_WIDTH,
        height = 440,
        surface = "color.surface.popup",
        border = "color.border.subtle",
    })
    frame.parseBusyPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_MARGIN, -102)
    frame.parseBusyPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -CONTENT_MARGIN, 12)
    frame.parseBusyPanel:SetFrameLevel(FRAME_LEVEL + 20)
    frame.parseBusyPanel:EnableMouse(true)
    frame.parseBusyText = GUI2:CreateText(
        frame.parseBusyPanel,
        "",
        "font.size.md",
        "color.text.primary",
        "CENTER"
    )
    frame.parseBusyText:SetPoint("CENTER", frame.parseBusyPanel, "CENTER", 0, 24)
    frame.parseBusyText:SetWidth(440)
    if GUI2.Data and GUI2.Data.CreateProgressBar then
        frame.parseProgress = GUI2.Data:CreateProgressBar(frame.parseBusyPanel, {
            width = 440,
            height = 18,
            value = 0,
            fillColor = "color.accent.primary",
        })
        frame.parseProgress:SetPoint("TOP", frame.parseBusyText, "BOTTOM", 0, -14)
    end
    frame.parseBusyPanel:Hide()

    frame:SetScript("OnHide", function(owner)
        local closed = owner.options and owner.options.onClosed
        if owner.pasteCapture then owner.pasteCapture:Cancel() end
        CancelImport(owner)
        CancelParse(owner)
        owner.rawString = nil
        owner.largePasteCaptured = false
        owner.parsed = nil
        owner.options = nil
        owner.selection = {}
        owner.personalDataAvailable = {}
        owner.input.transferSuppress = true
        owner.input:SetText("")
        owner.input.transferSuppress = nil
        owner.legacyInput:SetText("")
        owner.inputSummary:Hide()
        owner.input:Hide()
        owner.moduleArea:Hide()
        owner.legacyArea:Hide()
        owner.importTargetArea:Hide()
        owner.importTargetMode = "new"
        owner.importProfileName = ""
        owner.importName:SetText("")
        owner.personalDataOption:SetChecked(false, true)
        owner.personalDataOption:Hide()
        owner.parseState = "idle"
        owner.importState = "idle"
        SetParseBusy(owner, false)
        if closed then closed() end
    end)
    return frame
end

local function GetFrame()
    S.ConfigTransferDialog = S.ConfigTransferDialog or BuildFrame()
    return S.ConfigTransferDialog
end

function S:ShowConfigTransferExport(options)
    local frame = GetFrame()
    if frame.pasteCapture then frame.pasteCapture:Cancel() end
    CancelParse(frame)
    frame.mode = "export"
    frame.parseState = "idle"
    frame.importState = "idle"
    frame.options = type(options) == "table" and options or {}
    frame.scopeInvalid = nil
    frame.rawString = nil
    frame.largePasteCaptured = false
    frame.parsed = nil
    frame.legacy = false
    frame.title:SetText(T(
        "settings.config_transfer.export_title",
        "选择要导出的模块：%s",
        GetDialogProfileName(frame.options)
    ))
    LayoutDialog(frame, "export")
    frame.input:Hide()
    frame.inputSummary:Hide()
    frame.legacyArea:Hide()
    frame.importTargetArea:Hide()
    frame.personalDataOption:SetChecked(false, true)
    frame.personalDataOption:Hide()
    SetStatus(frame, "")
    SetButtonText(frame.primary, T("settings.config_transfer.generate", "生成导出字符串"))
    RenderModules(frame, Transfer:ListModules(frame.options and frame.options.context), false)
    if frame.options.configureExport then frame.options.configureExport(frame) end
    frame:Show()
end

function S:ShowConfigTransferImport(options)
    local frame = GetFrame()
    if frame:IsShown() and frame.options and frame.options.onClosed then frame:Hide() end
    if frame.pasteCapture then frame.pasteCapture:Cancel() end
    CancelParse(frame)
    frame.mode = "import"
    frame.parseState = "idle"
    frame.importState = "idle"
    frame.options = type(options) == "table" and options or {}
    frame.scopeInvalid = nil
    frame.rawString = ""
    frame.largePasteCaptured = false
    frame.parsed = nil
    frame.legacy = false
    frame.legacyName = ""
    frame.importTargetMode = frame.options.localShare and "current" or "new"
    frame.reserveShare:SetChecked(false, true)
    frame.soundShareMode:SetValue('incremental', true)
    frame.importProfileName = ""
    frame.importTarget:SetValue("new", true)
    frame.importName:SetText("")
    frame.personalDataOption:SetChecked(false, true)
    frame.personalDataOption:Hide()
    frame.title:SetText(T(
        "settings.config_transfer.import_title",
        "导入配置：%s",
        GetDialogProfileName(frame.options)
    ))
    LayoutDialog(frame, "import")
    frame.input.transferSuppress = true
    frame.input:SetText("")
    frame.input.transferSuppress = nil
    frame.input:Show()
    frame.inputSummary:Hide()
    SetButtonText(frame.primary, T("settings.config_transfer.import_selected", "导入所选模块"))
    ResetImportResult(frame)
    frame:Show()
    frame.input:SetFocus()
    if type(frame.options.initialString) == "string" then
        HandleCapturedInput(frame, frame.options.initialString)
    end
end

function S:ShowConfigTransferReview(lines, accept, cancel, owner)
    local panel = self.reviewPanel
    if panel then panel:Hide() end
    if not panel then
        panel = GUI2:CreatePanel(owner, { width = 650, height = 470, surface = 'color.surface.popup',
            border = 'color.popup.border', shadow = true })
        self.reviewPanel = panel
        panel:SetPoint('CENTER'); panel:EnableMouse(true)
        local title = GUI2:CreateText(panel, T('sound.share.preview'), 'font.size.lg', 'color.text.heading')
        title:SetPoint('TOPLEFT', 18, -16)
        local close = GUI2:CreateCloseButton(panel, function() panel:Hide() end)
        close:SetPoint('TOPRIGHT', -12, -12)
        panel.scroll = GUI2:CreateScrollFrame(panel, { width = 610, height = 356, childWidth = 596, childHeight = 356, autoHide = true })
        panel.scroll:SetPoint('TOPLEFT', 18, -52)
        panel.body = GUI2:CreateText(panel.scroll.child, '', 'font.size.md', 'color.text.primary', 'LEFT')
        panel.body:SetPoint('TOPLEFT', 0, 0); panel.body:SetWordWrap(true)
        local no = GUI2.Form:CreateTextLink(panel, { width = 90, height = 34, colorKey = 'color.text.secondary', text = T('sound.share.cancel'),
            onClick = function() panel:Hide() end })
        no:SetPoint('BOTTOMLEFT', 18, 16)
        local yes = GUI2.Form:CreateButton(panel, { width = 130, height = 30, text = T('sound.share.confirm'), tone = 'accent',
            onClick = function()
                local callback = panel.accept
                panel.accept, panel.cancel = nil, nil; panel:Hide()
                if callback then callback() end
            end })
        GUI2.Form:StyleDialogPrimary(yes)
        yes:SetPoint('BOTTOMRIGHT', -18, 16)
        panel:SetScript('OnHide', function()
            if GUI2.HideModalScrim then GUI2:HideModalScrim(panel) end
            local callback = panel.cancel
            panel.accept, panel.cancel = nil, nil
            if callback then callback() end
        end)
        owner:HookScript('OnHide', function() panel:Hide() end)
        panel:EnableKeyboard(true)
        panel:SetScript('OnKeyDown', function(self, key)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(key ~= 'ESCAPE') end
            if key == 'ESCAPE' then self:Hide() end
        end)
    end
    panel.accept, panel.cancel = accept, cancel
    panel:SetFrameStrata(owner:GetFrameStrata()); panel:SetFrameLevel(owner:GetFrameLevel() + 30)
    local width, height = math.min(650, owner:GetWidth() - 24), math.min(470, owner:GetHeight() - 24)
    panel:SetSize(width, height)
    panel.scroll:SetSize(width - 36, height - 110)
    panel.scroll.child:SetWidth(width - 50); panel.body:SetWidth(width - 54)
    panel.body:SetText(table.concat(lines, '\n\n'))
    GUI2:FitScrollContent(panel.scroll,panel.body:GetStringHeight()+12)
    panel:Show()
    local scrim = GUI2:ShowModalScrim(panel)
    if scrim then scrim:SetParent(owner); scrim:ClearAllPoints(); scrim:SetAllPoints(owner) end
end

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

local function FinishOpenColorPicker(action)
    local picker = GUI2 and GUI2.ColorPicker
    if not picker or not picker:IsShown() then return true end
    return picker:Close(action or "cancel")
end

local function ReturnOpenFailure(source, code, detail)
    if source == "settings" and code ~= "combat" then
        local message = T(
            "designer.error_open",
            "Halo 监控台：无法打开设计界面："
        ) .. tostring(code or "designer-ui-unavailable")
        if detail ~= nil and tostring(detail) ~= "" then
            message = message .. " (" .. tostring(detail) .. ")"
        end
        Print(message)
    end
    return nil, code, detail
end

local BUSY_PHASE_KEYS = {
    ["read-configuration"] = "designer.busy.read",
    ["convert-legacy-pack"] = "designer.busy.convert",
    ["load-specializations"] = "designer.busy.load_specs",
    ["prepare-configuration"] = "designer.busy.prepare",
    ["prepare-specializations"] = "designer.busy.save_specs",
    ["complete"] = "designer.busy.commit",
}

local BUSY_PHASE_FALLBACKS = {
    ["read-configuration"] = "正在读取配置…",
    ["convert-legacy-pack"] = "正在转换旧配置…",
    ["load-specializations"] = "正在加载专精内容…",
    ["prepare-configuration"] = "正在整理草稿…",
    ["prepare-specializations"] = "正在处理专精内容…",
    ["complete"] = "正在提交配置…",
}

function DesignerUI:EnsureBusyOverlay()
    if self.busyOverlay then return self.busyOverlay end
    local overlay = GUI2:CreatePanel(UIParent, {
        width = 480,
        height = 150,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(700)
    overlay:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    overlay:EnableMouse(true)
    overlay:Hide()
    overlay.text = GUI2:CreateText(
        overlay,
        "",
        "font.size.md",
        "color.text.primary",
        "CENTER"
    )
    overlay.text:SetPoint("TOP", overlay, "TOP", 0, -28)
    overlay.text:SetWidth(420)
    if GUI2.Data and GUI2.Data.CreateProgressBar then
        overlay.progress = GUI2.Data:CreateProgressBar(overlay, {
            width = 420,
            height = 18,
            value = 0,
            fillColor = "color.accent.primary",
        })
        overlay.progress:SetPoint("TOP", overlay.text, "BOTTOM", 0, -14)
    end
    overlay.cancel = GUI2.Form:CreateButton(overlay, {
        text = T("designer.cancel", "取消"),
        width = 84,
        height = 28,
        tone = "default",
        onClick = function()
            DesignerUI:CancelBusyOperation()
        end,
    })
    overlay.cancel:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 18)
    self.busyOverlay = overlay
    return overlay
end

function DesignerUI:SetBusyInteractionBlocked(blocked)
    local controls = {
        self.finishButton,
        self.cancelButton,
        self.profileDropdown,
        self.layoutButton,
        self.viewSpecButton,
        self.configSetManagerButton or false,
        self.globalSoundButton,
        self.libraryButton,
        self.blizzardCooldownButton,
    }
    for index = 1, #controls do
        local control = controls[index]
        if control and control.SetDisabled then
            control:SetDisabled(blocked == true)
        end
    end
end

function DesignerUI:ShowBusyOperation(kind, generation, cancelable)
    local overlay = self:EnsureBusyOverlay()
    self.busyKind = kind
    self.busyGeneration = generation
    self.busyCancelable = cancelable == true
    self:SetBusyInteractionBlocked(true)
    if overlay.progress then overlay.progress:SetValue(0, true) end
    overlay.text:SetText(T(
        kind == "open" and "designer.busy.read"
            or "designer.busy.prepare",
        kind == "open" and "正在读取配置…" or "正在整理草稿…"
    ))
    if overlay.cancel and overlay.cancel.SetDisabled then
        overlay.cancel:SetDisabled(not self.busyCancelable)
    end
    overlay:Show()
end

function DesignerUI:UpdateBusyProgress(detail)
    if not self.busyOverlay or type(detail) ~= "table" then return end
    local phase = detail.phase
    self.busyOverlay.text:SetText(T(
        BUSY_PHASE_KEYS[phase] or "designer.busy.prepare",
        BUSY_PHASE_FALLBACKS[phase] or "正在处理配置…"
    ))
    if self.busyOverlay.progress then
        self.busyOverlay.progress:SetValue(detail.progress or 0, true)
    end
end

function DesignerUI:SetBusyCancelable(cancelable)
    self.busyCancelable = cancelable == true
    if self.busyOverlay and self.busyOverlay.cancel
        and self.busyOverlay.cancel.SetDisabled then
        self.busyOverlay.cancel:SetDisabled(not self.busyCancelable)
    end
end

function DesignerUI:ClearBusyOperation(generation)
    if generation ~= nil and generation ~= self.busyGeneration then
        return false
    end
    self.busyJob = nil
    self.busyKind = nil
    self.busyCancelable = false
    if self.busyOverlay then self.busyOverlay:Hide() end
    self:SetBusyInteractionBlocked(false)
    return true
end

function DesignerUI:CancelBusyOperation()
    if self.busyCancelable ~= true then return false end
    local job = self.busyJob
    local generation = self.busyGeneration
    self.busyGeneration = (tonumber(generation) or 0) + 1
    if job and job.Cancel then job:Cancel() end
    self:ClearBusyOperation()
    self.saving = false
    return true
end

function DesignerUI:PositionPanelBesideGroup(panel, groupId, animate)
    if not panel then return false end
    local target = groupId and YHUD.View
        and YHUD.View:GetGroupFrame(groupId)
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    local panelWidth = panel.GetWidth and panel:GetWidth() or 360
    local panelHeight = panel.GetHeight and panel:GetHeight() or 780
    local targetLeft = target and target.GetLeft and target:GetLeft()
    local targetRight = target and target.GetRight and target:GetRight()
    local targetX
    local targetY
    if target and target.GetCenter then
        targetX, targetY = target:GetCenter()
    end

    panel:ClearAllPoints()
    if screenWidth and screenHeight and targetLeft and targetRight and targetY then
        local margin = 20
        local gap = 200
        local modeBottom = self.modeSwitcher
            and self.modeSwitcher.IsShown
            and self.modeSwitcher:IsShown()
            and self.modeSwitcher.GetBottom
            and self.modeSwitcher:GetBottom()
        local toolbarBottom = modeBottom
            or (self.toolbar and self.toolbar.GetBottom
                and self.toolbar:GetBottom())
        local topMargin = toolbarBottom
            and math.max(20, screenHeight - toolbarBottom + 16)
            or 94
        local bottomMargin = 20
        local leftSpace = targetLeft - margin
        local rightSpace = screenWidth - targetRight - margin
        local placeRight = rightSpace >= panelWidth + gap
            or rightSpace >= leftSpace
        local x
        if placeRight then
            self.inspectorSide = "right"
            x = targetRight + gap
        else
            self.inspectorSide = "left"
            x = targetLeft - gap - panelWidth
        end
        x = math.max(margin, math.min(screenWidth - margin - panelWidth, x))

        local top = targetY + panelHeight * 0.5
        top = math.max(
            bottomMargin + panelHeight,
            math.min(screenHeight - topMargin, top)
        )
        panel:SetPoint(
            "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            x,
            top
        )
    else
        local screenX = UIParent and UIParent.GetCenter and UIParent:GetCenter()
        if targetX and screenX and targetX >= screenX then
            self.inspectorSide = "left"
            panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -92)
        else
            self.inspectorSide = "right"
            panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -92)
        end
    end
    if animate and GUI2.FadeIn then
        GUI2:FadeIn(panel, {
            from = 0.82,
            to = 1,
            duration = 0.12,
            owner = self,
        })
    end
    return true
end

function DesignerUI:PositionInspector(animate)
    if not self.panel or self.manualPanel then return false end
    local session = Designer:GetSession()
    return self:PositionPanelBesideGroup(
        self.panel,
        session and session.selectedGroupId,
        animate
    )
end

function DesignerUI:PositionSkyridingSettingsPanel(animate)
    if not self.skyridingSettingsPanel or self.manualPanel then return false end
    local groupId = YHUD.GROUP_IDS and YHUD.GROUP_IDS.SKYRIDING
        or "group:system:skyriding"
    return self:PositionPanelBesideGroup(
        self.skyridingSettingsPanel,
        groupId,
        animate
    )
end

function DesignerUI:SetInspectorSuppressedForGroupDrag(suppressed)
    suppressed = suppressed == true
    if suppressed then
        if self.inspectorSuppressedByGroupDrag then return false end
        self.inspectorSuppressedByGroupDrag = true
        local panel = self.designerMode == "skyriding"
            and self.skyridingSettingsPanel or self.panel
        local shown = panel and panel.IsShown and panel:IsShown()
        if shown == nil and panel then shown = panel.shown ~= false end
        self.restoreInspectorAfterGroupDrag = shown == true
        self:HideMonitorPicker()
        self:HideGlowEditor()
        if panel then panel:Hide() end
        return true
    end

    if not self.inspectorSuppressedByGroupDrag then return false end
    self.inspectorSuppressedByGroupDrag = false
    local restore = self.restoreInspectorAfterGroupDrag == true
    self.restoreInspectorAfterGroupDrag = nil
    local session = Designer:GetSession()
    if restore
        and self.active == true
        and Designer:IsOpen()
        and session then
        local panel = self.designerMode == "skyriding"
            and self.skyridingSettingsPanel or self.panel
        if panel then panel:Show() end
        if self.designerMode == "skyriding" then
            self:PositionSkyridingSettingsPanel(false)
        else
            self:PositionInspector(false)
        end
    end
    return true
end

local function SelectDesignGroup(groupId)
    local View = YHUD.View
    local runtime = View and View.groups and View.groups[groupId]
    if runtime and runtime.runtimeOwned == true
        and DesignerUI.SelectRuntimeGroup then
        return DesignerUI:SelectRuntimeGroup(groupId)
    end
    DesignerUI:SelectGroup(groupId)
end

local function AddDesignMonitor(groupId)
    local activeProfile = Designer:GetProfile()
    local group = activeProfile
        and activeProfile.groups
        and activeProfile.groups.items[groupId]
    local capabilities = YHUD:GetGroupAddCapabilities(group)
    DesignerUI:OpenMonitorPicker(
        groupId,
        capabilities.cooldown and "cooldown" or "buff"
    )
end

local function SelectDesignMonitor(monitorId, resourceId, groupId)
    if resourceId then
        return DesignerUI:SelectResourceBar(groupId, resourceId) == true
    end
    return DesignerUI:SelectMonitor(monitorId) ~= nil
end

local function SelectedDesignMonitorId(session)
    if not session then return nil end
    return session.selectedMonitorId or session.selectedPreviewMonitorId
end

local function ReorderDesignMonitor(
    monitorId,
    targetLane,
    targetIndex,
    placement
)
    local View = YHUD.View
    local desiredMonitors = View and View.designProjection
        and View.designProjection.desiredMonitors
        or View and View.desiredMonitors
    local runtimeMonitor = desiredMonitors and desiredMonitors[monitorId]
    local resource = runtimeMonitor and runtimeMonitor._yhudResource
    if resource then
        return DesignerUI:ReorderResourcePreset(
            resource.id,
            nil,
            targetIndex,
            true
        ) ~= nil
    end
    local selected = Designer:SelectMonitor(monitorId)
    if not selected then return false end
    return DesignerUI:ReorderSelectedMonitor(
        nil,
        targetIndex,
        targetLane,
        placement
    ) ~= nil
end

local function BeginDesignGroupDrag(groupId)
    local View = YHUD.View
    if View and View.FinishStagedDesignGroup then
        View:FinishStagedDesignGroup(groupId)
    end
    DesignerUI:SetInspectorSuppressedForGroupDrag(true)
end

local function EndDesignGroupDrag()
    DesignerUI:SetInspectorSuppressedForGroupDrag(false)
end

local function PrepareViewDesignMode(View, session)
    if not (View and View.PrepareDesignMode) then return nil end
    local prepared, wasEnabled = View:PrepareDesignMode(
        true,
        session.selectedGroupId,
        SelectDesignGroup,
        AddDesignMonitor,
        SelectedDesignMonitorId(session),
        SelectDesignMonitor,
        ReorderDesignMonitor,
        BeginDesignGroupDrag,
        EndDesignGroupDrag
    )
    return prepared == true and wasEnabled or nil, prepared == true
end

local function FinishViewDesignMode(View, session, wasEnabled, prepared)
    if prepared and View.RefreshDesignModePresentation then
        return View:RefreshDesignModePresentation(true, wasEnabled, true)
    end
    if not View.SetDesignMode then return false end
    return View:SetDesignMode(
        true,
        session.selectedGroupId,
        SelectDesignGroup,
        AddDesignMonitor,
        SelectedDesignMonitorId(session),
        SelectDesignMonitor,
        ReorderDesignMonitor,
        BeginDesignGroupDrag,
        EndDesignGroupDrag
    )
end

local GetActiveRuntimeProfile

local DESIGN_ENTER_STATES = {
    closed = true,
    preparing = true,
    ["entering-groups"] = true,
    ["entering-inspector"] = true,
    active = true,
    exiting = true,
    aborting = true,
}
local DESIGN_SLICE_BUDGET_MS = 6
local DESIGN_GUI_SLICE_BUDGET_MS = 10
-- 即使计时值未推进，也必须把执行权交回下一帧，保留取消机会。
local DESIGN_MAX_STEPS_PER_SLICE = 64
local DESIGN_GROUP_FADE_SECONDS = 0.2
local DESIGN_GROUP_STAGGER_SECONDS = 0.035
YHUD.DESIGNER_DIAGNOSTIC_PROTOCOL = 3

local function DesignerNowMS()
    if type(_G.debugprofilestop) == "function" then
        local ok, value = pcall(_G.debugprofilestop)
        if ok and type(value) == "number" then return value end
    end
    local clock = _G.GetTimePreciseSec or _G.GetTime
    return clock and (clock() * 1000) or 0
end

local function DesignerMemoryKB()
    if type(_G.collectgarbage) ~= "function" then return 0 end
    local ok, value = pcall(_G.collectgarbage, "count")
    return ok and tonumber(value) or 0
end

local function CopyOperationStats(operation)
    if type(operation) ~= "table" then return nil end
    local copy = {
        operationId = operation.id,
        state = operation.state,
        interactiveMS = operation.interactiveMS,
        allMoversReadyMS = operation.allMoversReadyMS,
        inspectorReadyMS = operation.inspectorReadyMS,
        totalWorkMS = operation.totalWorkMS or 0,
        totalElapsedMS = operation.totalElapsedMS,
        maxSliceMS = operation.maxSliceMS or 0,
        slowestGroupId = operation.slowestGroupId,
        slowestStage = operation.slowestStage,
        slowestStageMS = operation.slowestStageMS or 0,
        sliceCount = operation.sliceCount or 0,
        guiCreates = operation.guiCreates or 0,
        uiWrites = operation.uiWrites or 0,
        layoutWrites = operation.layoutWrites or 0,
        relayouts = operation.relayouts or 0,
        animationStartedAt = operation.animationStartedAt,
        animationStoppedAt = operation.animationStoppedAt,
        animationActive = operation.animationActive or 0,
        tailCallbacks = operation.tailCallbacks or 0,
        budgetViolations = operation.budgetViolations or 0,
        cpuBeforeMS = operation.cpuBeforeMS,
        cpuClickMS = operation.cpuClickMS,
        abortedReason = operation.abortedReason,
        completed = operation.completed == true,
        slices = {},
        groups = {},
        guiCreateTypes = {},
        tail = {},
    }
    for index = 1, #(operation.slices or {}) do
        local row = operation.slices[index]
        copy.slices[index] = {
            stage = row.stage,
            groupId = row.groupId,
            elapsedMS = row.elapsedMS,
            allocationKB = row.allocationKB,
            guiCreates = row.guiCreates,
            uiWrites = row.uiWrites,
            layoutWrites = row.layoutWrites,
            relayouts = row.relayouts,
            budgetMS = row.budgetMS,
            overBudget = row.overBudget == true,
        }
    end
    for groupId, stages in pairs(operation.groups or {}) do
        copy.groups[groupId] = {}
        for stage, elapsed in pairs(stages) do
            copy.groups[groupId][stage] = elapsed
        end
    end
    for name, count in pairs(operation.guiCreateTypes or {}) do
        copy.guiCreateTypes[name] = count
    end
    for delayMS, sample in pairs(operation.tail or {}) do
        copy.tail[delayMS] = {
            state = sample.state,
            animationActive = sample.animationActive,
            timerPending = sample.timerPending,
            cpuMS = sample.cpuMS,
        }
    end
    return copy
end

function DesignerUI:GetDesignOperationStats(target)
    local snapshot = CopyOperationStats(
        self.designOperation or self.lastDesignOperation
    )
    if not snapshot then return nil end
    if type(target) ~= "table" then return snapshot end
    for key, value in pairs(snapshot) do target[key] = value end
    return target
end

function DesignerUI:GetDesignEnterState()
    return DESIGN_ENTER_STATES[self.designEnterState]
        and self.designEnterState or "closed"
end

function DesignerUI:EnsureEnteringSurface()
    if self.enteringSurface then return self.enteringSurface end
    if not (GUI2 and GUI2.CreatePanel and GUI2.CreateText
        and GUI2.Form and GUI2.Form.CreateButton) then
        local surface = {
            shown = false,
            label = { SetText = function(owner, text) owner.text = text end },
        }
        function surface:Show() self.shown = true end
        function surface:Hide() self.shown = false end
        function surface:IsShown() return self.shown == true end
        self.enteringSurface = surface
        return surface
    end
    local surface = GUI2:CreateFrame(UIParent, {
        mouse = false,
        hidden = true,
    })
    surface:SetAllPoints(UIParent)
    surface:SetFrameStrata("FULLSCREEN_DIALOG")
    surface:SetFrameLevel(680)
    surface:EnableMouse(false)
    local shade = GUI2:CreateTexture(surface, nil, "BACKGROUND")
    shade:SetAllPoints(surface)
    GUI2:SetTexturePaintKey(shade, "color.overlay.shadow")
    surface.shade = shade

    local bar = GUI2:CreatePanel(surface, {
        width = 620,
        height = 54,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    bar:SetPoint("TOP", UIParent, "TOP", 0, -18)
    bar:SetFrameLevel(681)
    local label = GUI2:CreateText(
        bar,
        T("designer.preparing", "正在准备设计模式"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    label:SetPoint("LEFT", bar, "LEFT", 18, 0)
    local cancel = GUI2.Form:CreateButton(bar, {
        text = T("designer.cancel", "取消"),
        width = 86,
        height = 30,
        tone = "default",
        onClick = function()
            if DesignerUI.designOperation then
                DesignerUI:AbortEnter("cancelled", true)
            else
                DesignerUI:CancelBusyOperation()
                DesignerUI.designEnterState = "closed"
                if DesignerUI.enteringSurface then
                    DesignerUI.enteringSurface:Hide()
                end
            end
        end,
    })
    cancel:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    surface.bar = bar
    surface.label = label
    surface.cancel = cancel
    self.enteringSurface = surface
    return surface
end

function DesignerUI:SetEnteringStatus(text)
    local surface = self:EnsureEnteringSurface()
    surface.label:SetText(text or T(
        "designer.preparing",
        "正在准备设计模式"
    ))
end

local function RestoreGUISliceGuards(operation)
    for index = #(operation.guiGuards or {}), 1, -1 do
        local guard = operation.guiGuards[index]
        if guard.container[guard.name] == guard.wrapper then
            guard.container[guard.name] = guard.original
        end
    end
    operation.guiGuards = {}
end

local function InstallGUISliceGuards(operation)
    if operation.guiGuards and #operation.guiGuards > 0 then return end
    operation.guiGuards = {}
    for _, container in ipairs({ GUI2, GUI2 and GUI2.Form }) do
        if type(container) == "table" then
            local names = {}
            for name, value in pairs(container) do
                if type(value) == "function" and name:match("^Create") then
                    names[#names + 1] = name
                end
            end
            table.sort(names)
            for index = 1, #names do
                local name = names[index]
                local original = container[name]
                local wrapper
                wrapper = function(owner, ...)
                    if operation.sliceStartedAt
                        and DesignerNowMS() - operation.sliceStartedAt
                            >= (DESIGN_GUI_SLICE_BUDGET_MS * 0.75) then
                        -- Large compound controls call nested GUI factories.
                        -- Yield before any nested factory once the current
                        -- callback nears budget; the complete Lua call stack is
                        -- resumed intact on the next frame. Shared entry points
                        -- are restored while the coroutine is paused.
                        RestoreGUISliceGuards(operation)
                        coroutine.yield("gui-slice-budget")
                        InstallGUISliceGuards(operation)
                    end
                    operation.guiCreates = (operation.guiCreates or 0) + 1
                    operation.sliceGUICreates =
                        (operation.sliceGUICreates or 0) + 1
                    operation.guiCreateTypes = operation.guiCreateTypes or {}
                    operation.guiCreateTypes[name] =
                        (operation.guiCreateTypes[name] or 0) + 1
                    operation.guiCallDepth =
                        (operation.guiCallDepth or 0) + 1
                    local result = original(owner, ...)
                    operation.guiCallDepth = math.max(
                        0,
                        (operation.guiCallDepth or 1) - 1
                    )
                    return result
                end
                container[name] = wrapper
                operation.guiGuards[#operation.guiGuards + 1] = {
                    container = container,
                    name = name,
                    original = original,
                    wrapper = wrapper,
                }
            end
        end
    end
end

local function ReadDesignerWrites()
    local values = YHUD.Stats and YHUD.Stats.values or {}
    return tonumber(values.viewWrites) or 0,
        tonumber(values.layoutWrites) or 0
end

local function ReadYUIAddonCPU()
    if type(_G.GetAddOnCPUUsage) ~= "function" then return nil end
    if type(_G.UpdateAddOnCPUUsage) == "function" then
        pcall(_G.UpdateAddOnCPUUsage)
    end
    local ok, value = pcall(_G.GetAddOnCPUUsage, "YUI")
    return ok and tonumber(value) or nil
end

local function IsDesignOperationCurrent(operation)
    if DesignerUI.designOperation ~= operation
        or DesignerUI.designEnterGeneration ~= operation.generation
        or operation.owner ~= DesignerUI
        or DESIGN_ENTER_STATES[operation.state] ~= true
        or operation.state == "closed"
        or operation.state == "aborting"
        or operation.state == "exiting" then
        return false, "stale-operation"
    end
    local session = Designer:GetSession()
    if session ~= operation.session or session.closed == true then
        return false, "stale-session"
    end
    if (tonumber(session.draft and session.draft.revision) or 0)
        ~= operation.draftRevision then
        return false, "stale-draft"
    end
    if session.setId ~= operation.setId
        or session.viewSpecKey ~= operation.specKey then
        return false, "stale-context"
    end
    if YHUD.GetCurrentSpecKey
        and operation.runtimeSpecKey
        and YHUD:GetCurrentSpecKey() ~= operation.runtimeSpecKey then
        return false, "specialization-changed"
    end
    if InCombat() then return false, "combat" end
    return true
end

local function RecordDesignerSlice(operation, elapsedMS, allocationKB)
    local viewWrites, layoutWrites = ReadDesignerWrites()
    local row = {
        stage = operation.stage,
        groupId = operation.groupId,
        elapsedMS = elapsedMS,
        allocationKB = allocationKB,
        guiCreates = operation.sliceGUICreates or 0,
        uiWrites = math.max(0, viewWrites - (operation.beforeViewWrites or 0)),
        layoutWrites = math.max(
            0,
            layoutWrites - (operation.beforeLayoutWrites or 0)
        ),
        relayouts = operation.sliceRelayouts or 0,
    }
    row.budgetMS = row.guiCreates > 0
        and DESIGN_GUI_SLICE_BUDGET_MS or DESIGN_SLICE_BUDGET_MS
    row.overBudget = elapsedMS > row.budgetMS
    if row.overBudget then
        operation.budgetViolations =
            (operation.budgetViolations or 0) + 1
    end
    operation.slices[#operation.slices + 1] = row
    operation.sliceCount = operation.sliceCount + 1
    operation.totalWorkMS = operation.totalWorkMS + elapsedMS
    operation.maxSliceMS = math.max(operation.maxSliceMS, elapsedMS)
    operation.uiWrites = operation.uiWrites + row.uiWrites
    operation.layoutWrites = operation.layoutWrites + row.layoutWrites
    operation.relayouts = operation.relayouts + row.relayouts
    if operation.groupId then
        local groupStats = operation.groups[operation.groupId] or {}
        operation.groups[operation.groupId] = groupStats
        groupStats[operation.stage] =
            (groupStats[operation.stage] or 0) + elapsedMS
    end
    if elapsedMS > operation.slowestStageMS then
        operation.slowestStageMS = elapsedMS
        operation.slowestStage = operation.stage
        operation.slowestGroupId = operation.groupId
    end
end

local ResumeDesignOperation

local function ScheduleDesignOperation(operation)
    if operation.timer then return false end
    local timerAPI = _G.C_Timer
    if not (timerAPI and timerAPI.NewTimer) then
        return ResumeDesignOperation(operation)
    end
    local delay = tonumber(operation.nextDelay) or 0
    operation.nextDelay = nil
    operation.timer = timerAPI.NewTimer(delay, function()
        operation.timer = nil
        ResumeDesignOperation(operation)
    end)
    return true
end

local function ScheduleTailSample(operation, delayMS, sampleAtMS)
    if YHUD.performanceDiagnosticsEnabled ~= true then return end
    local timerAPI = _G.C_Timer
    if not (timerAPI and timerAPI.NewTimer) then return end
    sampleAtMS = sampleAtMS or delayMS
    operation.tailTimer = timerAPI.NewTimer(delayMS / 1000, function()
        operation.tailTimer = nil
        local latest = DesignerUI.lastDesignOperation
        if latest ~= operation then return end
        operation.tailCallbacks = (operation.tailCallbacks or 0) + 1
        operation.tail = operation.tail or {}
        operation.tail[sampleAtMS] = {
            state = DesignerUI:GetDesignEnterState(),
            animationActive = operation.animationActive or 0,
            timerPending = operation.timer ~= nil,
            cpuMS = ReadYUIAddonCPU(),
        }
        if sampleAtMS == 250 then
            ScheduleTailSample(operation, 250, 500)
        elseif sampleAtMS == 500 then
            ScheduleTailSample(operation, 500, 1000)
        end
    end)
end

local function CancelDesignOperationTimers(operation)
    if type(operation) ~= "table" then return end
    for _, timer in ipairs({ operation.timer, operation.tailTimer }) do
        if timer and timer.Cancel then timer:Cancel() end
    end
    operation.timer = nil
    operation.tailTimer = nil
end

local function FinishDesignOperation(operation)
    RestoreGUISliceGuards(operation)
    operation.state = "active"
    operation.completed = true
    operation.inspectorReadyMS = operation.inspectorReadyMS
        or (DesignerNowMS() - operation.startedAt)
    operation.totalElapsedMS = DesignerNowMS() - operation.startedAt
    DesignerUI.designEnterState = "active"
    DesignerUI.lastDesignOperation = operation
    DesignerUI.designOperation = nil
    DesignerUI:SetBusyInteractionBlocked(false)
    if DesignerUI.enteringSurface then
        DesignerUI.enteringSurface:Hide()
    end
    ScheduleTailSample(operation, 250)
end

ResumeDesignOperation = function(operation)
    local current, reason = IsDesignOperationCurrent(operation)
    if not current then
        return DesignerUI:AbortEnter(reason, false)
    end
    operation.sliceStartedAt = DesignerNowMS()
    local memoryBefore = DesignerMemoryKB()
    operation.sliceGUICreates = 0
    operation.sliceRelayouts = 0
    operation.beforeViewWrites, operation.beforeLayoutWrites =
        ReadDesignerWrites()
    local ok, result
    local stepCount = 0
    repeat
        ok, result = coroutine.resume(operation.thread)
        stepCount = stepCount + 1
        if not ok or coroutine.status(operation.thread) == "dead" then
            break
        end
        -- A zero-delay timer resumes on a later rendered frame. Resuming once
        -- per tiny projection item made a 70+ item operation take more than a
        -- second even though the measured work was small. Drain cheap steps in
        -- the current callback while keeping headroom below the hard budget.
        local elapsed = DesignerNowMS() - operation.sliceStartedAt
        local budget = (operation.sliceGUICreates or 0) > 0
            and DESIGN_GUI_SLICE_BUDGET_MS or DESIGN_SLICE_BUDGET_MS
        if operation.forceNextFrame == true
            or (tonumber(operation.nextDelay) or 0) > 0
            or stepCount >= DESIGN_MAX_STEPS_PER_SLICE
            or elapsed >= (budget * 0.75) then
            break
        end
    until false
    operation.forceNextFrame = nil
    RestoreGUISliceGuards(operation)
    local elapsedMS = DesignerNowMS() - operation.sliceStartedAt
    RecordDesignerSlice(
        operation,
        elapsedMS,
        DesignerMemoryKB() - memoryBefore
    )
    if not ok then
        return DesignerUI:AbortEnter("stage-error:" .. tostring(result), false)
    end
    if coroutine.status(operation.thread) == "dead" then
        return FinishDesignOperation(operation)
    end
    return ScheduleDesignOperation(operation)
end

local function OrderedDesignGroups(profile, selectedGroupId)
    local result = {}
    local seen = {}
    if type(selectedGroupId) == "string" and selectedGroupId ~= "" then
        result[#result + 1] = selectedGroupId
        seen[selectedGroupId] = true
    end
    local groups = profile and profile.groups or {}
    for index = 1, #(groups.order or {}) do
        local groupId = groups.order[index]
        if not seen[groupId] and groups.items and groups.items[groupId] then
            result[#result + 1] = groupId
            seen[groupId] = true
        end
    end
    for groupId in pairs(groups.items or {}) do
        if not seen[groupId] then result[#result + 1] = groupId end
    end
    return result
end

local function ShowPreparedWorkspace(self, operation)
    if self.RegisterSpecializationToolbarEvents then
        self:RegisterSpecializationToolbarEvents()
    end
    if self.RefreshSpecializationToolbar then
        self:RefreshSpecializationToolbar()
    end
    -- The entering shade and the final dimmer use the same paint. Switch them
    -- in one presentation step so they never stack or expose a bright frame.
    if self.enteringSurface then self.enteringSurface:Hide() end
    if self.dimmer then self.dimmer:Show() end
    if self.toolbar then self.toolbar:Show() end
    if self.EnsureModeSwitcher then
        local switcher = self:EnsureModeSwitcher()
        if switcher then switcher:Show() end
    end
    local session = operation.session
    if self.panel then self.panel:Hide() end
    if self.panel and session.selectedGroupId then
        self.panel:Show()
        self:PositionInspector(false)
        if GUI2.SlideIn then
            GUI2:SlideIn(self.panel, {
                owner = operation,
                from = self.inspectorSide == "left" and "left" or "right",
                distance = 20,
                duration = DESIGN_GROUP_FADE_SECONDS,
                key = "yhud-design-inspector",
            })
        elseif GUI2.FadeIn then
            GUI2:FadeIn(self.panel, {
                owner = operation,
                from = 0,
                to = 1,
                duration = DESIGN_GROUP_FADE_SECONDS,
                key = "yhud-design-inspector",
            })
        end
    end
    if self.SyncDesignerModePresentation then
        self:SyncDesignerModePresentation()
    end
end

function DesignerUI:AbortEnter(reason, userCancelled)
    local operation = self.designOperation
    if not operation then
        if self:GetDesignEnterState() == "active" and userCancelled == true then
            return self:CancelAndClose()
        end
        return false
    end
    self.designEnterGeneration =
        (tonumber(self.designEnterGeneration) or 0) + 1
    self.designEnterState = "aborting"
    operation.state = "aborting"
    operation.abortedReason = reason or "aborted"
    RestoreGUISliceGuards(operation)
    CancelDesignOperationTimers(operation)
    local Animation = YUI.Animation
    if Animation and Animation.StopOwner then
        Animation:StopOwner(operation, false)
    end
    operation.animationActive = 0
    operation.animationStoppedAt = DesignerNowMS()
    if self.AbortStagedInspectorRefresh then
        self:AbortStagedInspectorRefresh()
    end

    local View = YHUD.View
    if View then
        if View.ClearDesignResourceValuePreview then
            View:ClearDesignResourceValuePreview()
        end
        if View.AbortStagedDesignMode then
            View:AbortStagedDesignMode()
        end
        if View.SetPreview then View:SetPreview(false, true) end
    end
    if operation.runtimeMutated == true then
        self.previewRuntimeDirty = true
        self:RestoreRuntimeView("designer-enter-abort", false)
    end
    if self.HideWorkspace and self.panel then self:HideWorkspace() end
    if self.enteringSurface then self.enteringSurface:Hide() end
    self:SetBusyInteractionBlocked(false)
    self.active = false

    local session = Designer:GetSession()
    local edited = session and session.draft
        and session.draft.changed == true
    local keepDraft = edited and operation.interactive == true
        and userCancelled ~= true
        and reason ~= "combat"
        and reason ~= "specialization-changed"
        and reason ~= "stale-context"
    if session and not keepDraft and type(Designer.Cancel) == "function" then
        Designer:Cancel()
    end
    operation.completed = false
    operation.totalElapsedMS = DesignerNowMS() - operation.startedAt
    self.lastDesignOperation = operation
    self.designOperation = nil
    self.designEnterState = "closed"
    return true
end

function DesignerUI:StartStagedEnter(session, source)
    if type(session) ~= "table" or session.closed == true then
        return nil, "designer-not-open"
    end
    if self.designOperation then
        return self.designOperation
    end
    CancelDesignOperationTimers(self.lastDesignOperation)
    self.designEnterGeneration =
        (tonumber(self.designEnterGeneration) or 0) + 1
    local generation = self.designEnterGeneration
    local startedAt = DesignerNowMS()
    local operation = {
        id = "designer-" .. tostring(generation)
            .. "-" .. tostring(math.floor(startedAt)),
        generation = generation,
        owner = self,
        session = session,
        draftRevision = tonumber(session.draft and session.draft.revision) or 0,
        setId = session.setId,
        specKey = session.viewSpecKey,
        runtimeSpecKey = session.runtimeSpecKey,
        state = "preparing",
        startedAt = startedAt,
        totalWorkMS = 0,
        maxSliceMS = 0,
        slowestStageMS = 0,
        sliceCount = 0,
        guiCreates = 0,
        uiWrites = 0,
        layoutWrites = 0,
        relayouts = 0,
        slices = {},
        groups = {},
        budgetViolations = 0,
        cpuBeforeMS = ReadYUIAddonCPU(),
    }
    operation.cpuClickMS = operation.cpuBeforeMS
    self.designOperation = operation
    self.designEnterState = "preparing"
    self.source = source
    self.active = true
    self.toolbarResetPending = true
    self.manualPanel = false
    self.previewRuntimeDirty = false
    self.inspectorSection = "group"
    local entering = self:EnsureEnteringSurface()
    entering:Show()
    self:SetEnteringStatus(T(
        "designer.preparing",
        "正在准备设计模式"
    ))

    operation.thread = coroutine.create(function()
        operation.stage = "draft-snapshot"
        local bridge = YHUD.LayoutBridge
        local runtimeProfile = GetActiveRuntimeProfile()
        self.runtimeLayoutSnapshot = bridge and bridge.CapturePlacements
            and bridge:CapturePlacements(runtimeProfile) or nil
        operation.forceNextFrame = true
        coroutine.yield("snapshot-ready")

        local profile = Designer.GetPresentationProfile
            and Designer:GetPresentationProfile() or Designer:GetProfile()
        local View = YHUD.View
        if not (profile and View) then error("preview-unavailable") end
        operation.stage = "projection-context"
        local projectionContext
        local runtimeContext = View.layoutProjectionContext
        if session.runtimeEquivalent == true
            and type(runtimeContext) == "table"
            and type(runtimeContext.claimedCooldownSources) == "table" then
            projectionContext = {
                profile = profile,
                preview = true,
                claimedCooldownSources = runtimeContext.claimedCooldownSources,
            }
        else
            projectionContext = YHUD.BuildMonitorLayoutProjectionContext
                and YHUD:BuildMonitorLayoutProjectionContext(profile, true) or nil
        end
        operation.projectionContext = projectionContext
        operation.forceNextFrame = true
        coroutine.yield("projection-context-ready")

        operation.stage = "base-handoff"
        if not View.PrepareStagedDesignMode
            or not View:PrepareStagedDesignMode(
                profile,
                projectionContext,
                session.selectedGroupId,
                SelectDesignGroup,
                AddDesignMonitor,
                SelectedDesignMonitorId(session),
                SelectDesignMonitor,
                ReorderDesignMonitor,
                BeginDesignGroupDrag,
                EndDesignGroupDrag
            ) then
            error("design-stage-unavailable")
        end
        coroutine.yield("base-ready")

        operation.state = "entering-groups"
        self.designEnterState = "entering-groups"
        local groupOrder = OrderedDesignGroups(profile, session.selectedGroupId)
        for index = 1, #groupOrder do
            local groupId = groupOrder[index]
            operation.groupId = groupId
            operation.stage = "group-projection"
            if View.BeginStagedDesignGroupBuild then
                local groupRuntime = View:BeginStagedDesignGroupBuild(groupId)
                if groupRuntime and groupRuntime.view == "resource" then
                    operation.forceNextFrame = true
                end
                coroutine.yield("group-projection-ready")
            end
            if View.BuildStagedDesignGroupSlice then
                local complete = false
                while not complete do
                    operation.stage = "group-slot"
                    local builtRuntime, builtCount, slotStage
                    complete, builtRuntime, builtCount, slotStage =
                        View:BuildStagedDesignGroupSlice(groupId, 1)
                    if not complete and not builtRuntime then
                        error("design-group-unavailable:" .. tostring(groupId)
                            .. ":" .. tostring(slotStage))
                    end
                    if slotStage then
                        operation.stage = "group-slot-" .. tostring(slotStage)
                    end
                    coroutine.yield("group-slot-ready")
                end
            end
            operation.stage = "group-presentation"
            local relayoutBefore = YHUD.Stats and YHUD.Stats.layoutPasses or 0
            View:EnterStagedDesignGroup(
                groupId,
                operation
            )
            local relayoutAfter = YHUD.Stats and YHUD.Stats.layoutPasses or relayoutBefore
            operation.sliceRelayouts = math.max(
                0,
                (tonumber(relayoutAfter) or 0) - (tonumber(relayoutBefore) or 0)
            )
            if index == 1 then
                operation.interactive = true
                operation.interactiveMS = DesignerNowMS() - operation.startedAt
            end
            operation.nextDelay = index < #groupOrder
                and DESIGN_GROUP_STAGGER_SECONDS or nil
            coroutine.yield("group-ready")
        end
        operation.groupId = nil
        operation.allMoversReadyMS = DesignerNowMS() - operation.startedAt

        operation.state = "entering-inspector"
        self.designEnterState = "entering-inspector"
        operation.stage = "inspector-shell"
        InstallGUISliceGuards(operation)
        local ready, code = self.EnsureUIShell
            and self:EnsureUIShell() or self:EnsureUI()
        RestoreGUISliceGuards(operation)
        if not ready then error(code or "designer-ui-unavailable") end
        self:SetBusyInteractionBlocked(true)
        coroutine.yield("inspector-shell-ready")

        operation.stage = "inspector-current-page"
        InstallGUISliceGuards(operation)
        ready, code = self.EnsureUICurrentPage
            and self:EnsureUICurrentPage() or self:EnsureUI()
        RestoreGUISliceGuards(operation)
        if not ready then error(code or "designer-ui-unavailable") end
        coroutine.yield("inspector-page-ready")

        if self.BeginStagedInspectorRefresh then
            operation.stage = "inspector-refresh-base"
            ready, code = self:BeginStagedInspectorRefresh(false, false)
            if not ready then error(code or "designer-refresh-unavailable") end
            operation.forceNextFrame = true
            coroutine.yield("inspector-refresh-base-ready")

            operation.stage = "inspector-refresh-header"
            ready, code = self:SyncStagedInspectorHeader()
            if not ready then error(code or "designer-refresh-unavailable") end
            operation.forceNextFrame = true
            coroutine.yield("inspector-refresh-header-ready")

            operation.stage = "inspector-refresh-notice"
            ready, code = self:SyncStagedInspectorNotice()
            if not ready then error(code or "designer-refresh-unavailable") end
            operation.forceNextFrame = true
            coroutine.yield("inspector-refresh-notice-ready")

            operation.stage = "inspector-refresh-layout"
            ready, code = self:LayoutStagedInspectorRefresh()
            if not ready then error(code or "designer-refresh-unavailable") end
            operation.forceNextFrame = true
            coroutine.yield("inspector-refresh-layout-ready")

            operation.stage = "inspector-refresh-finalize"
            ready, code = self:FinishStagedInspectorRefresh()
            if not ready then error(code or "designer-refresh-unavailable") end
            coroutine.yield("inspector-refresh-finalized")
        else
            operation.stage = "inspector-refresh"
            if self.Refresh then self:Refresh(false, false) end
            coroutine.yield("inspector-refresh-ready")
        end

        operation.stage = "inspector-present"
        ShowPreparedWorkspace(self, operation)
        operation.inspectorReadyMS = DesignerNowMS() - operation.startedAt
        coroutine.yield("inspector-presented")

        operation.stage = "design-finalize"
        if View.FinishStagedDesignMode then
            View:FinishStagedDesignMode()
        end
        if View.SetDesignerSkyridingState then
            View:SetDesignerSkyridingState(false)
        end
        if View.ProjectAllGroupVisibility then
            View:ProjectAllGroupVisibility()
        end
        coroutine.yield("design-finalized")

        operation.stage = "layout-snapshot"
        self:CaptureLayoutSnapshot()
    end)
    ScheduleDesignOperation(operation)
    return operation
end

local function ExitViewDesignMode(View, suppressRelayout)
    if not View then return false end
    if View.PrepareDesignMode and View.RefreshDesignModePresentation then
        local prepared, wasEnabled = View:PrepareDesignMode(false)
        if prepared then
            return View:RefreshDesignModePresentation(
                false,
                wasEnabled,
                suppressRelayout == true
            )
        end
    end
    return View.SetDesignMode and View:SetDesignMode(false) or false
end

function DesignerUI:ApplyPreview()
    local profile = Designer.GetPresentationProfile
        and Designer:GetPresentationProfile() or Designer:GetProfile()
    local session = Designer:GetSession()
    local View = YHUD.View
    if not (profile and session and View) then return false end
    if not View.designMode then
        local _, prepared = PrepareViewDesignMode(View, session)
        if prepared ~= true then return false end
    end
    local projectionContext = YHUD.BuildMonitorLayoutProjectionContext
        and YHUD:BuildMonitorLayoutProjectionContext(profile, true) or nil
    if not (View.RefreshDesignProjection
        and View:RefreshDesignProjection(profile, projectionContext)) then
        return false
    end
    session.previewRuntimeDirty = false
    session.previewRuntimeRevision = nil
    self.previewRuntimeDirty = false
    local skyridingMode = self.designerMode == "skyriding"
    if View.SetDesignerSkyridingState then
        View:SetDesignerSkyridingState(skyridingMode)
    end
    if YHUD.Skyriding and YHUD.Skyriding.ApplySettings then
        YHUD.Skyriding:ApplySettings(profile)
    end
    if YHUD.Skyriding and YHUD.Skyriding.SetDesignerPreview then
        YHUD.Skyriding:SetDesignerPreview(skyridingMode)
    end
    return true
end

function DesignerUI:RefreshAfterStructuralMutation(animate)
    local session = Designer:GetSession()
    if session then session.previewRuntimeRebuildRequired = true end
    if not self:ApplyPreview() then return false end
    return self:Refresh(animate == true, false)
end

function DesignerUI:RefreshSelectionPreview()
    local profile = Designer.GetPresentationProfile
        and Designer:GetPresentationProfile() or Designer:GetProfile()
    local session = Designer:GetSession()
    local View = YHUD.View
    if not (profile and session and View and View.active) then return false end

    if View.SetDesignSelection then
        View:SetDesignSelection(
            session.selectedGroupId,
            SelectedDesignMonitorId(session)
        )
    end
    return true
end

GetActiveRuntimeProfile = function()
    local canonical = YHUD.GetConfigProfile and YHUD:GetConfigProfile()
    if not canonical then return nil end
    if YHUD.GetRuntimeProfileForCurrentContext then
        return YHUD:GetRuntimeProfileForCurrentContext(canonical, true)
    end
    local specKey = YHUD.GetCurrentSpecKey and YHUD:GetCurrentSpecKey()
    if not (specKey and YHUD.GetRuntimeProfile) then return nil end
    return YHUD:GetRuntimeProfile(canonical, specKey, true)
end

function DesignerUI:RestoreRuntimeView(reason, runtimeAlreadyApplied)
    local View = YHUD.View
    ExitViewDesignMode(View, true)
    if View then View:SetPreview(false, true) end
    if View and View.ClearDesignResourceValuePreview then
        View:ClearDesignResourceValuePreview()
    end

    if self.previewOwnsView and not YHUD:IsEnabled() then
        if View then View:Disable() end
    elseif runtimeAlreadyApplied ~= true
        and self.previewRuntimeDirty ~= true then
        -- Independent design projections never mutate the live View. Exiting
        -- only releases the projection; Sources, Native and secret values keep
        -- running underneath and need no synthetic restore pass.
    elseif runtimeAlreadyApplied == true then
        local profile = GetActiveRuntimeProfile()
        if View and View.active and profile then
            -- ConfigSets may already have coordinated Sources and NativeBridge,
            -- but the View was still projected with preview/bypass enabled.
            -- Always rebuild the final runtime projection after those flags
            -- are cleared so synthetic previews and visibility state converge.
            View:ApplyConfig(profile)
            local LayoutBridge = YHUD.LayoutBridge
            if LayoutBridge and LayoutBridge.Sync then
                LayoutBridge:Sync(profile)
            end
            local NativeBridge = YHUD.NativeBridge
            if NativeBridge and NativeBridge.active then
                if NativeBridge.RestorePresentationAlpha then
                    NativeBridge:RestorePresentationAlpha()
                end
                NativeBridge:Sync(profile, reason or "designer-close")
            end
            local Sources = YHUD.Sources
            if Sources and Sources.active then
                -- Official Aura duration objects are transient: the source
                -- dispatcher clears them after delivery. Closing design mode
                -- clears the synthetic timer after ConfigSets has already
                -- coordinated Sources, so replay once at the final runtime
                -- boundary to bind the real timer or release an inactive bar.
                Sources:Refresh(reason or "designer-close", true)
            end
            if View.ProjectAllGroupVisibility then
                View:ProjectAllGroupVisibility()
            end
        else
            YHUD:Refresh(reason or "designer-close")
        end
    else
        local profile = GetActiveRuntimeProfile()
        if View and View.active and profile then
            View:ApplyConfig(profile)
            local LayoutBridge = YHUD.LayoutBridge
            if LayoutBridge and LayoutBridge.Sync then
                LayoutBridge:Sync(profile)
            end
            local NativeBridge = YHUD.NativeBridge
            if NativeBridge and NativeBridge.active then
                if NativeBridge.RestorePresentationAlpha then
                    NativeBridge:RestorePresentationAlpha()
                end
                NativeBridge:Sync(profile, reason or "designer-close")
            end
            local Sources = YHUD.Sources
            if Sources and Sources.active then
                Sources:ApplyConfig(profile)
                Sources:Refresh(reason or "designer-close", true)
            end
            if View.ProjectAllGroupVisibility then
                View:ProjectAllGroupVisibility()
            end
        else
            YHUD:Refresh(reason or "designer-close")
        end
    end
    self.previewOwnsView = false
    self.previewRuntimeDirty = false
    return true
end

function DesignerUI:HideWorkspace()
    local soundPicker = GUI2 and GUI2.SoundPicker
    if soundPicker and soundPicker.Close then soundPicker:Close() end
    self:HideMonitorPicker()
    self:HideGlowEditor()
    if self.visibilityRuleEditor
        and self.visibilityRuleEditor.ClosePanel then
        self.visibilityRuleEditor:ClosePanel()
    end
    if self.toolbar then self.toolbar:Hide() end
    if self.modeSwitcher then self.modeSwitcher:Hide() end
    if self.skyridingSettingsPanel then
        self.skyridingSettingsPanel:Hide()
    end
    if YHUD.Skyriding and YHUD.Skyriding.SetDesignerPreview then
        YHUD.Skyriding:SetDesignerPreview(false)
    end
    if YHUD.View and YHUD.View.SetDesignerSkyridingState then
        YHUD.View:SetDesignerSkyridingState(false)
    end
    if YHUD.View and YHUD.View.SetDesignerSurfaceVisible then
        YHUD.View:SetDesignerSurfaceVisible(true)
    end
    if self.panel then self.panel:Hide() end
    if self.dimmer then self.dimmer:Hide() end
    self:HideSwitchDialog()
    self:HideCancelDialog()
    self:HideNewGroupDialog()
    if self.HideReplicationDialog then self:HideReplicationDialog() end
    if self.HideSpecializationPicker then self:HideSpecializationPicker() end
    if self.UnregisterSpecializationToolbarEvents then
        self:UnregisterSpecializationToolbarEvents()
    end
end

function DesignerUI:ShowWorkspace()
    if self.RegisterSpecializationToolbarEvents then
        self:RegisterSpecializationToolbarEvents()
    end
    if self.RefreshSpecializationToolbar then
        self:RefreshSpecializationToolbar()
    end
    self.dimmer:Show()
    self.toolbar:Show()
    if self.EnsureModeSwitcher then
        local switcher = self:EnsureModeSwitcher()
        if switcher then switcher:Show() end
    end
    local session = Designer:GetSession()
    if session and session.selectedGroupId then
        self.panel:Show()
        self:Refresh(false)
    else
        self.panel:Hide()
    end
    if self.SyncDesignerModePresentation then
        self:SyncDesignerModePresentation()
    end
end

function DesignerUI:HandleEscape()
    if self.busyKind then
        if self.busyCancelable == true then self:CancelBusyOperation() end
        return true
    end
    if not self.active then return false end
    local specPanel = S.Elements and S.Elements.specMultiSelectPanel
    if specPanel and specPanel:IsShown() then
        S:CloseSpecMultiSelectDropdown(nil, "escape")
        return true
    end
    if S.SoundCenter and S.SoundCenter.HandleDesignerEscape and S.SoundCenter:HandleDesignerEscape() then return true end
    local configPicker = S.ConfigSetPicker
    if configPicker and configPicker:IsOpen() then
        local copy = S.CopyFrame
        if copy and copy:IsShown() then copy:Hide(); return true end
        local transfer = S.ConfigTransferDialog
        if transfer and transfer:IsShown() and transfer.options
            and transfer.options.layoutOwner == configPicker.panel then
            if transfer.importState ~= "committing" then transfer:Hide() end
            return true
        end
        if configPicker.activeUnifiedModal and configPicker.activeUnifiedModal:IsShown() then
            configPicker:HideUnifiedModal(configPicker.activeUnifiedModal)
        else
            configPicker:Close()
        end
        return true
    end
    if self.libraryImportActive then
        if S.reviewPanel and S.reviewPanel:IsShown() then S.reviewPanel:Hide()
        elseif S.ConfigTransferDialog then S.ConfigTransferDialog:Hide() end
        return true
    end
    if self.schemePicker and self.schemePicker:IsShown() then self:HideSchemePicker(); return true end
    if self.recommendedLibrary and self.recommendedLibrary:IsShown() then self.recommendedLibrary:Hide(); return true end
    local confirm = S and S.ConfirmFrame
    if confirm and confirm.confirmOwner == self and confirm:IsShown() then
        self:HideMonitorDeleteConfirm()
        return true
    end
    if self.replicationDialog and self.replicationDialog:IsShown() then
        self:HideReplicationDialog()
        return true
    end
    if self.specializationPicker and self.specializationPicker:IsShown() then
        self:HideSpecializationPicker()
        return true
    end
    if self.cancelDialog and self.cancelDialog:IsShown() then
        return self:ResolveCancelClose("cancel")
    end
    if self.switchDialog and self.switchDialog:IsShown() then
        return self:ResolveSwitch("cancel")
    end
    if self.newGroupDialog and self.newGroupDialog:IsShown() then
        self:HideNewGroupDialog()
        return true
    end
    if self.monitorPicker and self.monitorPicker:IsShown() then
        self:HideMonitorPicker()
        return true
    end
    if self.glowEditor and self.glowEditor:IsShown() then
        self:HideGlowEditor()
        return true
    end
    if self.panel and self.panel:IsShown() then
        return self:CloseInspector()
    end
    return self:RequestCancelClose()
end

function DesignerUI:CloseInspector()
    self:HideMonitorPicker()
    self:HideGlowEditor()
    if self.visibilityRuleEditor
        and self.visibilityRuleEditor.ClosePanel then
        self.visibilityRuleEditor:ClosePanel()
    end
    if self.StopResourceValuePreview then
        self:StopResourceValuePreview(true, true)
    end
    if self.SyncDesignCooldownTextPreview then
        self:SyncDesignCooldownTextPreview(false)
    end
    local cleared = Designer:ClearSelection()
    if not cleared then return false end
    self.inspectorSection = "group"
    self.manualPanel = false
    if self.panel then self.panel:Hide() end
    local View = YHUD.View
    if View and View.SetDesignSelection then
        View:SetDesignSelection(nil, nil)
    end
    return true
end

function DesignerUI:ClearLayoutListener()
    if self.layoutListener and YUI.Event and YUI.Event.Off then
        YUI.Event:Off(self.layoutListener)
    end
    self.layoutListener = nil
end

function DesignerUI:OpenLayoutMode()
    if InCombat() then
        self:SetStatus(T("designer.error_combat", "战斗中不能进入位置设置。"))
        return false
    end
    if not YHUD:IsEnabled() then
        self:SetStatus(T("designer.error_layout_disabled", "请先启用冷却监控，再设置位置。"))
        return false
    end
    if not (YUI.Event and YUI.Event.Once and YHUD.LayoutBridge) then
        self:SetStatus(T("designer.error_layout", "位置设置当前不可用。"))
        return false
    end

    self:ClearLayoutListener()
    ExitViewDesignMode(YHUD.View, true)
    local profile = Designer:GetProfile()
    if profile and YHUD.LayoutBridge.Sync then
        YHUD.LayoutBridge:Sync(profile)
    end
    self:HideWorkspace()
    self.layoutListener = YUI.Event:Once(
        "YUI_LAYOUT_EDIT_MODE_CLOSED",
        function()
            DesignerUI.layoutListener = nil
            if not Designer:IsOpen() then return end
            DesignerUI.active = true
            DesignerUI:ShowWorkspace()
            DesignerUI:ApplyPreview()
        end,
        self,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD:DesignerLayoutReturn",
        }
    )
    local opened = YHUD.LayoutBridge:Open("yhud-content")
    if not opened then
        self:ClearLayoutListener()
        self:ShowWorkspace()
        self:ApplyPreview()
        self:SetStatus(T("designer.error_layout", "位置设置当前不可用。"))
        return false
    end
    return true
end

function DesignerUI:FinishClose(reason, reopenSettings, runtimeAlreadyApplied)
    self.designEnterState = "exiting"
    CancelDesignOperationTimers(self.lastDesignOperation)
    local Animation = YUI.Animation
    if Animation and Animation.StopOwner and self.lastDesignOperation then
        Animation:StopOwner(self.lastDesignOperation, false)
        self.lastDesignOperation.animationActive = 0
        self.lastDesignOperation.animationStoppedAt = DesignerNowMS()
    end
    self:ClearBusyOperation()
    self.active = false
    self.saving = false
    if self.finishButton and self.finishButton.SetDisabled then
        self.finishButton:SetDisabled(false)
    end
    self.inspectorSuppressedByGroupDrag = false
    self.restoreInspectorAfterGroupDrag = nil
    self:ClearRestoreConfirm(true)
    self:HideCancelDialog()
    self:ClearLayoutListener()
    self:HideWorkspace()
    self:RestoreRuntimeView(reason, runtimeAlreadyApplied)
    self.layoutSnapshot = nil
    self.runtimeLayoutSnapshot = nil
    self.designerMode = "cooldown"
    local shouldReopen = reopenSettings and self.source == "settings"
    self.source = nil
    self.manualPanel = false
    self.designEnterState = "closed"
    if shouldReopen and S.OpenProduct then
        S:OpenProduct(YHUD.PRODUCT_ID, YHUD.SETTINGS_ENTRY)
    end
end

function DesignerUI:CaptureLayoutSnapshot()
    local bridge = YHUD.LayoutBridge
    self.layoutSnapshot = bridge and bridge.CapturePlacements
        and bridge:CapturePlacements(Designer:GetProfile())
        or {}
    if self.runtimeLayoutSnapshot == nil then
        self.runtimeLayoutSnapshot = self.layoutSnapshot
    end
    return self.layoutSnapshot
end

function DesignerUI:CaptureDraftPlacements()
    local bridge = YHUD.LayoutBridge
    local profile = Designer:GetProfile()
    if not (bridge and bridge.CaptureProfilePlacements and profile) then
        return true
    end
    local placements, code = bridge:CaptureProfilePlacements(profile)
    if not placements then return nil, code or "placement-capture-failed" end
    return Designer:SetGroupPlacements(placements)
end

function DesignerUI:RestoreLayoutSnapshot()
    local bridge = YHUD.LayoutBridge
    if bridge and bridge.RestorePlacements then
        return bridge:RestorePlacements(self.layoutSnapshot)
    end
    return false
end

function DesignerUI:RestoreRuntimeLayoutSnapshot()
    local bridge = YHUD.LayoutBridge
    if bridge and bridge.RestorePlacements then
        return bridge:RestorePlacements(
            self.runtimeLayoutSnapshot or self.layoutSnapshot
        )
    end
    return false
end

function DesignerUI:IsSessionDirty()
    -- Position changes become Draft changes through LayoutBridge's
    -- onPlacementCommitted callback. Comparing the shared Layout registry here
    -- also observes unrelated reapplication/normalization and can therefore
    -- turn an untouched Designer session dirty.
    return Designer:IsDirty() == true
end

function DesignerUI:GetActiveConfigurationName()
    local rows = Catalog:List()
    if type(rows) ~= "table" then return nil end
    for index = 1, #rows do
        local row = rows[index]
        if row.active == true and row.set then
            return row.set.name or row.set.id
        end
    end
    return nil
end

function DesignerUI:ShowRestoredConfigurationToast(name)
    if type(name) ~= "string" or name == "" then return false end
    if not (GUI2 and GUI2.Overlay and GUI2.Overlay.CreateToast
        and UIParent) then
        return false
    end
    if self.restoredConfigurationToastTimer
        and self.restoredConfigurationToastTimer.Cancel then
        self.restoredConfigurationToastTimer:Cancel()
    end
    self.restoredConfigurationToastTimer = nil
    if self.restoredConfigurationToast
        and self.restoredConfigurationToast.Hide then
        self.restoredConfigurationToast:Hide()
    end
    local toast = GUI2.Overlay:CreateToast(UIParent, {
        width = 430,
        title = T(
            "designer.saved_restored_title",
            "保存成功，已恢复到当前配置"
        ),
        body = string.format(
            T("designer.saved_restored_body", "「%s」"),
            name
        ),
    })
    toast:SetFrameStrata("TOOLTIP")
    toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
    self.restoredConfigurationToast = toast
    if C_Timer and C_Timer.NewTimer then
        local timer
        timer = C_Timer.NewTimer(3, function()
            if DesignerUI.restoredConfigurationToastTimer ~= timer
                or DesignerUI.restoredConfigurationToast ~= toast then
                return
            end
            toast:Hide()
            DesignerUI.restoredConfigurationToast = nil
            DesignerUI.restoredConfigurationToastTimer = nil
        end)
        self.restoredConfigurationToastTimer = timer
    end
    return true
end

local function GetSavedNativeCategoryPlan(result)
    local serviceResult = type(result) == "table" and result.applyResult or nil
    local applyResult = type(serviceResult) == "table"
        and serviceResult.result or nil
    return type(applyResult) == "table"
        and applyResult.nativeCategoryPlan or nil
end

function DesignerUI:ContinueNativeCategorySave(request)
    if type(request) ~= "table" then return false end
    if InCombat() then
        local message = T(
            "designer.native_category_reload.combat",
            "战斗中无法同步，请脱战后重试。"
        )
        self:SetStatus(message)
        Print(message)
        return false
    end
    local session = Designer:GetSession()
    local revision = session and session.draft
        and (tonumber(session.draft.revision) or 0) or nil
    if request.session and (
        session ~= request.session
        or revision ~= request.revision
        or session.runtimeSpecKey ~= request.specKey
    ) then
        return self:SaveAndClose()
    end
    return self:SaveAndClose({
        nativeCategoryReloadApproved = true,
        nativeCategoryPlan = request.plan,
        nativeCategoryReport = request.report,
        placementsCaptured = true,
        expectedSession = session,
        expectedRevision = revision,
        expectedSpecKey = session and session.runtimeSpecKey or nil,
    })
end

function DesignerUI:ShowNativeCategoryReloadPrompt(request)
    if type(request) ~= "table" then return false end
    if not (S and type(S.ShowConfirmPopup) == "function") then
        return false
    end
    local automatic = request.automatic == true
    local token = {}
    self.nativeCategoryReloadConfirmToken = token
    local function ClearToken()
        if DesignerUI.nativeCategoryReloadConfirmToken == token then
            DesignerUI.nativeCategoryReloadConfirmToken = nil
        end
    end
    local function Accept()
        if DesignerUI.nativeCategoryReloadConfirmToken ~= token then return end
        ClearToken()
        if InCombat() then
            local message = T(
                "designer.native_category_reload.combat",
                "战斗中无法同步，请脱战后重试。"
            )
            DesignerUI:SetStatus(message)
            Print(message)
            return
        end
        if automatic then
            local configSets = YHUD.ConfigSets
            local result, code = configSets
                and configSets.ApplyPendingNativeCategoryReload
                and configSets:ApplyPendingNativeCategoryReload(request)
            if type(result) == "table" and result.reloadPending == true then
                return DesignerUI:ShowNativeCategoryReloadNowPrompt(result)
            end
            if not result and code then
                local key = code == "combat-lockdown"
                    and "designer.native_category_reload.combat"
                    or "designer.native_category_reload.failed"
                local fallback = code == "combat-lockdown"
                    and "战斗中无法同步，请脱战后重试。"
                    or "同步暴雪冷却设置失败，已恢复原配置。"
                local message = T(key, fallback)
                DesignerUI:SetStatus(message)
                Print(message)
            end
            return
        end
        return DesignerUI:ContinueNativeCategorySave(request)
    end
    local function Cancel()
        if DesignerUI.nativeCategoryReloadConfirmToken ~= token then return end
        ClearToken()
        if automatic then
            local message = T(
                "designer.native_category_reload.pending",
                "暴雪冷却设置尚未同步，相关监控暂按“特殊”方式显示。"
            )
            DesignerUI:SetStatus(message)
            Print(message)
        end
    end
    S:ShowConfirmPopup(
        T(
            automatic
                and "designer.native_category_reload.automatic_message"
                or "designer.native_category_reload.save_message",
                automatic
                    and "当前方案需要同步暴雪冷却设置。继续后需重载界面。"
                    or "当前方案需要同步暴雪冷却设置。保存完成后需重载界面。"
        ),
        Accept,
        {
            titleText = T(
                "designer.native_category_reload.title",
                "需要重载界面"
            ),
            acceptText = T(
                automatic
                    and "designer.native_category_reload.automatic_accept"
                    or "designer.native_category_reload.save_accept",
                automatic and "继续同步" or "继续保存"
            ),
            cancelText = T(
                automatic
                    and "designer.native_category_reload.later"
                    or "designer.native_category_reload.return_edit",
                automatic and "稍后处理" or "返回编辑"
            ),
            onCancel = Cancel,
            acceptTone = "warning",
        }
    )
    return true
end

function DesignerUI:ShowNativeCategoryReloadNowPrompt(outcome)
    if not (S and type(S.ShowConfirmPopup) == "function") then
        return false
    end
    outcome = type(outcome) == "table" and outcome or {}
    local token = {}
    self.nativeCategoryReloadNowToken = token
    self.saving = true
    self:SetBusyInteractionBlocked(true)
    local function ReloadNow()
        if DesignerUI.nativeCategoryReloadNowToken ~= token then return end
        local configSets = YHUD.ConfigSets
        if not (configSets
            and type(configSets.ReloadInterfaceNow) == "function") then
            return
        end
        return configSets:ReloadInterfaceNow()
    end
    local function RestorePrompt()
        if DesignerUI.nativeCategoryReloadNowToken == token then
            DesignerUI:ShowNativeCategoryReloadNowPrompt(outcome)
        end
    end
    local failed = outcome.failed == true
    S:ShowConfirmPopup(
        T(
            failed
                and "designer.native_category_reload.required_failed_message"
                or "designer.native_category_reload.required_message",
            failed
                and "同步失败，已恢复原配置。请立即重载界面。"
                or "当前方案已保存，并已同步暴雪冷却设置。需要重载界面才能完成应用。"
        ),
        ReloadNow,
        {
            titleText = T(
                "designer.native_category_reload.required_title",
                "需要重载界面"
            ),
            buttons = {
                {
                    text = T(
                        "designer.native_category_reload.reload_now",
                        "立即重载"
                    ),
                    tone = "warning",
                    width = 120,
                    callback = ReloadNow,
                },
            },
            onDismiss = RestorePrompt,
        }
    )
    return true
end

function DesignerUI:ExecuteSavedNativeCategoryReload(result, fallbackPlan, recovery)
    local plan = GetSavedNativeCategoryPlan(result) or fallbackPlan
    if type(plan) ~= "table" or type(plan.requests) ~= "table"
        or #plan.requests == 0 then
        return false
    end
    local configSets = YHUD.ConfigSets
    if not (configSets
        and type(configSets.ExecuteNativeCategoryReload) == "function") then
        return nil, "native-category-reloader-unavailable"
    end
    local reloadResult, code, detail =
        configSets:ExecuteNativeCategoryReload(plan, recovery)
    if type(reloadResult) == "table"
        and reloadResult.reloadPending == true then
        return self:ShowNativeCategoryReloadNowPrompt(reloadResult)
    end
    return reloadResult, code, detail
end

function DesignerUI:SaveAndClose(options)
    options = type(options) == "table" and options or {}
    if self.saving == true then return false end
    if not FinishOpenColorPicker("confirm") then return false end
    if options.placementsCaptured == true then
        local session = Designer:GetSession()
        local revision = session and session.draft
            and (tonumber(session.draft.revision) or 0) or nil
        if not session or session ~= options.expectedSession
            or revision ~= options.expectedRevision
            or session.runtimeSpecKey ~= options.expectedSpecKey then
            return self:SaveAndClose()
        end
    else
        local placements, placementCode = self:CaptureDraftPlacements()
        if not placements then
            local message = T("designer.error_save", "保存失败：")
                .. tostring(placementCode)
            self:SetStatus(message)
            Print(message)
            return false
        end
    end
    local recovery
    if options.nativeCategoryReloadApproved ~= true then
        local plan, planCode, report
        if type(Designer.PlanNativeCategorySync) == "function" then
            plan, planCode, report = Designer:PlanNativeCategorySync()
        else
            plan = { kind = "cooldown-category-reload", requests = {} }
            report = { changedCount = 0, requiresReload = false }
        end
        if not plan then
            local message = T("designer.error_save", "保存失败：")
                .. tostring(planCode)
            self:SetStatus(message)
            Print(message)
            return false
        end
        if report and report.changedCount > 0 then
            local session = Designer:GetSession()
            return self:ContinueNativeCategorySave({
                plan = plan,
                report = report,
                session = session,
                revision = session and session.draft
                    and (tonumber(session.draft.revision) or 0) or nil,
                specKey = session and session.runtimeSpecKey or nil,
            })
        end
    else
        local session = Designer:GetSession()
        local draft = session and session.draft
        recovery = draft and {
            setId = draft.setId,
            storageSnapshot = YHUD:CopyValue(draft.storageSnapshot),
        } or nil
    end
    self.saving = true
    if self.finishButton and self.finishButton.SetDisabled then
        self.finishButton:SetDisabled(true)
    end
    local function RecoverSavedConfiguration()
        local storageOK = true
        if recovery then
            storageOK = Catalog:RestoreDraftStorageSnapshot(
                recovery.setId,
                recovery.storageSnapshot
            ) ~= nil
        end
        local service = YUI.Settings and YUI.Settings.ConfigSets
        local runtimeOK = service
            and service.UndoForReload
            and service:UndoForReload(YHUD.CONFIG_SET_PROVIDER_ID, YHUD)
        return storageOK and runtimeOK ~= nil
    end
    if type(Designer.StartSave) ~= "function" then
        local saveOptions = options.nativeCategoryReloadApproved == true
            and {
                nativeCategoryReloadApproved = true,
                nativeCategoryPlan = options.nativeCategoryPlan,
                nativeCategoryReport = options.nativeCategoryReport,
                keepSessionForReload = true,
            } or nil
        local result, code, detail = Designer:Save(saveOptions)
        if not result then
            self.saving = false
            if self.finishButton and self.finishButton.SetDisabled then
                self.finishButton:SetDisabled(false)
            end
            local message = T("designer.error_save", "保存失败：")
                .. tostring(code)
            if detail ~= nil and tostring(detail) ~= "" then
                message = message .. " (" .. tostring(detail) .. ")"
            end
            self:SetStatus(message)
            Print(message)
            return false
        end
        local reloadPlan = GetSavedNativeCategoryPlan(result)
            or options.nativeCategoryPlan
        if type(reloadPlan) == "table"
            and type(reloadPlan.requests) == "table"
            and #reloadPlan.requests > 0 then
            self.saving = false
            if self.finishButton and self.finishButton.SetDisabled then
                self.finishButton:SetDisabled(false)
            end
            return self:ExecuteSavedNativeCategoryReload(
                result,
                reloadPlan,
                RecoverSavedConfiguration
            )
        end
        local restoredConfigurationName = type(result) == "table"
            and result.applied == false
            and self:GetActiveConfigurationName() or nil
        self:FinishClose(
            "designer-save",
            true,
            type(result) == "table" and result.applied == true
        )
        if restoredConfigurationName then
            self:ShowRestoredConfigurationToast(restoredConfigurationName)
        end
        return true
    end
    local generation = (tonumber(self.busyGeneration) or 0) + 1
    self:ShowBusyOperation("save", generation, true)
    local saveJob = Designer:StartSave({
        nativeCategoryReloadApproved =
            options.nativeCategoryReloadApproved == true,
        nativeCategoryPlan = options.nativeCategoryPlan,
        nativeCategoryReport = options.nativeCategoryReport,
        keepSessionForReload = options.nativeCategoryReloadApproved == true,
        onProgress = function(progress)
            if DesignerUI.busyGeneration == generation then
                DesignerUI:UpdateBusyProgress(progress)
            end
        end,
        onCommit = function()
            if DesignerUI.busyGeneration == generation then
                DesignerUI:SetBusyCancelable(false)
                DesignerUI:UpdateBusyProgress({
                    phase = "complete",
                    progress = 1,
                })
            end
        end,
        onComplete = function(result, code, detail)
            if DesignerUI.busyGeneration ~= generation then return end
            DesignerUI:ClearBusyOperation(generation)
            DesignerUI.saving = false
            if not result then
                local message = T("designer.error_save", "保存失败：")
                    .. tostring(code)
                if detail ~= nil and tostring(detail) ~= "" then
                    message = message .. " (" .. tostring(detail) .. ")"
                end
                DesignerUI:SetStatus(message)
                Print(message)
                return
            end
            local reloadPlan = GetSavedNativeCategoryPlan(result)
                or options.nativeCategoryPlan
            if type(reloadPlan) == "table"
                and type(reloadPlan.requests) == "table"
                and #reloadPlan.requests > 0 then
                return DesignerUI:ExecuteSavedNativeCategoryReload(
                    result,
                    reloadPlan,
                    RecoverSavedConfiguration
                )
            end
            local restoredConfigurationName = result.applied == false
                and DesignerUI:GetActiveConfigurationName() or nil
            DesignerUI:FinishClose(
                "designer-save",
                true,
                result.applied == true
            )
            if restoredConfigurationName then
                DesignerUI:ShowRestoredConfigurationToast(
                    restoredConfigurationName
                )
            end
        end,
    })
    if self.busyGeneration == generation then self.busyJob = saveJob end
    return true
end

function DesignerUI:CancelAndClose()
    if self.designOperation then
        return self:AbortEnter("designer-cancel", true)
    end
    FinishOpenColorPicker()
    self:RestoreRuntimeLayoutSnapshot()
    local ok, code = Designer:Cancel()
    if not ok then
        self:SetStatus(T("designer.error_cancel", "取消失败：") .. tostring(code))
        return false
    end
    self:FinishClose("designer-cancel", true)
    return true
end

function DesignerUI:ForceClose(reason)
    if self.designOperation then
        return self:AbortEnter(reason or "designer-force-close", true)
    end
    if self.busyJob and self.busyJob.Cancel then self.busyJob:Cancel() end
    self:ClearBusyOperation()
    FinishOpenColorPicker()
    self:RestoreRuntimeLayoutSnapshot()
    if Designer:IsOpen() then Designer:Cancel() end
    self:FinishClose(reason or "designer-force-close", false)
    return true
end

function DesignerUI:Open(source, setId)
    if InCombat() then
        Print(T(
            "designer.error_combat_open",
            "Halo 监控台：战斗中不能打开设置。"
        ))
        return nil, "combat"
    end
    local Layout = YUI.Layout
    if Layout and Layout.IsEditing and Layout:IsEditing()
        and Layout.CloseEditMode then
        Layout:CloseEditMode("yhud-open")
    end

    local resumedSession = Designer:IsOpen()
    if resumedSession then
        local session = Designer:GetSession()
        if self.designOperation then
            if self.enteringSurface then self.enteringSurface:Show() end
            return session
        end
        if source == "settings" and S.Close then S:Close() end
        if self:GetDesignEnterState() == "active" and self.active == true then
            self:ShowWorkspace()
        else
            self:StartStagedEnter(session, source)
        end
        return session
    end
    self.designEnterState = "preparing"
    local entering = self:EnsureEnteringSurface()
    entering:Show()
    self:SetEnteringStatus(T(
        "designer.preparing",
        "正在准备设计模式"
    ))
    if type(Designer.StartOpen) ~= "function" then
        local code, detail
        local session
        session, code, detail = Designer:Open(setId)
        if not session then
            entering:Hide()
            self.designEnterState = "closed"
            return ReturnOpenFailure(source, code, detail)
        end
        if source == "settings" and S.Close then S:Close() end
        self:StartStagedEnter(session, source)
        return session
    end

    local generation = (tonumber(self.busyGeneration) or 0) + 1
    self.busyKind = "open"
    self.busyGeneration = generation
    self.busyCancelable = true
    local openedSession
    local openedCode
    local openedDetail
    local openJob = Designer:StartOpen(setId, {
        isCurrent = function()
            return DesignerUI.busyGeneration == generation
        end,
        onProgress = function(progress)
            if DesignerUI.busyGeneration == generation then
                local phase = type(progress) == "table" and progress.phase
                DesignerUI:SetEnteringStatus(T(
                    BUSY_PHASE_KEYS[phase] or "designer.preparing",
                    BUSY_PHASE_FALLBACKS[phase]
                        or "正在准备设计模式"
                ))
            end
        end,
        onComplete = function(session, resultCode, resultDetail)
            if DesignerUI.busyGeneration ~= generation then return end
            DesignerUI:ClearBusyOperation(generation)
            if not session then
                openedCode = resultCode
                openedDetail = resultDetail
                if DesignerUI.enteringSurface then
                    DesignerUI.enteringSurface:Hide()
                end
                DesignerUI.designEnterState = "closed"
                ReturnOpenFailure(source, resultCode, resultDetail)
                return
            end
            openedSession = session
            if source == "settings" and S.Close then S:Close() end
            DesignerUI:StartStagedEnter(session, source)
        end,
    })
    if self.busyGeneration == generation then self.busyJob = openJob end
    if openedSession then return openedSession end
    if openedCode then return nil, openedCode, openedDetail end
    return true, "pending"
end

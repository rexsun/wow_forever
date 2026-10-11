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

function DesignerUI:EnsureDesignerDialogs()
    if self.dialogBlocker and self.switchDialog and self.cancelDialog then
        return true
    end
    if self.dialogBlocker or self.switchDialog or self.cancelDialog then
        return nil, "designer-dialogs-partial"
    end
    if not (GUI2 and GUI2.CreateFrame and GUI2.CreatePanel
        and GUI2.CreateText and GUI2.Form
        and GUI2.Form.CreateButton and UIParent) then
        return nil, "gui-unavailable"
    end

    local blocker = GUI2:CreateFrame(UIParent, {
        name = "YUI_YHUD_DesignerDialogBlocker",
        allPoints = true,
        strata = "FULLSCREEN_DIALOG",
        level = 700,
        mouse = true,
        hidden = true,
    })

    local switchDialog = GUI2:CreatePanel(UIParent, {
        name = "YUI_YHUD_DesignerSwitchDialog",
        width = 430,
        height = 186,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    switchDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 70)
    switchDialog:SetFrameStrata("FULLSCREEN_DIALOG")
    switchDialog:SetFrameLevel(710)
    switchDialog:EnableMouse(true)
    switchDialog:Hide()

    local switchTitle = GUI2:CreateText(
        switchDialog,
        T("designer.unsaved_title", "未保存的修改"),
        "font.size.xl",
        "color.text.heading",
        "CENTER"
    )
    switchTitle:SetPoint("TOPLEFT", 20, -18)
    switchTitle:SetPoint("TOPRIGHT", -20, -18)

    local switchMessage = GUI2:CreateText(
        switchDialog,
        T("designer.unsaved_message", "切换配置前，如何处理当前修改？"),
        "font.size.md",
        "color.text.secondary",
        "CENTER"
    )
    switchMessage:SetPoint("TOPLEFT", 24, -58)
    switchMessage:SetPoint("TOPRIGHT", -24, -58)
    switchMessage:SetHeight(38)
    switchMessage:SetWordWrap(true)

    local saveSwitch = GUI2.Form:CreateButton(switchDialog, {
        text = T("designer.save_switch", "保存并切换"),
        width = 120,
        height = 30,
        tone = "success",
        onClick = function()
            DesignerUI:ResolveSwitch("save")
        end,
    })
    saveSwitch:SetPoint("BOTTOMLEFT", 20, 18)

    local discardSwitch = GUI2.Form:CreateButton(switchDialog, {
        text = T("designer.discard_switch", "放弃并切换"),
        width = 120,
        height = 30,
        tone = "danger",
        onClick = function()
            DesignerUI:ResolveSwitch("discard")
        end,
    })
    discardSwitch:SetPoint("BOTTOM", 0, 18)

    local cancelSwitch = GUI2.Form:CreateButton(switchDialog, {
        text = T("designer.cancel", "取消"),
        width = 120,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:ResolveSwitch("cancel")
        end,
    })
    cancelSwitch:SetPoint("BOTTOMRIGHT", -20, 18)

    local cancelDialog = GUI2.Form:CreateSaveChangesDialog(UIParent, {
        name = "YUI_YHUD_DesignerCancelDialog",
        locale = YUI.Locale:Get("Core"),
        onResolve = function(action) DesignerUI:ResolveCancelClose(action) end,
    })
    cancelDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 70)

    self.dialogBlocker = blocker
    self.switchDialog = switchDialog
    self.cancelDialog = cancelDialog
    return true
end

function DesignerUI:EnsureNewGroupDialog()
    if self.newGroupDialog and self.newGroupType and self.newGroupLayout
        and self.newGroupLayoutLabel and self.dialogBlocker then
        return true
    end
    if self.newGroupDialog or self.newGroupType or self.newGroupLayout
        or self.newGroupLayoutLabel then
        return nil, "designer-new-group-dialog-partial"
    end
    if not (GUI2 and GUI2.CreatePanel and GUI2.CreateText and GUI2.Form
        and GUI2.Form.CreateButton and GUI2.Form.CreateSegmentedControl
        and UIParent) then
        return nil, "gui-unavailable"
    end
    local ready, code = self:EnsureDesignerDialogs()
    if not ready then return nil, code end

    local newGroupDialog = GUI2:CreatePanel(UIParent, {
        name = "YUI_YHUD_DesignerNewGroupDialog",
        width = 430,
        height = 300,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    newGroupDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 70)
    newGroupDialog:SetFrameStrata("FULLSCREEN_DIALOG")
    newGroupDialog:SetFrameLevel(710)
    newGroupDialog:EnableMouse(true)
    newGroupDialog:Hide()

    local newGroupTitle = GUI2:CreateText(
        newGroupDialog,
        T("designer.new_group_title", "新建分组"),
        "font.size.xl",
        "color.text.heading",
        "LEFT"
    )
    newGroupTitle:SetPoint("TOPLEFT", 20, -18)

    local newGroupTypeLabel = GUI2:CreateText(
        newGroupDialog,
        T("designer.new_group_policy", "监控类型"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    newGroupTypeLabel:SetPoint("TOPLEFT", 20, -58)

    local newGroupType = GUI2.Form:CreateSegmentedControl(
        newGroupDialog,
        {
            width = 390,
            height = 34,
            items = {
                {
                    text = T("designer.new_cooldown_group", "冷却组"),
                    value = "cooldown-primary",
                },
                {
                    text = T("designer.new_buff_group", "光环组"),
                    value = "buff-only",
                },
                {
                    text = T("designer.type.resource", "资源条"),
                    value = "resource-only",
                },
            },
            value = "cooldown-primary",
            set = function(value)
                DesignerUI.pendingNewGroupPolicy = value == "resource-only" and value
                    or (value == "buff-only" and "buff-only" or "cooldown-primary")
                local resource = value == "resource-only"
                SetShown(DesignerUI.newGroupLayout, not resource)
                SetShown(DesignerUI.newGroupLayoutLabel, not resource)
                if resource then DesignerUI.pendingNewGroupLayout = "resource" end
                if DesignerUI.newGroupLayout then
                    local cooldown = DesignerUI.pendingNewGroupPolicy
                        == "cooldown-primary"
                    DesignerUI.newGroupLayout:SetItemDisabled("bars", cooldown)
                    DesignerUI.newGroupLayout:SetItemDisabled("rings", cooldown)
                    if cooldown then
                        DesignerUI.pendingNewGroupLayout = "icons"
                        DesignerUI.newGroupLayout:SetValue("icons", true)
                    end
                end
            end,
        }
    )
    newGroupType:SetPoint("TOPLEFT", 20, -78)

    local newGroupLayoutLabel = GUI2:CreateText(
        newGroupDialog,
        T("designer.new_group_layout", "显示方式"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    newGroupLayoutLabel:SetPoint("TOPLEFT", 20, -130)

    local newGroupLayout = GUI2.Form:CreateSegmentedControl(
        newGroupDialog,
        {
            width = 390,
            height = 34,
            items = {
                {
                    text = T("designer.type.icons", "图标"),
                    value = "icons",
                },
                {
                    text = T("designer.type.bars", "进度条"),
                    value = "bars",
                },
                {
                    text = T("designer.type.rings", "圆环"),
                    value = "rings",
                },
            },
            value = "icons",
            set = function(value)
                DesignerUI.pendingNewGroupLayout =
                    MONITOR_LAYOUTS[value] and value or "icons"
            end,
        }
    )
    newGroupLayout:SetPoint("TOPLEFT", 20, -150)

    local newGroupCancel = GUI2.Form:CreateButton(newGroupDialog, {
        text = T("designer.cancel", "取消"),
        width = 120,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:HideNewGroupDialog()
        end,
    })
    newGroupCancel:SetPoint("BOTTOMRIGHT", -150, 18)

    local newGroupCreate = GUI2.Form:CreateButton(newGroupDialog, {
        text = T("designer.create", "创建"),
        width = 120,
        height = 30,
        tone = "warning",
        onClick = function()
            DesignerUI:CreateGroup(
                DesignerUI.pendingNewGroupPolicy
                    or "cooldown-primary",
                DesignerUI.pendingNewGroupLayout or "icons"
            )
        end,
    })
    newGroupCreate:SetPoint("BOTTOMRIGHT", -20, 18)

    self.newGroupDialog = newGroupDialog
    self.newGroupType = newGroupType
    self.newGroupLayout = newGroupLayout
    self.newGroupLayoutLabel = newGroupLayoutLabel
    return true
end

function DesignerUI:HideNewGroupDialog()
    self.pendingNewGroupPolicy = nil
    self.pendingNewGroupLayout = nil
    if self.newGroupDialog then self.newGroupDialog:Hide() end
    if self.dialogBlocker then self.dialogBlocker:Hide() end
end

function DesignerUI:ShowNewGroupDialog()
    local ready, code = self:EnsureNewGroupDialog()
    if not ready then
        self:SetStatus(T("designer.error_create_group", "无法新建分组：") .. tostring(code))
        return nil, code
    end
    self:HideMonitorPicker()
    self:HideSwitchDialog()
    self.pendingNewGroupPolicy = "cooldown-primary"
    self.pendingNewGroupLayout = "icons"
    if self.newGroupType and self.newGroupType.SetValue then
        self.newGroupType:SetValue("cooldown-primary", true)
    end
    if self.newGroupLayout and self.newGroupLayout.SetValue then
        self.newGroupLayout:SetValue("icons", true)
    end
    if self.newGroupLayout and self.newGroupLayout.SetItemDisabled then
        self.newGroupLayout:SetItemDisabled("bars", true)
        self.newGroupLayout:SetItemDisabled("rings", true)
    end
    SetShown(self.newGroupLayout, true)
    SetShown(self.newGroupLayoutLabel, true)
    self.dialogBlocker:Show()
    self.newGroupDialog:Show()
    return true
end

function DesignerUI:CreateGroup(contentPolicy, layout)
    self:HideMonitorPicker()
    contentPolicy = contentPolicy == "resource-only" and contentPolicy
        or (contentPolicy == "buff-only" and "buff-only" or "cooldown-primary")
    layout = MONITOR_LAYOUTS[layout] and layout or "icons"
    if contentPolicy == "resource-only" then layout = "resource"
    elseif contentPolicy == "cooldown-primary" then layout = "icons" end
    self:HideNewGroupDialog()
    local group, code = Designer:CreateGroup(
        self:BuildNewGroupName(),
        contentPolicy,
        layout
    )
    if not group then
        self:SetStatus(
            T("designer.error_create_group", "无法新建分组：")
                .. tostring(code)
        )
        return false
    end
    self.inspectorSection = "group"
    self.manualPanel = false
    self.propertyPage = "monitor"
    self.monitorPage = 1
    self.monitorEffectsEditing = false
    self.monitorSoundEditing = false
    self:RefreshAfterStructuralMutation(true)
    local LayoutBridge = YHUD.LayoutBridge
    if LayoutBridge and LayoutBridge.ResetGroupPosition then
        LayoutBridge:ResetGroupPosition(group.id, group)
    end
    self:SetStatus(string.format(
        T("designer.status_group_created", "已新建空白%s。"),
        GroupTypeName(group)
    ))
    return group
end

function DesignerUI:CreateIconGroup()
    return self:CreateGroup("cooldown-primary", "icons")
end

function DesignerUI:RequestDefaultRestore()
    local session = Designer:GetSession()
    if not session then return false end
    local preview, code = Designer:PreviewDefaultRestore(session.selectedGroupId)
    if not preview then
        self:SetStatus(T("designer.error_restore", "无法读取暴雪冷却设置：") .. tostring(code))
        return false
    end
    if not S.ShowConfirmPopup then
        return self:ConfirmDefaultRestore(preview)
    end

    self:ClearRestoreConfirm(true)
    local token = {}
    local acceptCallback
    local cancelCallback
    acceptCallback = function()
        if DesignerUI.restoreConfirmToken ~= token then return end
        DesignerUI:ClearRestoreConfirm(false)
        DesignerUI:ConfirmDefaultRestore(preview)
    end
    cancelCallback = function()
        if DesignerUI.restoreConfirmToken ~= token then return end
        DesignerUI:ClearRestoreConfirm(false)
        Designer:CancelDefaultRestore()
    end
    self.restoreConfirmToken = token
    self.restoreConfirmAccept = acceptCallback
    self.restoreConfirmCancel = cancelCallback
    S:ShowConfirmPopup(
        T("designer.restore_confirm", "恢复该分组对应的全部暴雪冷却？"),
        acceptCallback,
        {
            titleText = T("designer.restore_title", "恢复暴雪冷却"),
            acceptText = T("designer.restore_accept", "恢复"),
            cancelText = T("designer.cancel", "取消"),
            onCancel = cancelCallback,
            acceptTone = "warning",
        }
    )
    if self.restoreConfirmToken == token then
        self.restoreConfirmFrame = S.ConfirmFrame
    end
    return true
end

function DesignerUI:ConfirmDefaultRestore(preview)
    local report, code = Designer:ConfirmDefaultRestore(preview)
    if not report then
        self:SetStatus(T("designer.error_restore", "无法恢复暴雪冷却：") .. tostring(code))
        return false
    end
    self.manualPanel = false
    self:Refresh(true)
    self:SetStatus(T("designer.status_restored", "已恢复到当前暴雪冷却设置，完成后保存。"))
    return true
end

function DesignerUI:HideSwitchDialog()
    self.pendingSwitchSetId = nil
    if self.switchDialog then self.switchDialog:Hide() end
    if self.dialogBlocker then self.dialogBlocker:Hide() end
end

function DesignerUI:ShowSwitchDialog(setId)
    local ready, code = self:EnsureDesignerDialogs()
    if not ready then
        self:SetStatus(T("designer.error_switch", "无法切换配置：") .. tostring(code))
        return nil, code
    end
    self.pendingSwitchSetId = setId
    self.dialogBlocker:Show()
    self.switchDialog:Show()
end

function DesignerUI:RequestSwitch(setId)
    local session = Designer:GetSession()
    if not session or not setId or setId == session.setId then return true end
    if self:IsSessionDirty() then
        self.profileDropdown:SetValue(session.setId, true)
        self:ShowSwitchDialog(setId)
        return false
    end
    return self:PerformSwitch(setId)
end

function DesignerUI:PerformSwitch(setId, resolution)
    self:HideMonitorPicker()
    if resolution == "save" then
        local placements, code = self:CaptureDraftPlacements()
        if not placements then
            self:SetStatus(
                T("designer.error_switch", "无法切换配置：")
                    .. tostring(code)
            )
            return false
        end
    end
    if resolution == "save" and Designer.PlanNativeCategorySync then
        local plan, planCode, report = Designer:PlanNativeCategorySync()
        if not plan then
            self:SetStatus(T("designer.error_switch", "无法切换配置：")
                .. tostring(planCode))
            return false
        end
        if report and report.changedCount > 0 then
            local session = Designer:GetSession()
            self:HideSwitchDialog()
            return self:ContinueNativeCategorySave({
                plan = plan,
                report = report,
                session = session,
                revision = session and session.draft
                    and (tonumber(session.draft.revision) or 0) or nil,
                specKey = session and session.runtimeSpecKey or nil,
            })
        end
    end
    if resolution == "discard" then self:RestoreLayoutSnapshot() end
    if type(Designer.StartSwitch) ~= "function" then
        local session, code = Designer:Switch(setId, resolution)
        if not session then
            self:SetStatus(T("designer.error_switch", "无法切换配置：")
                .. tostring(code))
            return false
        end
        self:HideSwitchDialog()
        self.manualPanel = false
        self:Refresh(true)
        local bridge = YHUD.LayoutBridge
        local profile = Designer:GetProfile()
        if bridge and bridge.Sync and profile then bridge:Sync(profile) end
        self:CaptureLayoutSnapshot()
        return true
    end

    local generation = (tonumber(self.busyGeneration) or 0) + 1
    self:ShowBusyOperation("switch", generation, true)
    local switchJob = Designer:StartSwitch(setId, resolution, {
        isCurrent = function()
            return DesignerUI.busyGeneration == generation
        end,
        onProgress = function(progress)
            if DesignerUI.busyGeneration == generation then
                DesignerUI:UpdateBusyProgress(progress)
            end
        end,
        onComplete = function(session, code, detail)
            if DesignerUI.busyGeneration ~= generation then return end
            DesignerUI:ClearBusyOperation(generation)
            if not session then
                local message = T("designer.error_switch", "无法切换配置：")
                    .. tostring(code)
                if detail ~= nil and tostring(detail) ~= "" then
                    message = message .. " (" .. tostring(detail) .. ")"
                end
                DesignerUI:SetStatus(message)
                return
            end
            DesignerUI:HideSwitchDialog()
            DesignerUI.manualPanel = false
            DesignerUI:Refresh(true)
            local bridge = YHUD.LayoutBridge
            local profile = Designer:GetProfile()
            if bridge and bridge.Sync and profile then bridge:Sync(profile) end
            DesignerUI:CaptureLayoutSnapshot()
        end,
    })
    if self.busyGeneration == generation then self.busyJob = switchJob end
    return true
end

function DesignerUI:ResolveSwitch(resolution)
    local target = self.pendingSwitchSetId
    if resolution == "cancel" or not target then
        self:HideSwitchDialog()
        local session = Designer:GetSession()
        if session then self.profileDropdown:SetValue(session.setId, true) end
        return true
    end
    return self:PerformSwitch(target, resolution)
end

function DesignerUI:HideCancelDialog()
    if self.cancelDialog then self.cancelDialog:Hide() end
    if self.dialogBlocker then self.dialogBlocker:Hide() end
end

function DesignerUI:ShowCancelDialog()
    local ready, code = self:EnsureDesignerDialogs()
    if not ready then
        self:SetStatus(T("designer.error_cancel", "取消失败：") .. tostring(code))
        return nil, code
    end
    self:HideMonitorPicker()
    self:HideGlowEditor()
    self:HideNewGroupDialog()
    self.dialogBlocker:Show()
    self.cancelDialog:Show()
    if self.cancelDialog.IsShown and not self.cancelDialog:IsShown() then
        self.dialogBlocker:Hide()
        self:SetStatus(T("designer.error_cancel", "取消失败：") .. "dialog-not-shown")
        return nil, "dialog-not-shown"
    end
    return true
end

function DesignerUI:RequestCancelClose()
    if not Designer:IsOpen() then return false end
    if self:IsSessionDirty() then
        return self:ShowCancelDialog()
    end
    return self:CancelAndClose()
end

function DesignerUI:ResolveCancelClose(resolution)
    if resolution == "cancel" then
        self:HideCancelDialog()
        return true
    end
    self:HideCancelDialog()
    if resolution == "save" then return self:SaveAndClose() end
    if resolution == "discard" then return self:CancelAndClose() end
    return false
end

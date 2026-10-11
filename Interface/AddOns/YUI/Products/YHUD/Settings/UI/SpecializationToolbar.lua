local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local GUI2 = YUI.GUI2
local Settings = YUI.Settings
local Designer = YHUD.Designer
local DesignerUI = YHUD.DesignerUI
if not (GUI2 and GUI2.Form and Designer and DesignerUI) then return end
local Icons = YUI.API and YUI.API.Icons
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API
local SPEC_ICON_FALLBACK = 134400
local SPEC_PICKER_MIN_WIDTH = 288
local SPEC_PICKER_MAX_WIDTH = 316
local SPEC_PICKER_PANEL_TO_BUTTON = 40
local SPEC_PICKER_PANEL_TO_SCROLL = 26
local SPEC_PICKER_PANEL_TO_CHILD = 34
local SPEC_PICKER_PANEL_TO_HEADER = 38

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

local function ColorHex(r, g, b, a)
    if _G.CreateColor then
        return _G.CreateColor(r or 1, g or 1, b or 1, a or 1)
            :GenerateHexColor()
    end
    return string.format(
        "ff%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5)
    )
end

local function TokenHex(token, fallback)
    local r, g, b, a = GUI2:GetColor(token, fallback)
    return ColorHex(r, g, b, a)
end

local function ClassHex(classFile)
    local color = classFile and UnitAPI and UnitAPI.GetClassColor
        and UnitAPI.GetClassColor(classFile) or nil
    return ColorHex(
        color and color.r or 1,
        color and color.g or 1,
        color and color.b or 1,
        1
    )
end

local function Colorize(text, hex)
    return "|c" .. tostring(hex or "ffffffff")
        .. tostring(text or "") .. "|r"
end

local function BuildColoredSpecLabel(label, row, suffix, suffixToken)
    local classHex = ClassHex(row and row.classFile)
    local result = Colorize(label, classHex)
    if suffix and suffix ~= "" then
        local token = suffixToken or "color.state.success"
        result = result .. Colorize(
            suffix,
            TokenHex(
                token,
                token == "color.text.accent"
                    and { 1, 0.82, 0, 1 }
                    or { 0.12, 0.72, 0.34, 1 }
            )
        )
    end
    return result
end

local function BuildSpecLabel(row, session)
    local label = row and row.text or session.viewSpecKey
    local specKey = row and row.specKey or session.viewSpecKey
    if specKey == session.runtimeSpecKey then
        return BuildColoredSpecLabel(
            label,
            row,
            T("designer.spec.current_suffix", "（当前）")
        )
    end
    return BuildColoredSpecLabel(
        label,
        row,
        nil
    )
end

local function ApplySpecializationPresentation(button, row)
    if not button then return end
    local nativeIcon = row and row.icon or SPEC_ICON_FALLBACK
    if button.icon then
        local iconData = Icons and Icons.GetScopedSpecIcon
            and Icons.GetScopedSpecIcon(row and row.specID, nativeIcon, "settings")
        local applied = Icons and Icons.GetScopedSpecIcon and Icons.ApplyIcon
            and Icons.ApplyIcon(
                button.icon,
                iconData
            )
        if applied and iconData.custom ~= true and button.icon.SetTexCoord then
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if not applied and button.icon.SetTexture then
            button.icon:SetTexture(nativeIcon)
            if button.icon.SetTexCoord then
                button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
        if button.icon.Show then button.icon:Show() end
    end

end

function DesignerUI:RefreshSpecializationToolbar()
    if not self.viewSpecButton then return end
    local session = Designer:GetSession()
    if not session then return end
    local sections = Designer:GetSpecializationSections() or {}
    local selected
    for sectionIndex = 1, #sections do
        for rowIndex = 1, #sections[sectionIndex].rows do
            local row = sections[sectionIndex].rows[rowIndex]
            if row.specKey == session.viewSpecKey then selected = row break end
        end
        if selected then break end
    end
    self.viewSpecButton:SetText(BuildSpecLabel(selected, session))
    ApplySpecializationPresentation(self.viewSpecButton, selected)
    if self.RefreshToolbarContext then self:RefreshToolbarContext() end
end

function DesignerUI:HideSpecializationPicker()
    if self.specializationPicker then self.specializationPicker:Hide() end
end

local function SpecializationButtonOnClick(control)
    local targetSpecKey = control.specKey
    DesignerUI:HideSpecializationPicker()
    if DesignerUI.HideReplicationDialog then
        DesignerUI:HideReplicationDialog()
    end
    DesignerUI:CancelMonitorIdentityEdit(true)
    local profile, code = Designer:SwitchViewSpec(targetSpecKey)
    if not profile then
        DesignerUI:SetStatus(T(
            "designer.spec.switch_failed",
            "无法切换查看专精。"
        ) .. " (" .. tostring(code or "unknown") .. ")")
        return
    end
    if DesignerUI.HideMonitorPicker then
        DesignerUI:HideMonitorPicker()
    end
    DesignerUI.monitorEffectsEditing = false
    DesignerUI.monitorSoundEditing = false
    DesignerUI:ApplyPreview()
    DesignerUI:RefreshSpecializationToolbar()
    DesignerUI:Refresh(false, false)
end

local function EnsureSpecializationPickerCapacity(picker, sections)
    local headerCount = 0
    local buttonCount = 0
    for sectionIndex = 1, #sections do
        local rows = sections[sectionIndex].rows
        if #rows > 0 then
            headerCount = headerCount + 1
            buttonCount = buttonCount + #rows
        end
    end
    while #picker.headerPool < headerCount do
        picker.headerPool[#picker.headerPool + 1] = GUI2:CreateText(
            picker.scroll.child, "", "font.size.sm",
            "color.text.accent", "LEFT"
        )
    end
    while #picker.buttonPool < buttonCount do
        local button = GUI2.Form:CreateButton(picker.scroll.child, {
                text = "",
                width = SPEC_PICKER_MAX_WIDTH
                    - SPEC_PICKER_PANEL_TO_BUTTON,
                height = 28,
                icon = SPEC_ICON_FALLBACK,
                iconSize = 20,
                preserveIconColor = true,
                contentAlign = "left",
                tone = "default",
                onClick = SpecializationButtonOnClick,
            })
        button:HookScript("OnEnter", function(control)
            if not control.specLabelTruncated or not GameTooltip then return end
            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
            GameTooltip:SetText(control.specPlainLabel or "-", 1, 1, 1)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function(control)
            if GameTooltip and GameTooltip:IsOwned(control) then
                YUI.HideGameTooltip()
            end
        end)
        picker.buttonPool[#picker.buttonPool + 1] = button
    end
end

function DesignerUI:RefreshSpecializationPicker(preparedSections)
    local picker = self.specializationPicker
    if not (picker and picker:IsShown()) then return end
    for index = 1, #picker.headerPool do picker.headerPool[index]:Hide() end
    for index = 1, #picker.buttonPool do picker.buttonPool[index]:Hide() end

    local sections = preparedSections or Designer:GetSpecializationSections()
    if type(sections) ~= "table" then return end
    local sectionNames = {
        ["current-class"] = T(
            "designer.spec.section_current_class",
            "本职业专精"
        ),
        enabled = T(
            "designer.spec.section_enabled",
            "配置启用专精"
        ),
        disabled = T(
            "designer.spec.section_disabled",
            "配置未启用专精"
        ),
    }
    local y = 0
    local headerIndex = 0
    local buttonIndex = 0
    local measuredWidth = SPEC_PICKER_MIN_WIDTH
    for sectionIndex = 1, #sections do
        local section = sections[sectionIndex]
        if #section.rows > 0 then
            headerIndex = headerIndex + 1
            local header = picker.headerPool[headerIndex]
            header:SetText(sectionNames[section.id] or section.id)
            if header.GetStringWidth then
                measuredWidth = math.max(
                    measuredWidth,
                    math.ceil(header:GetStringWidth() or 0)
                        + SPEC_PICKER_PANEL_TO_HEADER
                )
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 6, -y)
            header:SetHeight(24)
            header:Show()
            y = y + 26
            for rowIndex = 1, #section.rows do
                local row = section.rows[rowIndex]
                local label = (row.className or row.classFile)
                    .. " · " .. row.text
                local suffix
                local suffixToken
                if row.current then
                    suffix = T("designer.spec.current_suffix", "（当前）")
                elseif row.viewed then
                    suffix = T("designer.spec.preview_suffix", "（预览）")
                    suffixToken = "color.text.accent"
                end
                buttonIndex = buttonIndex + 1
                local button = picker.buttonPool[buttonIndex]
                button.specKey = row.specKey
                button.specPlainLabel = label .. (suffix or "")
                button:SetText(BuildColoredSpecLabel(
                    label,
                    row,
                    suffix,
                    suffixToken
                ))
                button:SetSelected(row.viewed == true)
                ApplySpecializationPresentation(button, row)
                if button.text and button.text.GetStringWidth then
                    measuredWidth = math.max(
                        measuredWidth,
                        math.ceil(button.text:GetStringWidth() or 0)
                            + SPEC_PICKER_PANEL_TO_BUTTON
                    )
                end
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", 8, -y)
                button:Show()
                y = y + 30
            end
            y = y + 8
        end
    end
    local panelWidth = math.max(
        SPEC_PICKER_MIN_WIDTH,
        math.min(SPEC_PICKER_MAX_WIDTH, measuredWidth)
    )
    picker:SetWidth(panelWidth)
    picker.scroll:SetWidth(panelWidth - SPEC_PICKER_PANEL_TO_SCROLL)
    picker.scroll.child:SetWidth(panelWidth - SPEC_PICKER_PANEL_TO_CHILD)
    for index = 1, headerIndex do
        picker.headerPool[index]:SetWidth(
            panelWidth - SPEC_PICKER_PANEL_TO_HEADER
        )
    end
    local buttonWidth = panelWidth - SPEC_PICKER_PANEL_TO_BUTTON
    for index = 1, buttonIndex do
        local button = picker.buttonPool[index]
        button:SetWidth(buttonWidth)
        button.specLabelTruncated = button.text
            and button.text.GetStringWidth
            and (button.text:GetStringWidth() or 0)
                > buttonWidth - 41
            or false
    end
    picker.scroll.child:SetHeight(math.max(430, y))
end

local function CopyActiveConfigSetReference()
    local service = Settings and Settings.ConfigSets
    local reference = service and service.GetActiveReference
        and service:GetActiveReference(YHUD.ConfigSets.PROVIDER_ID) or nil
    return type(reference) == "table" and {
        kind = reference.kind,
        id = reference.id,
    } or nil
end

local function ReferencesEqual(left, right)
    if left == nil or right == nil then return left == right end
    return left.kind == right.kind and left.id == right.id
end

local function CaptureRuntimeLayoutBaseline()
    local bridge = YHUD.LayoutBridge
    local canonical = YHUD.GetConfigProfile and YHUD:GetConfigProfile()
    local specKey = YHUD.GetCurrentSpecKey and YHUD:GetCurrentSpecKey()
    local runtime = canonical and specKey and YHUD.GetRuntimeProfile
        and YHUD:GetRuntimeProfile(canonical, specKey, true) or nil
    return bridge and bridge.CapturePlacements and runtime
        and bridge:CapturePlacements(runtime) or nil
end

local function RestoreSessionSelection(groupId)
    if not groupId then return false end
    local profile = Designer:GetProfile()
    if not (profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]) then
        return false
    end
    return Designer:SelectGroup(groupId) ~= nil
end

local function FinishSessionReload(groupId, captureRuntimeBaseline)
    if captureRuntimeBaseline then
        local runtimeSnapshot = CaptureRuntimeLayoutBaseline()
        if runtimeSnapshot then
            DesignerUI.runtimeLayoutSnapshot = runtimeSnapshot
        end
    end
    RestoreSessionSelection(groupId)
    DesignerUI.manualPanel = false
    DesignerUI.monitorEffectsEditing = false
    DesignerUI.monitorSoundEditing = false
    DesignerUI.previewRuntimeDirty = false
    if not DesignerUI:ApplyPreview() then
        return nil, "preview-unavailable"
    end
    if DesignerUI.RefreshSpecializationToolbar then
        DesignerUI:RefreshSpecializationToolbar()
    end
    DesignerUI:Refresh(false, false)
    local bridge = YHUD.LayoutBridge
    local profile = Designer:GetProfile()
    if bridge and bridge.Sync and profile then bridge:Sync(profile) end
    DesignerUI:CaptureLayoutSnapshot()
    return Designer:GetSession()
end

local function ReloadDesignerSession(setId, groupId, captureRuntimeBaseline)
    if Designer:IsOpen() then
        local cancelled, code = Designer:Cancel()
        if not cancelled then return nil, code end
    end
    local session, code, detail = Designer:Open(setId)
    if not session and setId ~= nil then
        session, code, detail = Designer:Open(nil)
    end
    if not session then return nil, code, detail end
    return FinishSessionReload(groupId, captureRuntimeBaseline)
end

local function RebaseCurrentDesignerDraft(resolution)
    local session = Designer:GetSession()
    if not session then return nil, "designer-closed" end
    local setId = session.setId
    local groupId = session.selectedGroupId
    local captureRuntimeBaseline = false
    if resolution == "save" then
        local placements, code = DesignerUI:CaptureDraftPlacements()
        if not placements then return nil, code end
        local saved, saveCode, detail = Designer:Save()
        if not saved then return nil, saveCode, detail end
        captureRuntimeBaseline = type(saved) == "table"
            and saved.applied == true
    elseif resolution == "discard" then
        DesignerUI:RestoreLayoutSnapshot()
        local cancelled, code = Designer:Cancel()
        if not cancelled then return nil, code end
    else
        return nil, "invalid-resolution"
    end
    local reopened, code, detail = Designer:Open(setId)
    if not reopened then return nil, code, detail end
    return FinishSessionReload(groupId, captureRuntimeBaseline)
end

local function OpenConfigSetManager(sessionSetId)
    local ConfigSets = YHUD.ConfigSets
    if not (ConfigSets and ConfigSets.Open) then
        return nil, "config-sets-unavailable"
    end
    local initialReference = CopyActiveConfigSetReference()
    local changed = false
    return ConfigSets:Open(nil, {
        host = UIParent,
        setId = sessionSetId,
        frameStrata = "FULLSCREEN_DIALOG",
        frameLevel = 900,
        toplevel = false,
        onApplied = function()
            changed = true
        end,
        onClosed = function()
            if DesignerUI.active ~= true or not Designer:IsOpen() then return end
            local session = Designer:GetSession()
            local finalReference = CopyActiveConfigSetReference()
            local currentExists = session and session.setId
                and YHUD.ConfigCatalog and YHUD.ConfigCatalog.Get
                and YHUD.ConfigCatalog:Get(session.setId) ~= nil
            local activeChanged = not ReferencesEqual(
                initialReference,
                finalReference
            )
            if changed or activeChanged or not currentExists then
                local targetSetId = finalReference
                    and finalReference.kind == "user"
                    and finalReference.id or nil
                local groupId = session and session.selectedGroupId
                local reloaded, code = ReloadDesignerSession(
                    targetSetId,
                    groupId,
                    activeChanged or changed
                )
                if not reloaded then
                    DesignerUI:SetStatus(T(
                        "designer.error_config_manager_reload",
                        "配置方案已关闭，但无法刷新当前设计草稿。"
                    ) .. " (" .. tostring(code or "unknown") .. ")")
                end
            else
                DesignerUI:RefreshSpecializationToolbar()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
end

function DesignerUI:ToggleSpecializationPicker()
    local picker = self.specializationPicker
    if not picker then return end
    if picker:IsShown() then
        picker:Hide()
        return
    end
    local sections = Designer:GetSpecializationSections()
    if type(sections) ~= "table" then return end
    EnsureSpecializationPickerCapacity(picker, sections)
    picker:Show()
    self:RefreshSpecializationPicker(sections)
end

function DesignerUI:PrepareToolbarExternalAction(title, continuation)
    local session = Designer:GetSession()
    if not session then return nil end
    local setId = session.setId
    self:HideSpecializationPicker()
    if self:IsSessionDirty() then
        if not (Settings and Settings.ShowConfirmPopup) then
            return nil, "confirm-unavailable"
        end
        Settings:ShowConfirmPopup(T(
            "designer.config_manager_dirty",
            "打开配置方案前，如何处理当前草稿？"
        ), nil, {
            owner = self,
            ownerFrame = self.workspace,
            titleText = title or T(
                "designer.config_manager",
                "管理配置方案"
            ),
            buttons = {
                {
                    text = T(
                        "designer.config_manager_save",
                        "保存并继续"
                    ),
                    tone = "success",
                    width = 112,
                    callback = function()
                        -- An external import cannot proceed past a save requiring reload.
                        -- Keep the existing save/reload transaction in charge.
                        if title and Designer.PlanNativeCategorySync then
                            local placements, captureCode = DesignerUI:CaptureDraftPlacements()
                            if not placements then DesignerUI:SetStatus(tostring(captureCode)); return end
                            local plan, planCode, report = Designer:PlanNativeCategorySync()
                            if not plan then DesignerUI:SetStatus(tostring(planCode)); return end
                            if report and report.changedCount > 0 then DesignerUI:SaveAndClose(); return end
                        end
                        local rebased, code = RebaseCurrentDesignerDraft("save")
                        if rebased then
                            continuation(setId)
                        else
                            DesignerUI:SetStatus(T(
                                "designer.error_config_manager_prepare",
                                "无法准备配置方案："
                            ) .. tostring(code or "unknown"))
                        end
                    end,
                },
                {
                    text = T(
                        "designer.config_manager_discard",
                        "放弃并继续"
                    ),
                    tone = "danger",
                    width = 112,
                    callback = function()
                        local rebased, code = RebaseCurrentDesignerDraft(
                            "discard"
                        )
                        if rebased then
                            continuation(setId)
                        else
                            DesignerUI:SetStatus(T(
                                "designer.error_config_manager_prepare",
                                "无法准备配置方案："
                            ) .. tostring(code or "unknown"))
                        end
                    end,
                },
                {
                    text = T("designer.replication.cancel", "取消"),
                    tone = "default",
                    width = 92,
                },
            },
        })
        return true
    end
    return continuation(setId)
end

function DesignerUI:OpenConfigSetManagerFromToolbar()
    return self:PrepareToolbarExternalAction(nil, OpenConfigSetManager)
end

function DesignerUI:ReloadAfterExternalImport()
    local reference = CopyActiveConfigSetReference()
    local target = reference and reference.kind == 'user' and reference.id or nil
    local result, code = ReloadDesignerSession(target, nil, true)
    if not result then self:SetStatus(T('designer.error_config_manager_reload') .. ' (' .. tostring(code) .. ')') end
    return result, code
end
function DesignerUI:EnsureSpecializationToolbar()
    if self.specializationPicker then return end
    local viewSpec = self.viewSpecButton

    local picker = GUI2:CreatePanel(UIParent, {
        name = "YUI_YHUD_SpecializationPicker",
        width = SPEC_PICKER_MAX_WIDTH,
        height = 486,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    picker:SetPoint("TOPLEFT", viewSpec, "BOTTOMLEFT", 0, -6)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetFrameLevel(650)
    picker:EnableMouse(true)
    picker:Hide()
    picker.headerPool = {}
    picker.buttonPool = {}
    picker.scroll = GUI2:CreateScrollFrame(picker, {
        template = "UIPanelScrollFrameTemplate",
        width = SPEC_PICKER_MAX_WIDTH - SPEC_PICKER_PANEL_TO_SCROLL,
        height = 454,
        childWidth = SPEC_PICKER_MAX_WIDTH - SPEC_PICKER_PANEL_TO_CHILD,
        childHeight = 454,
    })
    picker.scroll:SetPoint("TOPLEFT", 12, -16)
    self.specializationPicker = picker
    self:RefreshSpecializationToolbar()
end

local specializationToolbarEventOwner = {}

function specializationToolbarEventOwner:RefreshAppearance()
    DesignerUI:RefreshSpecializationToolbar()
    DesignerUI:RefreshSpecializationPicker()
    if DesignerUI.RefreshReplicationDialog then
        DesignerUI:RefreshReplicationDialog()
    end
end

function DesignerUI:RegisterSpecializationToolbarEvents()
    if self.specializationToolbarEventsRegistered == true then return true end
    local Event = YUI.Event
    if not (Event and Event.On) then return false end
    Event:On(
        "YUI_APPEARANCE_ICON_SET_CHANGED",
        "RefreshAppearance",
        specializationToolbarEventOwner
    )
    Event:On(
        "YUI_APPEARANCE_ICON_SCOPE_CHANGED",
        "RefreshAppearance",
        specializationToolbarEventOwner
    )
    self.specializationToolbarEventsRegistered = true
    return true
end

function DesignerUI:UnregisterSpecializationToolbarEvents()
    if self.specializationToolbarEventsRegistered ~= true then return false end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(specializationToolbarEventOwner)
    end
    self.specializationToolbarEventsRegistered = false
    return true
end

function DesignerUI:OnRuntimeContextChanged(detail)
    self:HideSpecializationPicker()
    if self.HideMonitorPicker then self:HideMonitorPicker() end
    if self.HideReplicationDialog then self:HideReplicationDialog() end
    self:RefreshSpecializationToolbar()
    if self.active == true then
        self:ApplyPreview()
        self:Refresh(false, false)
    end
    return true
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local UI = YHUD and YHUD.DesignerUI
local I = UI and UI._internal
local GUI2 = YUI and YUI.GUI2
local Manager = YHUD and YHUD.ResourceManager
if not (I and GUI2 and GUI2.Form and Manager) then return end
local Designer, Catalog = YHUD.Designer, YHUD.ResourceCatalog
local WIDTH, ROW_HEIGHT, LINK_HEIGHT = 368, 50, 20
local LINK_PAINTS = { "color.state.info", "color.badge.purple", "color.badge.green",
    "color.badge.orange", "color.badge.pink" }
local function T(key, fallback) return YHUD:T(key, fallback) end
local function Place(control, parent, x, y, width)
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if width then control:SetWidth(width) end
    control:Show()
end
local function Text(parent, text, secondary)
    local control = GUI2:CreateText(parent, text, secondary and "font.size.sm" or "font.size.md",
        secondary and "color.text.secondary" or "color.text.primary", "LEFT")
    control:SetWordWrap(false)
    if control.SetMaxLines then control:SetMaxLines(1) end
    return control
end
local function Button(parent, text, width, callback, primary)
    return GUI2.Form:CreateButton(parent, { text = text, width = width, height = 26,
        tone = primary and "accent" or "default", onClick = callback })
end
local function ActionButton(parent, icon, tooltip, callback)
    return GUI2.Form:CreateButton(parent, { text = "", width = 24, height = 22,
        microIcon = icon ~= "settings" and icon or nil,
        icon = icon == "settings" and GUI2:GetSettingsIcon("settings") or nil,
        iconSize = 16, iconGap = 0, contentAlign = "center", tone = "default",
        tooltip = tooltip, onClick = callback })
end
local function RefreshResourceLink(button, expanded)
    button:SetText(expanded and T(button.linked and "designer.resource.unlink" or "designer.resource.link",
        button.linked and "断开同行" or "同行等分") or "")
    local width = expanded and button:GetFontString():GetStringWidth() + 38 or 24
    button:SetWidth(math.min(WIDTH - 24, width))
end
local function CloseResourceMenu(self)
    local menu = GUI2.DropdownFrame
    if menu and menu.anchor == self.resourceMenuAnchor then GUI2:CloseDropdown(false) end
    self.resourceMenuAnchor = nil
end
local function CloseTransient(self)
    CloseResourceMenu(self)
    if GUI2.CloseDropdown then GUI2:CloseDropdown(false) end
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    if YUI.HideGameTooltip then YUI.HideGameTooltip() end
end
local function Modal(self, panel)
    panel:Show()
    if GUI2.ShowModalScrim then
        local scrim = GUI2:ShowModalScrim(panel)
        if scrim then scrim:SetScript("OnMouseDown", function() self:CloseResourceDialog() end) end
    end
end
local function FitDialog(self, panel, bodyHeight, top)
    top = top or 108
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", 0, -16)
    panel:SetSize(400, math.max(250, math.min(bodyHeight + top + 64, self.panel:GetHeight() - 32, 640)))
    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -top)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 58)
    panel.body:SetHeight(math.max(1, bodyHeight))
end
local function Context()
    local session = Designer:GetSession()
    local class, spec, form = Designer:GetResourcePreviewContext()
    return session, session and session.selectedGroupId, Manager.ContextKey(class, spec, form)
end
local function ContextText()
    local class, spec, formKey = Designer:GetResourcePreviewContext()
    local locale = YUI.Locale
    local text = (locale and locale.GetClassName and locale:GetClassName(class, class) or class)
        .. " · " .. (locale and locale.GetSpecializationName and locale:GetSpecializationName(spec, tostring(spec)) or tostring(spec))
    for _, form in ipairs(Catalog:GetFormOptions(class,spec)) do
        if form.key == formKey then text = text .. " · " .. T(form.nameKey,form.key) break end
    end
    return text
end
local function Bind(target)
    target.session, target.groupId, target.context = Context()
end
local function Current(target)
    local session, group, context = Context()
    return target and session and not session.draft.closed and not session.draft.combat
        and target.session == session and target.groupId == group and target.context == context
end
local function Find(id)
    for _, item in ipairs(Designer:GetManagedResources(true)) do if item.id == id then return item end end
end
local ISSUE_TEXT = {
    source = { "designer.resource.status.source", "来源待确认" },
    tracking = { "designer.resource.status.tracking", "需启用暴雪追踪" },
    unlearned = { "designer.resource.status.unlearned", "未学习 / 未选择" },
    progress = { "designer.resource.status.progress", "进度暂不可用" },
    maximum = { "designer.resource.status.maximum", "需设置层数上限" },
}
local function IssueText(issue)
    local text = ISSUE_TEXT[issue]
    return text and T(text[1], text[2]) or ""
end
local function Name(preset) return preset.name or T(preset.nameKey, preset.id) end
local function SourceLabels(entry, source)
    local kind = "cast_timer"
    if YHUD:CanUseSkillDurationSource(entry, { view = "bar" }) then kind = "cooldown"
    elseif YHUD:CanUseBarAuraProgress(entry, { view = "bar" }) then
        kind = YHUD:GetFilteredAuraScopeKey(entry) == YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL
            and "target_aura" or "self_aura"
    end
    local labels = {
        cooldown = { "技能冷却", "冷却剩余时间" },
        target_aura = { "目标减益 · 仅本人", "光环剩余时间" },
        self_aura = { "自身增益", "光环剩余时间" },
        cast_timer = { "施法计时", "计时剩余时间" },
    }
    local label = T("designer.resource.source." .. kind, labels[kind][1])
    local metric = source == "spell-charges" and T("designer.bar.spell_charges_short", "技能充能")
        or source == "aura-stacks" and T("designer.bar.aura_stacks", "光环层数")
        or T("designer.resource.time." .. kind, labels[kind][2])
    return label, metric
end
local function Description(preset)
    if preset.customEntry then
        local kind, metric = SourceLabels(preset.customEntry, preset.progress.source)
        return kind .. " · " .. metric
    end
    return (preset.id == "health" or preset.id == "cast" or preset.id == "gcd")
        and T("designer.resource.common", "通用资源") or T("designer.resource.preset", "专精预设")
end

local function CustomMark()
    return "|T" .. GUI2:GetSettingsIcon("diamond") .. ":14:14:0:0|t"
end

-- Display-only numbering uses the whole group, including disabled memberships.
-- Custom IDs retain creation order even when rows move or earlier items disappear.
function I.BuildResourceDisplayLabels()
    local labels, names = {}, {}
    local profile, session = Designer:GetProfile(), Designer:GetSession()
    for _, preset in ipairs(Designer:GetManagedResourceStyles()) do
        local id, name = preset.styleResourceId or preset.id, Name(preset)
        local custom = Manager:IsCustom(id) and Manager:GetCustom(profile, session.selectedGroupId, id)
        local label = { id = id, name = name, custom = type(custom) == "table",
            description = custom and Description({ customEntry = custom.entry, progress = custom.progress }) or Description(preset) }
        labels[id] = label
        names[name] = names[name] or {}
        names[name][#names[name] + 1] = label
    end
    for _, duplicates in pairs(names) do
        table.sort(duplicates, function(a, b)
            if a.custom and b.custom then
                return tonumber(a.id:match("(%d+)$")) < tonumber(b.id:match("(%d+)$"))
            end
            if a.custom ~= b.custom then return not a.custom end
            return a.id < b.id
        end)
        for index, label in ipairs(duplicates) do
            if #duplicates > 1 then
                label.name = string.format(T("designer.resource.numbered_name", "%s %d"), label.name, index)
            end
            label.text = label.name .. (label.custom and (" " .. CustomMark()) or "")
        end
    end
    return labels
end

local resourceTooltipLayer, resourceTooltipHooked
local function RestoreResourceTooltipLayer()
    local state = resourceTooltipLayer
    if not state then return end
    resourceTooltipLayer = nil
    state.tooltip:SetFrameStrata(state.strata)
    state.tooltip:SetFrameLevel(state.level)
end

function I.ShowResourceLabelTooltip(owner, label, issue)
    if not (label and GameTooltip) then return end
    RestoreResourceTooltipLayer()
    if not resourceTooltipHooked then
        GameTooltip:HookScript("OnHide", RestoreResourceTooltipLayer)
        resourceTooltipHooked = true
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(label.name)
    if label.custom then GameTooltip:AddLine(T("designer.resource.custom_title", "自定义资源条"), 0.7, 0.8, 0.85, true) end
    GameTooltip:AddLine(label.description, 0.7, 0.8, 0.85, true)
    if issue then GameTooltip:AddLine(IssueText(issue), 1, 0.75, 0.25, true) end
    local session = Designer:GetSession()
    if session then I.AppendResourceSpecializations(label.id, Designer:GetProfile(), session.selectedGroupId) end
    GameTooltip:Show()
    -- Dropdowns also occupy TOOLTIP strata. Elevate only this resource hint,
    -- and restore the shared GameTooltip when it hides or is shown again.
    local level = owner:GetFrameLevel() + 10
    local menu = GUI2.DropdownFrame
    if menu and menu:IsShown() then level = math.max(level, menu:GetFrameLevel() + 10) end
    resourceTooltipLayer = { tooltip = GameTooltip, strata = GameTooltip:GetFrameStrata(), level = GameTooltip:GetFrameLevel() }
    GameTooltip:SetFrameStrata("TOOLTIP")
    GameTooltip:SetFrameLevel(math.max(level, resourceTooltipLayer.level))
end

function I.HideResourceLabelTooltip(owner)
    if GameTooltip and GameTooltip:IsOwned(owner) and YUI.HideGameTooltip then YUI.HideGameTooltip() end
end

local function RefreshResourceSelector(control, id)
    if not control then return end
    -- A surviving ID may have a new label after a duplicate is added/removed.
    control:SetValue(id or "empty", { silent = true, force = true })
    control.resourceDisplayLabel = I.BuildResourceDisplayLabels()[id]
    Bind(control)
    if control.resourceLabelTooltipBound then return end
    control.resourceLabelTooltipBound = true
    control:HookScript("OnEnter", function(owner)
        if Current(owner) then I.ShowResourceLabelTooltip(owner, owner.resourceDisplayLabel) end
    end)
    control:HookScript("OnLeave", I.HideResourceLabelTooltip)
    control:HookScript("OnHide", I.HideResourceLabelTooltip)
end

function UI:MutateManagedResource(action, id, value)
    if GUI2.ColorPicker and GUI2.ColorPicker.Close then GUI2.ColorPicker:Close("cancel") end
    local selected = self.resourceStyleResourceId
    local previous, oldIndex = Designer:GetManagedResourceStyles()
    for index, preset in ipairs(previous) do if preset.id == selected then oldIndex = index break end end
    local result, items = Designer:MutateResource(action, id, value)
    if not result then
        self:SetMutationError(items, "designer.error_resource", "无法修改资源。")
        return nil, items
    end
    CloseResourceMenu(self)
    if (action == "remove" or action == "remove-all")
        and (selected == id or id == "swingHands" and selected == "swingMainHand") then
        local remaining, retained = Designer:GetManagedResourceStyles(), false
        for _, preset in ipairs(remaining) do if preset.id == selected then retained = true break end end
        if not retained then
            self:StopResourceValuePreview(true, false)
            local adjacent = remaining[math.min(oldIndex or 1, #remaining)]
            self.resourceStyleResourceId = adjacent and adjacent.id or nil
        end
    elseif action == "add" or action == "custom" then
        self.resourceStyleResourceId = result == "swingHands" and "swingMainHand" or result
    end
    local session = Designer:GetSession()
    self.resourceStyleSession = session
    self.resourceStyleContextKey = tostring(session.selectedGroupId)
    self:RefreshAfterStructuralMutation(false)
    return result
end

function UI:ClearResourceOperation(hide)
    local frame = self.resourceOperationFrame
    self.resourceOperationToken, self.resourceOperationFrame = nil, nil
    if frame then
        frame.resourceAccept = nil
        if hide then frame:Hide() end
    end
end

local function OperationTitle(report)
    if report.action == "copy-forms" then
        return T("designer.resource.copy_forms", "复制到其他形态")
    elseif report.action == "copy-all" then
        return report.selectedEnabled and T("designer.resource.copy_enabled", "全专精开启") or T("designer.resource.copy_disabled", "全专精关闭")
    end
    return report.action == "remove-all" and T("designer.resource.remove_all", "全专精移除") or T("designer.resource.remove", "移除资源")
end

local function PaintOperationText(token,text)
    local r,g,b = GUI2:GetColor(token)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return text end
    return string.format("|cff%02x%02x%02x%s|r",math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(b*255+0.5),text)
end

local function OperationText(report,completed)
    -- Keep the confirmed names after removing the final custom definition.
    if not report.resourceNames then
        local labels, names = I.BuildResourceDisplayLabels(), {}
        for index = 1, math.min(3,#report.resourceIds) do
            local label = labels[report.resourceIds[index]]
            names[#names+1] = label and label.name or T("designer.resource.item", "资源")
        end
        if #report.resourceIds > 3 then names[#names+1] = string.format(T("designer.resource.operation_more", "等 %d 项"),#report.resourceIds) end
        report.resourceNames = table.concat(names,"、")
    end
    local resources = PaintOperationText("color.state.info",report.resourceNames)
    local action = report.action
    local text
    if action == "copy-forms" then
        text = string.format(completed and T("designer.resource.prompt.copied_forms", "已复制%s。")
            or T("designer.resource.prompt.copy_forms", "将%s复制到其他形态？"),resources)
        local class,spec = Designer:GetResourcePreviewContext()
        local namesByForm, affected = {}, {}
        for _, form in ipairs(Catalog:GetFormOptions(class,spec)) do namesByForm[form.key] = T(form.nameKey,form.key) end
        for _, context in ipairs(report.contexts) do affected[#affected+1] = namesByForm[context.formKey] or context.formKey end
        if #affected > 0 then text = text .. "\n\n" .. PaintOperationText("color.text.secondary",table.concat(affected,"、")) end
        if not completed then text = text .. "\n\n" .. T("designer.resource.prompt.copy_effect", "同步开关、顺序和同行关系。") end
    elseif action == "copy-all" then
        if report.selectedEnabled then
            text = string.format(completed and T("designer.resource.prompt.enabled_all", "已在所有专精中开启%s。")
                or T("designer.resource.prompt.enable_all", "在所有专精中开启%s？"),resources)
        else
            text = string.format(completed and T("designer.resource.prompt.disabled_all", "已在所有专精中关闭%s。")
                or T("designer.resource.prompt.disable_all", "在所有专精中关闭%s？"),resources)
        end
    else
        text = string.format(completed and T("designer.resource.prompt.removed", "已移除%s。")
            or action == "remove-all" and T("designer.resource.prompt.remove_all", "从所有专精和形态中移除%s？")
            or T("designer.resource.prompt.remove", "从当前列表移除%s？"),resources)
    end
    if report.removesDefinition then
        text = text .. "\n\n" .. PaintOperationText("color.state.warning",completed
            and T("designer.resource.prompt.deleted_settings", "来源和外观设置也已删除。")
            or T("designer.resource.prompt.delete_settings", "来源和外观设置也会删除。"))
    end
    return text
end

local function MoveButton(self, row, step)
    local button = ActionButton(row, step < 0 and "arrow-big-up" or "arrow-big-down", nil, function()
        if not Current(row) then return end
        local action = YUI.API.Frame.IsControlKeyDown() and "move-row" or "move"
        self:MutateManagedResource(action,row.resourceId,step)
    end)
    button:HookScript("OnEnter",function(owner)
        if not Current(row) or not GameTooltip then return end
        local info = Manager:GetMoveInfo(Designer:GetManagedResources(true),row.resourceId,step)
        if not info then return end
        RestoreResourceTooltipLayer()
        GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
        GameTooltip:SetText(step < 0 and T("designer.monitor.move_up", "上移") or T("designer.monitor.move_down", "下移"))
        if info.detaches then
            GameTooltip:AddLine(PaintOperationText("color.state.warning",T("designer.resource.move_detaches", "此次移动会脱离当前同行。")),1,1,1,true)
        end
        if info.linked then
            local hint = step < 0 and T("designer.resource.move_row_up", "Ctrl + 点击：整行上移，保留同行关联。")
                or T("designer.resource.move_row_down", "Ctrl + 点击：整行下移，保留同行关联。")
            GameTooltip:AddLine(hint,0.7,0.8,0.85,true)
            if not info.rowCanMove then
                GameTooltip:AddLine(step < 0 and T("designer.resource.row_at_top", "整行已在最上方。")
                    or T("designer.resource.row_at_bottom", "整行已在最下方。"),0.7,0.8,0.85,true)
            end
        end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave",I.HideResourceLabelTooltip)
    button:HookScript("OnHide",I.HideResourceLabelTooltip)
    return button
end

local function EnsureOperationDialog(self)
    if self.resourceOperationDialog then return self.resourceOperationDialog end
    if not (GUI2.Overlay and GUI2.Overlay.CreateConfirmDialog and self.panel) then return nil end
    local frame = GUI2.Overlay:CreateConfirmDialog(self.panel,{
        width=math.max(280,math.min(400,self.panel:GetWidth()-24)),
        onCancel=function() self:ClearResourceOperation(true) end,
        onAccept=function(dialog)
            local accept = dialog.resourceAccept
            if accept then accept() else self:ClearResourceOperation(true) end
            return false -- Confirmation and its result reuse this same dialog.
        end,
    })
    local scrim = GUI2:CreateFrame(self.panel,{mouse=true})
    scrim:SetAllPoints(self.panel)
    local shade = GUI2:CreateTexture(scrim,{layer="BACKGROUND",colorKey="color.overlay.shadow"})
    shade:SetAllPoints(scrim)
    scrim:SetScript("OnMouseDown",function()self:ClearResourceOperation(true)end)
    scrim:Hide()
    frame:HookScript("OnHide",function()
        scrim:Hide()
        frame.resourceAccept = nil
        if self.resourceOperationFrame == frame then self:ClearResourceOperation(false) end
    end)
    frame.resourceScrim = scrim
    self.resourceOperationDialog = frame
    return frame
end

local function ShowOperationDialog(self,title,text,accept,warning)
    local frame = EnsureOperationDialog(self)
    if not frame then return false end
    local width = math.max(280,math.min(400,self.panel:GetWidth()-24))
    frame:SetWidth(width)
    frame.heading:SetWidth(width-36)
    frame.bodyScroll:SetWidth(width-44)
    frame.bodyScroll.child:SetWidth(width-44)
    frame.body:SetWidth(width-52)
    frame.heading:SetText(title)
    GUI2:SetTextColorKey(frame.heading,warning and "color.state.warning" or accept and "color.text.heading" or "color.state.success")
    local note = PaintOperationText("color.text.secondary",T("designer.resource.prompt.save_note", "保存后生效。"))
    local previousHeight = not accept and frame:IsShown() and frame:GetHeight()
    frame:SetMessage(text .. "\n\n" .. note,math.max(154,math.min(420,self.panel:GetHeight()-24)))
    if previousHeight and previousHeight > frame:GetHeight() then
        frame:SetHeight(previousHeight)
        frame.bodyScroll:SetHeight(previousHeight-110)
        frame.bodyScroll.child:SetHeight(math.max(frame.body:GetHeight(),frame.bodyScroll:GetHeight()))
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER",self.panel,"CENTER")
    frame:SetFrameStrata(self.panel:GetFrameStrata())
    local level = self.panel:GetFrameLevel()
    frame.resourceScrim:SetFrameStrata(self.panel:GetFrameStrata())
    frame.resourceScrim:SetFrameLevel(level+10)
    frame:SetFrameLevel(level+11)
    frame.resourceAccept = accept
    frame.cancel:SetShown(accept ~= nil)
    frame.ok:SetText(accept and (warning and T("designer.resource.prompt.remove_button", "移除")
        or T("designer.resource.prompt.copy_button", "复制")) or T("designer.resource.operation_ack", "知道了"))
    if GUI2.ApplyButtonStyle then
        GUI2:ApplyButtonStyle(frame.ok,warning and "warningFilled" or accept and "successFilled" or "grayFilled")
    end
    self.resourceOperationFrame = frame
    frame.resourceScrim:Show()
    frame:Show()
    return true
end

function UI:ShowResourceOperationResult(text)
    local status = (text:match("^[^\n]+") or text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    self:SetStatus(status)
    return ShowOperationDialog(self,T("designer.resource.operation_result", "操作结果"),text)
end

function UI:RequestResourceOperation(action,id)
    if self.busyKind or not Find(id) then return false end
    self:ClearResourceOperation(true)
    CloseTransient(self)
    local token = {}
    Bind(token)
    if not Current(token) then return false end
    local class,spec,form = Designer:GetResourcePreviewContext()
    local report,code = Manager:PreviewOperation(YHUD:GetResourceProfile(Designer:GetProfile(),token.groupId),class,spec,form,action,id)
    if not report then
        self:SetMutationError(code,"designer.error_resource","无法修改资源。")
        self:ShowResourceOperationResult(code == "resource-limit"
            and T("designer.resource.operation_limit", "目标列表已满，无法复制。")
            or T("designer.resource.operation_failed", "操作失败，未修改设置。"))
        return false
    end
    local text = OperationText(report)
    if #report.contexts == 0 then
        self:ShowResourceOperationResult(T("designer.resource.operation_no_changes", "已经一致，无需修改。"))
        return true
    end
    token.revision = token.session.draft.revision
    token.accept = function()
        if self.resourceOperationToken ~= token then return end
        if self.busyKind or not Current(token) or token.session.draft.revision ~= token.revision then
            self:ClearResourceOperation(false)
            self:ShowResourceOperationResult(T("designer.resource.operation_stale", "设置已变化，请重新操作。"))
            return
        end
        self:ClearResourceOperation(false)
        local result = action == "copy-all" and self:CopyResourcePresetEnabled(id)
            or action ~= "copy-all" and self:MutateManagedResource(action,id)
        if result then
            self:ShowResourceOperationResult(OperationText(report,true))
        else self:ShowResourceOperationResult(T("designer.resource.operation_failed", "操作失败，未修改设置。")) end
    end
    self.resourceOperationToken = token
    local shown = ShowOperationDialog(self,OperationTitle(report),text,token.accept,action == "remove" or action == "remove-all")
    if not shown then self:ClearResourceOperation(false) end
    return shown
end

function UI:ShowResourceMore(row)
    if not Current(row) or not Find(row.resourceId) then return end
    local menu = GUI2.DropdownFrame
    if menu and menu:IsShown() and menu.anchor == row.more then CloseResourceMenu(self) return end
    CloseTransient(self)
    local target, id, options = {}, row.resourceId, {}
    Bind(target)
    if Manager:IsCustom(id) then
        options[#options + 1] = { text = T("designer.resource.edit_progress", "编辑进度来源"), func = function()
            if not Current(target) then return end
            local preset = Find(id)
            if preset and preset.customEntry then self:OpenCustomResourceEditor(preset.customEntry, id) end
        end }
    end
    options[#options + 1] = { text = T("designer.resource.edit_style", "设置资源外观"), func = function()
        if not Current(target) or not Find(id) then return end
        self.resourceStyleResourceId = id == "swingHands" and "swingMainHand" or id
        self:SetPropertyPage("appearance")
    end }
    local classFile, specID, formKey = Designer:GetResourcePreviewContext()
    if formKey and #Catalog:GetFormOptions(classFile, specID) > 1 then
        local preset = Find(id)
        options[#options + 1] = {
            text = preset.resourceRowKey and T("designer.resource.copy_row_forms", "复制同行到其他形态")
                or T("designer.resource.copy_forms", "复制到其他形态"),
            func = function()
                if self.busyKind or not Current(target) or not Find(id) then return end
                self:RequestResourceOperation("copy-forms",id)
            end,
        }
    end
    if not Manager:IsCustom(id) then
        local enabled = Find(id).enabled == true
        options[#options + 1] = {
            text = enabled and T("designer.resource.copy_enabled", "全专精开启")
                or T("designer.resource.copy_disabled", "全专精关闭"),
            func = function()
                if self.busyKind or not Current(target) then return end
                local preset = Find(id)
                if not preset or (preset.enabled == true) ~= enabled then return end
                CloseResourceMenu(self)
                self:RequestResourceOperation("copy-all",id)
            end,
        }
    end
    options[#options + 1] = { text = T("designer.resource.remove", "移除资源"), func = function()
        if Current(target) and Find(id) then self:RequestResourceOperation("remove", id) end
    end }
    options[#options + 1] = { text = T("designer.resource.remove_all", "全专精移除"), func = function()
        if not self.busyKind and Current(target) and Find(id) then self:RequestResourceOperation("remove-all", id) end
    end }
    self.resourceMenuAnchor = row.more
    GUI2:OpenDropdown(row.more, options, nil, nil, 176)
end

local OldRefreshMonitor = I.RefreshResourceMonitorPage
function I.RefreshResourceMonitorPage(self, profile, group)
    if group.contentPolicy ~= "resource-only" then
        for _, row in ipairs(self.managedResourceRows or {}) do row:Hide() end
        if self.managedResourceHeading then
            self.managedResourceHeading:Hide()
            self.managedResourceAdd:Hide()
            self.managedResourceHint:Hide()
        end
        return OldRefreshMonitor(self, profile, group)
    end
    local root, body = self.v2PageRoots.resourceMonitor, self.groupInspectorBody
    body:Show()
    for _, control in ipairs(self.resourceBaseControls or {}) do control:Hide() end
    for _, row in ipairs(self.resourcePresetRows or {}) do row:Hide() end
    if self.resourceEmptyGroupHint then self.resourceEmptyGroupHint:Hide() end
    local class, spec, form = Designer:GetResourcePreviewContext()
    self.resourceClassDropdown:SetValue(class, true)
    self.resourceSpecDropdown:SetValue(spec, true)
    for index = 1, 4 do
        local control = self.resourceBaseControls[index]
        Place(control, body, (index % 2 == 0) and 192 or 0, index <= 2 and 0 or 20, 176)
    end
    local top = 64
    if form then
        self.resourceFormDropdown:SetValue(form, true)
        Place(self.resourceBaseControls[5], body, 0, top)
        Place(self.resourceFormDropdown, body, 0, top + 20, WIDTH)
        top = top + 64
    end
    if not self.managedResourceHeading then
        self.managedResourceHeading = Text(root, "")
        self.managedResourceAdd = Button(root, T("designer.resource.add", "+ 添加资源"), 108, function() self:OpenResourceAdd() end, true)
        I.ApplySolidMonitorButton(self.managedResourceAdd, "color.badge.orange", "color.state.warning")
        self.managedResourceHint = Text(root, "", true)
        self.managedResourceRows = {}
    end
    Manager:RefreshCatalog(profile)
    local presets = Designer:GetManagedResources(true)
    local labels = I.BuildResourceDisplayLabels()
    self.managedResourceHeading:SetText(T("designer.resource.added", "已添加资源") .. "  " .. #presets)
    Place(self.managedResourceHeading, body, 0, top + 5, WIDTH - 116)
    Place(self.managedResourceAdd, body, WIDTH - 108, top)
    self.managedResourceAdd:SetDisabled(#presets >= Manager.LIMIT)
    top = top + 36
    local linkGroupIndex = 0
    for index, preset in ipairs(presets) do
        local row = self.managedResourceRows[index]
        if not row then
            row = GUI2:CreateFrame(root, { width = WIDTH, height = ROW_HEIGHT, mouse = true })
            self.managedResourceRows[index] = row
            row.swatch = GUI2:CreateTexture(row, { layer = "ARTWORK" })
            row.swatch:SetSize(10, 10)
            row.swatch:SetPoint("TOPLEFT", 2, -10)
            row.divider = GUI2:CreateTexture(row, { layer = "BORDER", colorKey = "color.border.default" })
            row.divider:SetHeight(GUI2:GetPixelSize(row, 1, 1))
            row.divider:SetPoint("LEFT", row, "TOPLEFT", 0, LINK_HEIGHT * 0.5)
            row.divider:SetPoint("RIGHT", row, "TOPRIGHT", 0, LINK_HEIGHT * 0.5)
            row.label, row.status, row.description = Text(row, ""), Text(row, "", true), Text(row, "", true)
            row.customMark = Text(row, CustomMark(), true)
            if GUI2.SetTextColorKey then GUI2:SetTextColorKey(row.status, "color.state.warning") end
            row.up = MoveButton(self,row,-1)
            row.down = MoveButton(self,row,1)
            row.toggle = GUI2.Form:CreateSwitch(row, { width = 48, height = 22, set = function(value)
                if not self.v2Refreshing and Current(row) then self:MutateManagedResource("enabled", row.resourceId, value) end
            end })
            row.more = ActionButton(row, "settings", T("designer.resource.actions", "资源操作"), function() self:ShowResourceMore(row) end)
            row.linkBackground = GUI2:CreateTexture(row, { layer = "BACKGROUND", colorKey = "color.accent.soft" })
            row.linkBackground:SetAlpha(0.18)
            row.linkMarker = GUI2:CreateTexture(row, { layer = "ARTWORK", colorKey = "color.accent.primary" })
            row.linkMarker:SetWidth(2)
            row.link = GUI2.Form:CreateButton(row, { text = "", width = 24, height = LINK_HEIGHT,
                icon = GUI2:GetSettingsIcon("link-2"), iconSize = 14, iconCrop = false,
                contentAlign = "center", tone = "default", onClick = function()
                    if not Current(row) then return end
                    local previous
                    for _, item in ipairs(Designer:GetManagedResources(true)) do
                        if item.id == row.resourceId then
                            if previous and previous == row.previousResourceId then
                                self:MutateManagedResource("link", row.resourceId, not row.link.linked)
                            end
                            return
                        end
                        previous = item.id
                    end
                end })
            row.link:SetPoint("BOTTOM", row, "TOP", 0, 0)
            row.link:HookScript("OnEnter", function(button)
                if Current(row) then RefreshResourceLink(button, true) end
            end)
            row.link:HookScript("OnLeave", function(button) RefreshResourceLink(button, false) end)
            row.link:HookScript("OnHide", function(button) RefreshResourceLink(button, false) end)
            row:SetScript("OnEnter", function()
                if Current(row) then I.ShowResourceLabelTooltip(row, row.displayLabel, row.issue) end
            end)
            row:SetScript("OnLeave", I.HideResourceLabelTooltip)
            row:SetScript("OnHide", function()
                I.HideResourceLabelTooltip(row)
                row.session = nil
            end)
        end
        I.HideResourceLabelTooltip(row.up)
        I.HideResourceLabelTooltip(row.down)
        Bind(row)
        local joined = preset.joinPrevious == true
        local linked = joined or presets[index + 1] and presets[index + 1].joinPrevious == true
        if linked and not joined then linkGroupIndex = linkGroupIndex + 1 end
        if linked then
            local paint = LINK_PAINTS[(linkGroupIndex - 1) % #LINK_PAINTS + 1]
            GUI2:SetTexturePaintKey(row.linkBackground, paint)
            GUI2:SetTexturePaintKey(row.linkMarker, paint)
        end
        row.previousResourceId = presets[index - 1] and presets[index - 1].id
        row.link.linked = joined
        row.link:SetSelected(joined)
        row.link:SetShown(index > 1)
        row.divider:SetShown(index > 1)
        RefreshResourceLink(row.link, false)
        row.linkBackground:ClearAllPoints()
        row.linkBackground:SetPoint("TOPLEFT", row, "TOPLEFT", 0, joined and LINK_HEIGHT or 0)
        row.linkBackground:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.linkBackground:SetShown(linked == true)
        row.linkMarker:ClearAllPoints()
        row.linkMarker:SetPoint("TOPLEFT", row, "TOPLEFT", 0, joined and LINK_HEIGHT or 0)
        row.linkMarker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.linkMarker:SetShown(linked == true)
        row.displayLabel = labels[preset.styleResourceId or preset.id]
        row.resourceId, row.fullName, row.issue = preset.id, row.displayLabel.name, preset.issue
        row.label:SetText(row.fullName)
        row.status:SetText(IssueText(preset.issue))
        -- Release the previous width before measuring: pooled FontStrings can
        -- otherwise keep reporting the already truncated name or status.
        row.label:SetWidth(0)
        row.status:SetWidth(0)
        local statusWidth = preset.issue and math.min(100, row.status:GetStringWidth() + 2) or 0
        local markWidth = row.displayLabel.custom and 16 or 0
        local nameWidth = math.min(row.label:GetStringWidth() + 2, WIDTH - 168 - statusWidth - markWidth)
        Place(row.label, row, 20, 7, nameWidth)
        Place(row.customMark, row, 22 + nameWidth, 7, 14)
        row.customMark:SetShown(row.displayLabel.custom)
        row.customMark:SetAlpha(preset.enabled and 1 or 0.5)
        Place(row.status, row, 26 + nameWidth + markWidth, 7, math.max(1, statusWidth))
        row.status:SetShown(preset.issue ~= nil)
        row.description:SetText(Description(preset))
        Place(row.description, row, 20, 28, WIDTH - 20)
        Place(row.up, row, WIDTH - 136, 3)
        Place(row.down, row, WIDTH - 108, 3)
        Place(row.toggle, row, WIDTH - 80, 3)
        Place(row.more, row, WIDTH - 24, 3)
        row.up:SetDisabled(index == 1)
        row.down:SetDisabled(index == #presets)
        row.toggle:SetValue(preset.enabled == true, true)
        row.label:SetAlpha(preset.enabled and 1 or 0.5)
        row.description:SetAlpha(preset.enabled and 1 or 0.5)
        local color = YHUD:GetResourceSetting(profile, preset.styleResourceId or preset.id, group.id).fillColor or preset.color
        row.swatch:SetColorTexture(color.r or color[1], color.g or color[2], color.b or color[3], preset.enabled and 1 or 0.4)
        if index > 1 then top = top + LINK_HEIGHT end
        Place(row, body, 0, top, WIDTH)
        top = top + ROW_HEIGHT
    end
    for index = #presets + 1, #self.managedResourceRows do self.managedResourceRows[index]:Hide() end
    self.managedResourceHint:SetText(#presets == 0 and T("designer.resource.empty", "尚未添加资源，点击上方按钮添加。")
        or T("designer.resource.list_hint", "关闭后保留配置；点击齿轮可设置或移除资源。"))
    Place(self.managedResourceHint, body, 0, top + 10, WIDTH)
    I.SetResourceContentHeight(self, top + 56)
end

function UI:EnsureResourceDialog()
    if self.resourceDialog then return self.resourceDialog end
    local panel = GUI2:CreatePanel(self.panel, { width = 400, height = 600, surface = "color.surface.popup", border = "color.border.accent" })
    panel:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", 0, -16)
    panel:SetFrameLevel(self.panel:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function() end)
    panel:Hide()
    self.resourceDialog = panel
    panel.title = Text(panel, "")
    Place(panel.title, panel, 16, 16, 300)
    if GUI2.SetTextColorKey then GUI2:SetTextColorKey(panel.title, "color.text.heading") end
    panel.contextLabel = Text(panel, "", true)
    Place(panel.contextLabel, panel, 16, 40, WIDTH)
    panel.close = Button(panel, "×", 28, function() self:CloseResourceDialog() end)
    panel.close:SetPoint("TOPRIGHT", -12, -10)
    panel.tabs = GUI2.Form:CreateSegmentedControl(panel, { width = WIDTH, height = 30,
        items = {
            { value = "preset", text = T("designer.resource.preset", "专精预设") },
            { value = "common", text = T("designer.resource.common", "通用资源") },
            { value = "custom", text = T("designer.resource.custom", "自定义") },
        }, set = function(value) if Current(panel) then self:OpenResourceAdd(value) end end })
    Place(panel.tabs, panel, 16, 68)
    panel.scroll = GUI2:CreateScrollFrame(panel, { width = WIDTH, height = 480 })
    panel.scroll:SetPoint("TOPLEFT", 16, -96)
    panel.scroll:SetPoint("BOTTOMRIGHT", -16, 16)
    panel.body = panel.scroll.child or panel.scroll.scrollChild
    panel.controls, panel.rows = {}, {}
    panel.cancel = Button(panel, T("designer.cancel", "取消"), 64, function() self:CloseResourceDialog() end)
    panel.cancel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    panel:SetScript("OnHide", function()
        if panel.name then panel.name:ClearFocus() end
        if panel.positions then panel.positions:ClearFocus() end
        panel.session, panel.entry, panel.editId = nil, nil, nil
        if GUI2.CloseDropdown then GUI2:CloseDropdown(false) end
    end)
    return panel
end

function UI:IsResourceSelectionCurrent()
    return Current(self.resourceDialog)
end

function UI:CloseResourceDialog()
    CloseTransient(self)
    if self.monitorPickerResourceSelection then self:HideMonitorPicker(true) end
    local panel = self.resourceDialog
    if panel then
        panel:Hide()
        panel.session, panel.entry, panel.editId = nil, nil, nil
    end
end

local function ResetDialog(panel)
    for _, control in ipairs(panel.controls) do control:Hide() end
    for _, row in ipairs(panel.rows) do row:Hide() end
    panel.body:SetHeight(1)
    if panel.scroll.SetVerticalScroll then panel.scroll:SetVerticalScroll(0) end
end

function UI:OpenResourceAdd(category)
    CloseTransient(self)
    if self.monitorPickerResourceSelection then self:HideMonitorPicker(true) end
    Manager:RefreshCatalog()
    local panel = self:EnsureResourceDialog()
    ResetDialog(panel)
    Bind(panel)
    panel.entry, panel.editId = nil, nil
    panel.category = category or "preset"
    panel.title:SetText(T("designer.resource.add_title", "添加资源"))
    panel.contextLabel:SetText(ContextText())
    panel.tabs:SetValue(panel.category, true)
    panel.tabs:Show()
    panel.cancel:ClearAllPoints()
    panel.cancel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    if panel.category == "custom" then
        panel:Hide()
        Bind(panel)
        return self:OpenMonitorPicker(panel.groupId, "cooldown", true)
    end
    local choices, present = {}, {}
    for _, preset in ipairs(Designer:GetManagedResources(true)) do present[preset.id] = true end
    local class, spec, form = Designer:GetResourcePreviewContext()
    local profile = YHUD:GetResourceProfile(Designer:GetProfile(), panel.groupId)
    local presets = form and Catalog:GetFormPresets(profile, class, spec, form) or Catalog:GetPresets(profile, class, spec)
    for _, preset in ipairs(Catalog:GetDisplayPresets(profile, presets)) do
        local common = preset.id == "health" or preset.id == "cast" or preset.id == "gcd"
        if not present[preset.id] and common == (panel.category == "common") then choices[#choices + 1] = preset end
    end
    for index, preset in ipairs(choices) do
        local row = panel.rows[index]
        if not row then
            row = GUI2:CreatePanel(panel.body, { width = WIDTH - 16, height = 56, surface = "color.control.bg", border = "color.border.subtle" })
            row.swatch = GUI2:CreateTexture(row, { layer = "ARTWORK" })
            row.swatch:SetSize(10, 10)
            row.swatch:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.name, row.description = Text(row, ""), Text(row, "", true)
            Place(row.name, row, 30, 8, WIDTH - 140)
            Place(row.description, row, 30, 30, WIDTH - 140)
            row.add = Button(row, T("designer.resource.add_short", "添加"), 64, function()
                if not Current(panel) then self:CloseResourceDialog() return end
                if self:MutateManagedResource("add", row.id) then self:OpenResourceAdd(panel.category) end
            end, true)
            row.add:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            panel.rows[index] = row
        end
        row.id = preset.id
        row.name:SetText(Name(preset))
        row.description:SetText(preset.id == "gcd" and T("designer.resource.gcd_hint", "玩家公共冷却进度") or Description(preset))
        local color = preset.color
        row.swatch:SetColorTexture(color.r or color[1], color.g or color[2], color.b or color[3], 1)
        Place(row, panel.body, 0, (index - 1) * 64)
    end
    if not panel.empty then
        panel.empty = Text(panel.body, T("designer.resource.all_added", "此分类的资源已全部添加。"), true)
        panel.controls[#panel.controls + 1] = panel.empty
    end
    if #choices == 0 then Place(panel.empty, panel.body, 0, 20, WIDTH - 16) end
    FitDialog(self, panel, math.max(80, #choices * 64))
    Modal(self, panel)
end

function UI:ConfigureResourcePicker(resourceSelection)
    local picker = self.monitorPicker
    if not picker then return end
    if not self.resourcePickerTabs and resourceSelection then
        self.resourcePickerContext = Text(picker, "", true)
        self.resourcePickerTabs = GUI2.Form:CreateSegmentedControl(picker, { width = WIDTH, height = 30,
            items = {
                { value = "preset", text = T("designer.resource.preset", "专精预设") },
                { value = "common", text = T("designer.resource.common", "通用资源") },
                { value = "custom", text = T("designer.resource.custom", "自定义") },
            }, set = function(value) if self:IsResourceSelectionCurrent() then self:OpenResourceAdd(value) end end })
        self.resourcePickerFamily = GUI2.Form:CreateSegmentedControl(picker, { width = WIDTH, height = 28,
            items = {
                { value = "cooldown", text = T("designer.resource.family.cooldown", "冷却") },
                { value = "buff", text = T("designer.resource.family.buff", "光环") },
            }, set = function(value)
                if not self:IsResourceSelectionCurrent() then return end
                self:OpenMonitorPicker(self.resourceDialog.groupId, value, true)
            end })
        self.resourcePickerCancel = Button(picker, T("designer.cancel", "取消"), 64, function() self:CloseResourceDialog() end)
    end
    for _, control in ipairs({self.resourcePickerContext, self.resourcePickerTabs, self.resourcePickerFamily, self.resourcePickerCancel}) do
        control:SetShown(resourceSelection)
    end
    picker:ClearAllPoints()
    self.monitorPickerSearch:ClearAllPoints()
    self.monitorPickerScroll:ClearAllPoints()
    if resourceSelection then
        CloseTransient(self)
        picker:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", 0, -16)
        picker:SetSize(400, math.min(620, self.panel:GetHeight() - 32))
        self.resourcePickerContext:SetText(ContextText() .. " · " .. T("designer.resource.step_source", "选择监控对象"))
        Place(self.resourcePickerContext, picker, 16, 40, WIDTH)
        Place(self.resourcePickerTabs, picker, 16, 66)
        Place(self.resourcePickerFamily, picker, 16, 108)
        self.resourcePickerTabs:SetValue("custom", true)
        self.resourcePickerFamily:SetValue(self.monitorPickerSemanticFamily, true)
        self.resourcePickerCancel:ClearAllPoints()
        self.resourcePickerCancel:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -16, 16)
        self.monitorPickerSearch:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -150)
        self.monitorPickerScroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -190)
        self.monitorPickerScroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -16, 56)
        Modal(self, picker)
    else
        picker:SetAllPoints(self.panel)
        self.monitorPickerSearch:SetPoint("TOPLEFT", 16, -50)
        self.monitorPickerScroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -90)
        self.monitorPickerScroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -16, 16)
    end
end

local function ProgressOptions(entry, progress)
    local caps, options = Manager:Capabilities(entry) or {}, {}
    for _, source in ipairs({ "time", "spell-charges", "aura-stacks" }) do
        if caps[source] or progress.source == source then
            options[#options + 1] = { value = source, text = source == "time" and select(2, SourceLabels(entry, source)) or T(
                source == "spell-charges" and "designer.bar.spell_charges" or "designer.bar.aura_stacks",
                source == "spell-charges" and "技能充能（含恢复进度）" or "光环层数") }
        end
    end
    return options
end

function UI:OpenCustomResourceEditor(entry, id)
    CloseTransient(self)
    local panel = self:EnsureResourceDialog()
    ResetDialog(panel)
    Bind(panel)
    local custom = id and Manager:GetCustom(Designer:GetProfile(), panel.groupId, id)
    if id and not custom then return false end
    panel.entry, panel.editId = YHUD:CopyValue(entry), id
    panel.progress = YHUD:NormalizeBarProgress(custom and custom.progress)
    panel.title:SetText(T("designer.resource.custom_title", "自定义资源条"))
    panel.contextLabel:SetText(T("designer.resource.step_progress", "设置进度 · 样式在布局、外观和文字分页调整"))
    panel.tabs:Hide()
    local body = panel.body
    if not panel.source then
        local function Keep(control) panel.controls[#panel.controls + 1] = control return control end
        local function Label(text) return Keep(Text(body, text)) end
        local function Dropdown(options, set)
            return Keep(GUI2.Form:CreateDropdown(body, { width = WIDTH - 16, options = options, set = function(value)
                if Current(panel) and not panel.refreshing then set(value); self:RefreshCustomResourceEditor() end
            end }))
        end
        panel.object = Label("")
        panel.identity = Label("")
        if GUI2.SetTextColorKey then GUI2:SetTextColorKey(panel.identity, "color.text.secondary") end
        panel.nameLabel = Label(T("designer.resource.name", "资源名称"))
        panel.name = Keep(GUI2.Form:CreateEditBox(body, { width = WIDTH - 16, autoFocus = false }))
        panel.sourceLabel = Label(T("designer.bar.source", "进度来源"))
        panel.source = Dropdown(function() return ProgressOptions(panel.entry, panel.progress) end, function(value)
            panel.progress = YHUD:SwitchBarProgressSource(panel.progress, value)
        end)
        panel.maximumLabel = Label(T("designer.bar.maximum_mode", "满条层数"))
        panel.maximumMode = Dropdown({
            { value = "auto", text = T("designer.bar.maximum_auto", "自动识别") },
            { value = "custom", text = T("designer.bar.maximum_custom", "手动设置") },
        }, function(value) panel.progress.maximumMode = value end)
        panel.maximum = Keep(GUI2.Form:CreateSlider(body, { width = WIDTH - 70, inline = true, inputWidth = 44,
            min = 1, max = 100, step = 1, set = function(value) if Current(panel) and not panel.refreshing then panel.progress.maximum = value end end }))
        panel.tickLabel = Label(T("designer.bar.ticks", "刻度线"))
        panel.ticks = Dropdown(function()
            local options = { { value = "off", text = T("designer.bar.ticks_off", "关闭") } }
            if panel.progress.source ~= "time" then options[#options + 1] = { value = panel.progress.source,
                text = T("designer.resource.ticks_auto", "按层数 / 充能次数") } end
            options[#options + 1] = { value = "custom", text = T("designer.bar.ticks_custom", "自定义百分比") }
            return options
        end, function(value) panel.progress.ticks.mode = value end)
        panel.positionsLabel = Label(T("designer.bar.positions", "位置（%）"))
        panel.positions = Keep(GUI2.Form:CreateEditBox(body, { width = WIDTH - 16, autoFocus = false,
            tooltip = T("designer.bar.positions_hint", "填写 0 到 100 之间的百分比，用逗号分隔；最多 32 个位置。") }))
        panel.step = Keep(GUI2.Form:CreateSlider(body, { width = WIDTH - 70, inline = true, inputWidth = 44,
            min = 1, max = 100, step = 1, set = function(value) if Current(panel) and not panel.refreshing then panel.progress.ticks.step = value end end }))
        panel.status = Keep(Text(body, "", true))
        panel.status:SetWordWrap(true)
        if panel.status.SetMaxLines then panel.status:SetMaxLines(2) end
        panel.status:SetHeight(36)
        panel.save = Keep(Button(panel, T("designer.resource.save", "保存资源"), 136, function()
            if not Current(panel) then self:CloseResourceDialog() return end
            local progress = YHUD:CopyValue(panel.progress)
            if progress.ticks.mode == "custom" then
                local positions = {}
                for part in panel.positions:GetText():gsub("，", ","):gmatch("[^,%s]+") do
                    local value = tonumber(part)
                    if not value or value ~= value or value <= 0 or value >= 100 or #positions >= 32 then
                        panel.status:SetText(T("designer.bar.positions_hint", "填写 0 到 100 之间的百分比，用逗号分隔；最多 32 个位置。"))
                        FitDialog(self, panel, panel.statusOffset + 40, 76)
                        return
                    end
                    positions[#positions + 1] = value
                end
                progress.ticks.positions = positions
            end
            local name = panel.name:GetText():match("^%s*(.-)%s*$")
            local value = { entry = panel.entry, progress = progress, name = name ~= "" and name or panel.entry.name }
            local saved = self:MutateManagedResource(panel.editId and "edit" or "custom", panel.editId, value)
            if saved then self:CloseResourceDialog() end
        end, true))
    end
    panel.name:SetText(custom and custom.name or entry.name or "")
    panel.positions:SetText(table.concat(panel.progress.ticks.positions, ", "))
    Modal(self, panel)
    self:RefreshCustomResourceEditor()
    return true
end

function UI:RefreshCustomResourceEditor()
    local panel = self.resourceDialog
    if not panel or not panel.entry then return end
    panel.refreshing = true
    for _, control in ipairs(panel.controls) do control:Hide() end
    local body, progress = panel.body, panel.progress
    panel.object:SetText(panel.entry.name or "")
    Place(panel.object, body, 0, 0, WIDTH - 16)
    panel.identity:SetText(SourceLabels(panel.entry, progress.source) .. " · ID " .. tostring(panel.entry.spellId or ""))
    Place(panel.identity, body, 0, 24, WIDTH - 16)
    Place(panel.nameLabel, body, 0, 62)
    Place(panel.name, body, 0, 84)
    Place(panel.sourceLabel, body, 0, 128)
    Place(panel.source, body, 0, 150)
    panel.source:SetValue(progress.source, true)
    local y = 194
    if progress.source == "aura-stacks" then
        Place(panel.maximumLabel, body, 0, y)
        Place(panel.maximumMode, body, 0, y + 22)
        panel.maximumMode:SetValue(progress.maximumMode, true)
        y = y + 66
        if progress.maximumMode == "custom" then
            Place(panel.maximum, body, 0, y)
            panel.maximum:SetValue(progress.maximum, true)
            y = y + 42
        end
    end
    Place(panel.tickLabel, body, 0, y)
    Place(panel.ticks, body, 0, y + 22)
    panel.ticks:SetValue(progress.ticks.mode, true)
    y = y + 66
    if progress.ticks.mode == "custom" then
        panel.positionsLabel:SetText(T("designer.bar.positions", "位置（%）"))
        Place(panel.positionsLabel, body, 0, y)
        Place(panel.positions, body, 0, y + 22)
        y = y + 66
    elseif progress.ticks.mode == "aura-stacks" then
        panel.positionsLabel:SetText(T("designer.bar.tick_step", "每隔层数"))
        Place(panel.positionsLabel, body, 0, y)
        Place(panel.step, body, 0, y + 22)
        panel.step:SetValue(progress.ticks.step, true)
        y = y + 66
    end
    panel.statusOffset = y
    panel.status:SetText(IssueText(Manager:Issue({ entry = panel.entry, progress = progress }, true)))
    Place(panel.status, body, 0, y, WIDTH - 16)
    panel.save:ClearAllPoints()
    panel.save:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
    panel.save:SetText(panel.editId and T("designer.resource.save", "保存资源") or T("designer.resource.add_short", "添加"))
    panel.save:Show()
    panel.cancel:ClearAllPoints()
    panel.cancel:SetPoint("RIGHT", panel.save, "LEFT", -8, 0)
    FitDialog(self, panel, y + (panel.status:GetText() ~= "" and 40 or 8), 76)
    panel.refreshing = nil
end

function UI:ShowEmptyResourceSelection(page)
    local root = self.v2PageRoots[page]
    self.resourceEmptySelections = self.resourceEmptySelections or {}
    local controls = self.resourceEmptySelections[page]
    if not controls then
        controls = {}
        self.resourceEmptySelections[page] = controls
        controls.label = Text(root, T("designer.resource.select", "当前资源"))
        controls.select = GUI2.Form:CreateDropdown(root, { width = WIDTH, options = {
            { value = "empty", text = T("designer.resource.none", "无资源") },
        } })
        controls.add = Button(root, T("designer.resource.add", "+ 添加资源"), 136, function() self:OpenResourceAdd() end)
    end
    Place(controls.label, root, 0, 4)
    Place(controls.select, root, 0, 28, WIDTH)
    controls.select:SetValue("empty", true)
    controls.select:SetDisabled(true)
    Place(controls.add, root, 0, 76)
    I.SetResourceContentHeight(self, 130)
end

function UI:RefreshResourcePageSelection(profile, group, page)
    local token = self.resourceOperationToken
    if token and (not Current(token) or token.session.draft.revision ~= token.revision) then self:ClearResourceOperation(true) end
    for _, controls in pairs(self.resourceEmptySelections or {}) do for _, control in pairs(controls) do control:Hide() end end
    if self.resourceLayoutItem then self.resourceLayoutItem:Hide() end
    CloseResourceMenu(self)
    if self.resourceDialog and (self.resourceDialog:IsShown() or self.monitorPickerResourceSelection) and not Current(self.resourceDialog) then self:CloseResourceDialog() end
    if group.layout ~= "resource" then return end
    if page == "appearance" or page == "text" then
        if not self.resourceStyleResourceId then self:ShowEmptyResourceSelection(page)
        elseif group.contentPolicy ~= "cast-only" then
            local controls = page == "appearance" and self.resourceV2Appearance or self.resourceV2Text
            RefreshResourceSelector(controls and controls.resource, self.resourceStyleResourceId)
        end
        return
    end
    if page ~= "layout" or group.contentPolicy == "cast-only" then return end
    local parent = self.v2PageRoots.layout
    if not self.resourceLayoutItem then
        local box = GUI2:CreateFrame(parent, { width = WIDTH, height = 148, mouse = false })
        self.resourceLayoutItem = box
        box.label = Text(box, T("designer.resource.select", "当前资源"))
        box.select = GUI2.Form:CreateDropdown(box, { width = WIDTH, options = function()
            local options = I.BuildResourceOptions()
            return #options > 0 and options or {{value="empty",text=T("designer.resource.none", "无资源")}}
        end,
            set = function(value) if not self.v2Refreshing then self:SelectResourceStyleResource(value) end end })
        box.heightLabel = Text(box, T("designer.resource.height_override", "覆盖高度"))
        box.override = GUI2.Form:CreateSwitch(box, { width = 48, set = function(value)
            if self.v2Refreshing or not self.resourceStyleResourceId then return end
            local layout = YHUD:GetResourceGroupLayout(Designer:GetProfile(), Designer:GetSession().selectedGroupId)
            local result = Designer:SetResourceSetting(self.resourceStyleResourceId, { heightOverride = value and layout.height or false })
            if result then self:PreviewSelectedGroup(); self:Refresh(false, false) end
        end })
        box.height = GUI2.Form:CreateSlider(box, { width = 250, inline = true, inputWidth = 44, min = 2, max = 128, step = 1,
            set = function(value)
                if self.v2Refreshing or not self.resourceStyleResourceId then return end
                local result = Designer:SetResourceSetting(self.resourceStyleResourceId, { heightOverride = value })
                if result then self:PreviewSelectedGroup() end
            end })
        Place(box.label, box, 0, 0)
        Place(box.select, box, 0, 24)
        Place(box.heightLabel, box, 0, 68)
        Place(box.override, box, WIDTH - 48, 62)
        Place(box.height, box, 0, 104)
        box.add = Button(box, T("designer.resource.add", "+ 添加资源"), 136, function() self:OpenResourceAdd() end)
        Place(box.add, box, 0, 70)
    end
    local box = self.resourceLayoutItem
    local y = self.resourceHandControls and 564 or 416
    Place(box, parent, 0, y)
    local id = self.resourceStyleResourceId
    box.select:SetDisabled(id == nil)
    RefreshResourceSelector(box.select, id)
    local layout = YHUD:GetResourceGroupLayout(profile, group.id)
    box.heightLabel:SetText(layout.orientation == "vertical" and T("designer.resource.thickness_override", "覆盖粗细")
        or T("designer.resource.height_override", "覆盖高度"))
    local setting = id and YHUD:GetResourceSetting(profile, id, group.id)
    box.override:SetValue(setting and setting.heightOverride ~= nil, true)
    box.override:SetDisabled(not id)
    box.height:SetValue(setting and setting.heightOverride or YHUD:GetResourceGroupLayout(profile, group.id).height, true)
    box.height:SetDisabled(not setting or setting.heightOverride == nil)
    box.add:SetShown(id == nil)
    box.height:SetShown(id ~= nil)
    box.heightLabel:SetShown(id ~= nil)
    box.override:SetShown(id ~= nil)
    I.SetResourceContentHeight(self, y + 172)
end

local HideWorkspace = UI.HideWorkspace
function UI:HideWorkspace(...)
    self:ClearResourceOperation(true)
    self:CloseResourceDialog()
    CloseResourceMenu(self)
    return HideWorkspace(self, ...)
end

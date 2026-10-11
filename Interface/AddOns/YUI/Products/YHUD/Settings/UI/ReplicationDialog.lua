local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local GUI2 = YUI.GUI2
local Designer = YHUD.Designer
local DesignerUI = YHUD.DesignerUI
if not (GUI2 and GUI2.Form and Designer and DesignerUI) then return end
local Icons = YUI.API and YUI.API.Icons
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API

local DIALOG_MIN_WIDTH = 520
local DIALOG_MAX_WIDTH = 580
local DIALOG_HORIZONTAL_PADDING = 28
local DIALOG_SCROLLBAR_ALLOWANCE = 16
local TARGET_GRID_COLUMNS = 3
local TARGET_GRID_GAP = 8
local TARGET_GRID_INSET = 4
local TARGET_ROW_HEIGHT = 30
local TARGET_ICON_SIZE = 20
local SOURCE_ICON_FALLBACK = 134400

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

local function Colorize(text, r, g, b, a)
    return "|c" .. ColorHex(r, g, b, a)
        .. tostring(text or "") .. "|r"
end

local function ClassColor(classFile)
    local color = classFile and UnitAPI and UnitAPI.GetClassColor
        and UnitAPI.GetClassColor(classFile) or nil
    return color and color.r or 1,
        color and color.g or 1,
        color and color.b or 1,
        1
end

local function ApplySpecializationIcon(control, spec)
    local icon = control and control.specIcon
    if not icon then return false end
    local fallback = spec and spec.icon or SOURCE_ICON_FALLBACK
    local applied = Icons and Icons.GetScopedSpecIcon and Icons.ApplyIcon
        and Icons.ApplyIcon(
            icon,
            Icons.GetScopedSpecIcon(
                spec and spec.specID,
                fallback,
                "settings"
            )
        )
    if not applied and icon.SetTexture then
        icon:SetTexture(fallback)
        if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    return applied == true
end

local function EntrySourcePresentation(entry)
    if entry.origin == "official-cdm" then
        return T("designer.monitor.source.native", "原生"), 0, 0.62, 1, 1
    end
    if entry.origin == "preset" or entry.presetKey ~= nil then
        return T("designer.monitor.source.preset", "预设"), 1, 0.50, 0, 1
    end
    local r, g, b, a = GUI2:GetColor(
        "color.text.muted",
        { 0.55, 0.58, 0.62, 1 }
    )
    return T("designer.monitor.source.custom", "自定义"), r, g, b, a
end

local function EntryIdentityValue(entry)
    return tonumber(entry.itemId or entry.itemID)
        or tonumber(entry.spellId or entry.spellID or entry.runtimeSpellId)
        or tonumber(entry.cooldownId or entry.cooldownID)
        or tonumber(entry.slotId or entry.slotID)
end

local function ApplyDialogWidth(dialog, width)
    width = math.max(
        DIALOG_MIN_WIDTH,
        math.min(DIALOG_MAX_WIDTH, math.floor(width + 0.5))
    )
    local contentWidth = width - (DIALOG_HORIZONTAL_PADDING * 2)
    dialog:SetWidth(width)
    dialog.tabs:SetWidth(width - 50)
    dialog.summaryPanel:SetWidth(contentWidth)
    dialog.scroll:SetWidth(contentWidth)
    local childWidth = contentWidth - DIALOG_SCROLLBAR_ALLOWANCE
    dialog.scroll.child:SetWidth(childWidth)
    for index = 1, #dialog.headerPool do
        dialog.headerPool[index]:SetWidth(contentWidth - 44)
    end
    local cellWidth = math.floor((childWidth
        - (TARGET_GRID_INSET * 2)
        - (TARGET_GRID_GAP * (TARGET_GRID_COLUMNS - 1)))
        / TARGET_GRID_COLUMNS)
    for index = 1, #dialog.checkboxPool do
        local checkbox = dialog.checkboxPool[index]
        checkbox:SetWidth(cellWidth)
        if checkbox.text then
            checkbox.text:SetWidth(math.max(cellWidth - 52, 1))
        end
        if checkbox.gridColumn ~= nil and checkbox.gridY ~= nil then
            checkbox:ClearAllPoints()
            checkbox:SetPoint(
                "TOPLEFT",
                TARGET_GRID_INSET
                    + checkbox.gridColumn * (cellWidth + TARGET_GRID_GAP),
                -checkbox.gridY
            )
        end
    end
    dialog.contentWidth = contentWidth
    dialog.targetCellWidth = cellWidth
    return width
end

local function FindSemanticMonitor(profile, identity)
    for monitorId, monitor in pairs(profile and profile.monitors or {}) do
        if YHUD:GetMonitorSemanticIdentity(profile, monitor) == identity then
            return monitorId, monitor,
                profile.entries and profile.entries[monitor.entryKey] or nil
        end
    end
    return nil
end

local function SelectedCount(values)
    local count = 0
    for _, selected in pairs(values or {}) do
        if selected == true then count = count + 1 end
    end
    return count
end

local function EnsureDialog(self)
    if self.replicationDialog then return self.replicationDialog end

    local blocker = GUI2:CreateFrame(UIParent, {
        name = "YUI_YHUD_ReplicationDialogBlocker",
    })
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:SetFrameLevel(760)
    blocker:EnableMouse(true)
    local shade = blocker:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(blocker)
    shade:SetColorTexture(0, 0, 0, 0.72)
    blocker:Hide()

    local dialog = GUI2:CreatePanel(UIParent, {
        name = "YUI_YHUD_ReplicationDialog",
        width = DIALOG_MIN_WIDTH,
        height = 620,
        surface = "color.surface.panel",
        border = true,
    })
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 34)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(770)
    dialog:EnableMouse(true)
    dialog:Hide()
    dialog.mode = "copy"
    dialog.selectedByMode = { copy = {}, sync = {} }
    dialog.scopes = { display = true, sound = false }
    dialog.rows = {}
    dialog.headerPool = {}
    dialog.checkboxPool = {}
    dialog.resultStatus = nil

    local title = GUI2:CreateText(
        dialog,
        T("designer.replication.title", "复制 / 同步"),
        "font.size.xl",
        "color.text.accent",
        "CENTER"
    )
    title:SetPoint("TOPLEFT", 24, -18)
    title:SetPoint("TOPRIGHT", -24, -18)

    local close = GUI2.Form:CreateButton(dialog, {
        text = "×",
        width = 30,
        height = 28,
        tone = "danger",
        onClick = function() DesignerUI:HideReplicationDialog() end,
    })
    close:SetPoint("TOPRIGHT", -14, -12)

    local tabs = GUI2.Form:CreateUnderlineTabs(dialog, {
        width = DIALOG_MIN_WIDTH - 50,
        height = 34,
        minItemWidth = 220,
        showBaseline = true,
        value = "copy",
        items = {
            {
                value = "copy",
                text = T(
                    "designer.replication.tab_copy",
                    "复制完整监控"
                ),
            },
            {
                value = "sync",
                text = T(
                    "designer.replication.tab_sync",
                    "仅同步设置"
                ),
            },
        },
        set = function(value)
            dialog.mode = value == "sync" and "sync" or "copy"
            dialog.resultStatus = nil
            DesignerUI:RefreshReplicationDialog()
        end,
    })
    tabs:SetPoint("TOPLEFT", 24, -54)
    dialog.tabs = tabs

    local summaryPanel = GUI2:CreatePanel(dialog, {
        width = DIALOG_MIN_WIDTH - (DIALOG_HORIZONTAL_PADDING * 2),
        height = 72,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    summaryPanel:SetPoint("TOPLEFT", DIALOG_HORIZONTAL_PADDING, -98)
    dialog.summaryPanel = summaryPanel
    local summaryIcon = summaryPanel:CreateTexture(nil, "ARTWORK")
    summaryIcon:SetPoint("TOPLEFT", 12, -12)
    summaryIcon:SetSize(48, 48)
    summaryIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    dialog.summaryIcon = summaryIcon
    local summary = GUI2:CreateText(
        summaryPanel, "", "font.size.md", "color.text.primary", "LEFT"
    )
    summary:SetPoint("TOPLEFT", 72, -10)
    summary:SetPoint("TOPRIGHT", -12, -10)
    summary:SetHeight(20)
    dialog.summary = summary
    local summaryMeta = GUI2:CreateText(
        summaryPanel, "", "font.size.sm", "color.text.secondary", "LEFT"
    )
    summaryMeta:SetPoint("TOPLEFT", 72, -32)
    summaryMeta:SetPoint("TOPRIGHT", -12, -32)
    summaryMeta:SetHeight(18)
    dialog.summaryMeta = summaryMeta
    local summaryId = GUI2:CreateText(
        summaryPanel, "", "font.size.sm", "color.text.secondary", "LEFT"
    )
    summaryId:SetPoint("TOPLEFT", 72, -50)
    summaryId:SetPoint("TOPRIGHT", -12, -50)
    summaryId:SetHeight(18)
    dialog.summaryId = summaryId

    local scopeDisplay = GUI2.Form:CreateCheckbox(dialog, {
        text = T("designer.replication.scope_display", "显示设置"),
        width = 150,
        height = 26,
        checked = true,
        onClick = function(_, checked)
            dialog.scopes.display = checked == true
            dialog.resultStatus = nil
            DesignerUI:RefreshReplicationDialog()
        end,
    })
    scopeDisplay:SetPoint("TOPLEFT", 28, -178)
    dialog.scopeDisplay = scopeDisplay
    local scopeSound = GUI2.Form:CreateCheckbox(dialog, {
        text = T("designer.replication.scope_sound", "声音设置"),
        width = 150,
        height = 26,
        checked = true,
        onClick = function(_, checked)
            dialog.scopes.sound = checked == true
            dialog.resultStatus = nil
            DesignerUI:RefreshReplicationDialog()
        end,
    })
    scopeSound:SetPoint("LEFT", scopeDisplay, "RIGHT", 16, 0)
    dialog.scopeSound = scopeSound

    local quickLabel = GUI2:CreateText(
        dialog,
        T("designer.replication.targets", "选择目标专精"),
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    quickLabel:SetPoint("TOPLEFT", 28, -216)

    local clear = GUI2.Form:CreateButton(dialog, {
        text = T("designer.replication.clear", "清空"),
        width = 82,
        height = 26,
        tone = "default",
        onClick = function()
            dialog.selectedByMode[dialog.mode] = {}
            dialog.resultStatus = nil
            DesignerUI:RefreshReplicationDialog()
        end,
    })
    clear:SetPoint("TOPRIGHT", -28, -210)
    local all = GUI2.Form:CreateButton(dialog, {
        text = T("designer.replication.all", "全部"),
        width = 82,
        height = 26,
        tone = "default",
        onClick = function()
            local selected = dialog.selectedByMode[dialog.mode]
            for index = 1, #dialog.rows do
                local row = dialog.rows[index]
                if row.specKey and row.selectable then
                    selected[row.specKey] = true
                end
            end
            dialog.resultStatus = nil
            DesignerUI:RefreshReplicationDialog()
        end,
    })
    all:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    local currentClass = GUI2.Form:CreateButton(dialog, {
        text = T("designer.replication.current_class", "当前职业"),
        width = 108,
        height = 26,
        tone = "default",
        onClick = function()
            local session = Designer:GetSession()
            local classFile = session and session.runtimeSpecKey
                and session.runtimeSpecKey:match("^([^:]+):") or nil
            local selected = dialog.selectedByMode[dialog.mode]
            for index = 1, #dialog.rows do
                local row = dialog.rows[index]
                if row.specKey and row.selectable
                    and row.classFile == classFile then
                    selected[row.specKey] = true
                end
            end
            dialog.resultStatus = nil
            DesignerUI:RefreshReplicationDialog()
        end,
    })
    currentClass:SetPoint("RIGHT", all, "LEFT", -8, 0)

    local scroll = GUI2:CreateScrollFrame(dialog, {
        template = "UIPanelScrollFrameTemplate",
        width = DIALOG_MIN_WIDTH - (DIALOG_HORIZONTAL_PADDING * 2),
        height = 260,
        childWidth = DIALOG_MIN_WIDTH
            - (DIALOG_HORIZONTAL_PADDING * 2)
            - DIALOG_SCROLLBAR_ALLOWANCE,
        childHeight = 260,
    })
    scroll:SetPoint("TOPLEFT", 28, -246)
    dialog.scroll = scroll

    local status = GUI2:CreateText(
        dialog, "", "font.size.sm", "color.text.secondary", "LEFT"
    )
    status:SetPoint("BOTTOMLEFT", 28, 66)
    status:SetPoint("BOTTOMRIGHT", -28, 66)
    status:SetHeight(30)
    status:SetWordWrap(true)
    dialog.status = status

    local cancel = GUI2.Form:CreateButton(dialog, {
        text = T("designer.replication.cancel", "取消"),
        width = 132,
        height = 32,
        tone = "default",
        onClick = function() DesignerUI:HideReplicationDialog() end,
    })
    cancel:SetPoint("BOTTOMRIGHT", -184, 22)
    local apply = GUI2.Form:CreateButton(dialog, {
        text = T("designer.replication.apply_copy", "复制到所选专精"),
        width = 156,
        height = 32,
        tone = "accent",
        onClick = function() DesignerUI:ApplyReplicationDialog() end,
    })
    apply:SetPoint("BOTTOMRIGHT", -20, 22)
    dialog.apply = apply

    self.replicationDialogBlocker = blocker
    self.replicationDialog = dialog
    return dialog
end

local function ResolveTargetState(dialog, session, specKey)
    if specKey == session.viewSpecKey then return false, "source" end
    local profile = session.draft.profile
    local sourceMonitor = profile.monitors[session.selectedMonitorId]
    local sourceEntry = sourceMonitor and profile.entries[sourceMonitor.entryKey]
    if not sourceEntry then return false, "missing" end
    if sourceEntry.sourceType == "yhud.ammo-count"
        and not YHUD:CanMaterializePresetForSpec(sourceEntry, specKey) then
        return false, "not-applicable"
    end
    local identity = YHUD:GetEntrySemanticIdentity(
        sourceEntry,
        sourceMonitor.entryKey
    )
    if dialog.mode == "copy" then
        local allowed, code = YHUD:CanMaterializePresetForSpec(
            sourceEntry,
            specKey
        )
        if not allowed then
            return false, code == "preset-not-applicable"
                and "not-applicable" or "policy-denied"
        end
        local scoped = YHUD:GetScopedProfile(session.draft.root, specKey, false)
        if scoped and FindSemanticMonitor(scoped, identity) then
            return true, "already-exists"
        end
        return true, "missing"
    end

    local scoped = YHUD:GetScopedProfile(session.draft.root, specKey, false)
    local monitorId, monitor, entry
    if scoped then
        monitorId, monitor, entry = FindSemanticMonitor(scoped, identity)
    end
    if not monitor then return false, "missing" end
    if entry and entry.origin == "official-cdm" then
        return false, "native-read-only"
    end
    return true, "available"
end

local STATUS_TEXT = {
    source = { "designer.replication.status_source", "来源" },
    ["already-exists"] = {
        "designer.replication.status_exists", "已有"
    },
    available = {
        "designer.replication.status_available", "可同步"
    },
    ["not-applicable"] = {
        "designer.replication.status_not_applicable", "不适用"
    },
    ["policy-denied"] = {
        "designer.replication.status_unavailable", "暂不可用"
    },
    missing = { "designer.replication.status_missing", "未添加" },
    ["native-read-only"] = {
        "designer.replication.status_native", "原生只读"
    },
}

function DesignerUI:RefreshReplicationDialog()
    local dialog = self.replicationDialog
    if not (dialog and dialog:IsShown()) then return end
    local session = Designer:GetSession()
    local profile = session and session.draft.profile
    local monitor = profile and profile.monitors[session.selectedMonitorId]
    local entry = monitor and profile.entries[monitor.entryKey]
    if not (session and monitor and entry) then
        return self:HideReplicationDialog()
    end

    local summaryName = entry.nameKey
        and T(entry.nameKey, entry.name or monitor.entryKey)
        or entry.name or monitor.entryKey
    dialog.summary:SetText(summaryName)
    local summaryIcon = entry.icon or SOURCE_ICON_FALLBACK
    if (YHUD.Ammo and entry.sourceType == YHUD.Ammo.SOURCE_TYPE)
        or entry.sourceType == "racial-bundle" or entry.bundleKind == "racial" then
        summaryIcon = DesignerUI._internal.EntryIcon(entry)
    end
    dialog.summaryIcon:SetTexture(summaryIcon)
    local kindText = entry.semantic == "buff"
        and T("designer.monitor.type_buff_short", "光环")
        or T("designer.monitor.type_cooldown_short", "冷却")
    local kindR, kindG, kindB, kindA = GUI2:GetColor(
        "color.state.success",
        { 0.12, 0.72, 0.34, 1 }
    )
    local sourceText, sourceR, sourceG, sourceB, sourceA =
        EntrySourcePresentation(entry)
    dialog.summaryMeta:SetText(
        Colorize(kindText, kindR, kindG, kindB, kindA)
            .. "  "
            .. Colorize(sourceText, sourceR, sourceG, sourceB, sourceA)
    )
    local idLabel = T("designer.monitor.id", "ID") .. ":"
    local idValue = EntryIdentityValue(entry) or "-"
    local idR, idG, idB, idA = GUI2:GetColor(
        "color.state.danger",
        { 0.90, 0.18, 0.22, 1 }
    )
    local valueR, valueG, valueB, valueA = GUI2:GetColor(
        "color.text.accent",
        { 1, 0.82, 0, 1 }
    )
    dialog.summaryId:SetText(
        Colorize(idLabel, idR, idG, idB, idA)
            .. " "
            .. Colorize(idValue, valueR, valueG, valueB, valueA)
    )
    local syncMode = dialog.mode == "sync"
    dialog.scopeDisplay:SetShown(syncMode)
    dialog.scopeSound:Hide()
    dialog.apply:SetText(syncMode
        and T("designer.replication.apply_sync", "同步到所选专精")
        or T("designer.replication.apply_copy", "复制到所选专精"))

    for index = 1, #dialog.headerPool do
        dialog.headerPool[index]:Hide()
    end
    for index = 1, #dialog.checkboxPool do
        dialog.checkboxPool[index]:Hide()
    end
    dialog.rows = {}
    local sections = Designer:GetSpecializationSections() or {}
    local sectionNames = {
        ["current-class"] = T(
            "designer.replication.section_current_class",
            "本职业专精"
        ),
        enabled = T(
            "designer.replication.section_enabled",
            "配置启用专精"
        ),
        disabled = T(
            "designer.replication.section_disabled",
            "配置未启用专精"
        ),
    }
    local selected = dialog.selectedByMode[dialog.mode]
    local y = 0
    local headerIndex = 0
    local checkboxIndex = 0
    local maxRowTextWidth = 0
    for sectionIndex = 1, #sections do
        local section = sections[sectionIndex]
        if #section.rows > 0 then
            headerIndex = headerIndex + 1
            local header = dialog.headerPool[headerIndex]
            if not header then
                header = GUI2:CreateText(
                    dialog.scroll.child, "", "font.size.sm",
                    "color.text.accent", "LEFT"
                )
                dialog.headerPool[headerIndex] = header
            end
            header:SetText(sectionNames[section.id] or section.id)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 4, -y)
            header:SetWidth((dialog.contentWidth or 544) - 44)
            header:SetHeight(24)
            header:Show()
            y = y + 26
            local sectionStartY = y
            for rowIndex = 1, #section.rows do
                local spec = section.rows[rowIndex]
                local selectable, state = ResolveTargetState(
                    dialog,
                    session,
                    spec.specKey
                )
                if not selectable then selected[spec.specKey] = nil end
                local statusInfo = STATUS_TEXT[state]
                local statusText = statusInfo
                    and T(statusInfo[1], statusInfo[2]) or nil
                local classR, classG, classB, classA = ClassColor(
                    spec.classFile
                )
                local label = Colorize(
                    spec.text,
                    classR,
                    classG,
                    classB,
                    classA
                )
                local fullLabel = spec.text
                if statusInfo then
                    label = label .. "  " .. statusText
                    fullLabel = fullLabel .. "  " .. statusText
                end
                checkboxIndex = checkboxIndex + 1
                local checkbox = dialog.checkboxPool[checkboxIndex]
                if not checkbox then
                    checkbox = GUI2.Form:CreateCheckbox(
                        dialog.scroll.child,
                        {
                            text = "",
                            width = dialog.targetCellWidth or 150,
                            height = 28,
                            onClick = function(control, checked)
                                local values = dialog.selectedByMode[
                                    dialog.mode
                                ]
                                values[control.specKey] = checked == true
                                    or nil
                                dialog.resultStatus = nil
                            DesignerUI:RefreshReplicationDialog()
                        end,
                        }
                    )
                    checkbox.specIcon = GUI2:CreateIcon(checkbox, {
                        icon = SOURCE_ICON_FALLBACK,
                        size = TARGET_ICON_SIZE,
                        crop = true,
                    })
                    checkbox.specIcon:SetPoint(
                        "LEFT",
                        checkbox.box,
                        "RIGHT",
                        5,
                        0
                    )
                    checkbox.text:ClearAllPoints()
                    checkbox.text:SetPoint(
                        "LEFT",
                        checkbox.specIcon,
                        "RIGHT",
                        5,
                        0
                    )
                    checkbox.text:SetWidth(math.max(
                        (dialog.targetCellWidth or 150) - 52,
                        1
                    ))
                    checkbox:HookScript("OnEnter", function(control)
                        local text = control.text
                        local available = control.GetWidth
                            and control:GetWidth() - 52 or 0
                        local actual = text and text.GetStringWidth
                            and text:GetStringWidth() or 0
                        if control.fullLabel and actual > available
                            and GameTooltip then
                            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
                            GameTooltip:SetText(control.fullLabel, 1, 1, 1, true)
                            GameTooltip:Show()
                        end
                    end)
                    checkbox:HookScript("OnLeave", function(control)
                        if GameTooltip and GameTooltip:GetOwner() == control then
                            GameTooltip:Hide()
                        end
                    end)
                    dialog.checkboxPool[checkboxIndex] = checkbox
                end
                checkbox.text:SetText(label)
                checkbox.fullLabel = fullLabel
                checkbox.specPlainLabel = spec.text
                if checkbox.text and checkbox.text.GetStringWidth then
                    maxRowTextWidth = math.max(
                        maxRowTextWidth,
                        checkbox.text:GetStringWidth() or 0
                    )
                end
                checkbox:SetChecked(selected[spec.specKey] == true, true)
                checkbox:SetDisabled(not selectable, true)
                checkbox.gridColumn = (rowIndex - 1) % TARGET_GRID_COLUMNS
                checkbox.gridY = sectionStartY
                    + math.floor((rowIndex - 1) / TARGET_GRID_COLUMNS)
                        * TARGET_ROW_HEIGHT
                checkbox.specKey = spec.specKey
                checkbox.classFile = spec.classFile
                checkbox.selectable = selectable
                ApplySpecializationIcon(checkbox, spec)
                checkbox:Show()
                dialog.rows[#dialog.rows + 1] = checkbox
            end
            y = sectionStartY
                + math.ceil(#section.rows / TARGET_GRID_COLUMNS)
                    * TARGET_ROW_HEIGHT
            y = y + 8
        end
    end
    local desiredWidth = (maxRowTextWidth + 68) * TARGET_GRID_COLUMNS
        + (TARGET_GRID_GAP * (TARGET_GRID_COLUMNS - 1))
        + (TARGET_GRID_INSET * 2)
        + (DIALOG_HORIZONTAL_PADDING * 2)
        + DIALOG_SCROLLBAR_ALLOWANCE
    ApplyDialogWidth(dialog, desiredWidth)
    dialog.scroll.child:SetHeight(math.max(260, y))
    local count = SelectedCount(selected)
    local scopeReady = not syncMode
        or dialog.scopes.display == true
    dialog.apply:SetDisabled(count == 0 or not scopeReady)
    if dialog.resultStatus then
        dialog.status:SetText(dialog.resultStatus)
    elseif syncMode and not scopeReady then
        dialog.status:SetText(T(
            "designer.replication.select_scope",
            "请至少选择一个同步范围。"
        ))
    elseif not syncMode then
        dialog.status:SetText(T(
            "designer.replication.copy_hint",
            "选择已有监控时，将保留目标 ID 并覆盖完整设置和分组位置。"
        ))
    elseif count == 0 then
        dialog.status:SetText(T(
            "designer.replication.select_target",
            "请选择至少一个目标专精。"
        ))
    else
        dialog.status:SetText("")
    end
end

function DesignerUI:ShowReplicationDialog()
    local session = Designer:GetSession()
    local profile = session and session.draft.profile
    local monitor = profile and profile.monitors[session.selectedMonitorId]
    local entry = monitor and profile.entries[monitor.entryKey]
    if not entry then return nil, "monitor-not-selected" end
    local allowed, code = YHUD:CanCrossSpecOperate(
        "copy",
        entry,
        session.runtimeSpecKey,
        session.viewSpecKey
    )
    if not allowed then return nil, code end
    local dialog = EnsureDialog(self)
    dialog.mode = "copy"
    dialog.tabs:SetValue("copy", true)
    dialog.selectedByMode = { copy = {}, sync = {} }
    dialog.scopes = { display = true, sound = false }
    dialog.resultStatus = nil
    dialog.scopeDisplay:SetChecked(true, true)
    dialog.scopeSound:SetChecked(false, true)
    dialog.status:SetText("")
    self.replicationDialogBlocker:Show()
    dialog:Show()
    self:RefreshReplicationDialog()
    return true
end

function DesignerUI:HideReplicationDialog()
    if self.replicationDialog then self.replicationDialog:Hide() end
    if self.replicationDialogBlocker then
        self.replicationDialogBlocker:Hide()
    end
end

function DesignerUI:ApplyReplicationDialog()
    local dialog = self.replicationDialog
    if not (dialog and dialog:IsShown()) then return nil end
    local selected = dialog.selectedByMode[dialog.mode]
    local targets = {}
    for specKey, enabled in pairs(selected) do
        if enabled == true then targets[#targets + 1] = specKey end
    end
    table.sort(targets)
    local report, code
    if dialog.mode == "sync" then
        report, code = Designer:SyncSelectedMonitorToSpecializations(
            targets,
            dialog.scopes
        )
    else
        report, code = Designer:CopySelectedMonitorToSpecializations(targets)
    end
    if not report then
        dialog.status:SetText(T(
            "designer.replication.failed",
            "操作失败，未写入本批改动。"
        ) .. " (" .. tostring(code or "unknown") .. ")")
        return nil, code
    end
    dialog.selectedByMode[dialog.mode] = {}
    if dialog.mode == "copy" then
        dialog.resultStatus = string.format(
            T(
                "designer.replication.completed_copy",
                "已新增 %d 个专精，覆盖 %d 个，跳过 %d 个。"
            ),
            report.copied or 0,
            report.overwritten or 0,
            report.skipped or 0
        )
    else
        dialog.resultStatus = string.format(
            T(
                "designer.replication.completed",
                "已完成 %d 个专精，跳过 %d 个。"
            ),
            report.synced or 0,
            report.skipped or 0
        )
    end
    dialog.status:SetText(dialog.resultStatus)
    self:ApplyPreview()
    self:Refresh(false, false)
    self:RefreshReplicationDialog()
    return report
end

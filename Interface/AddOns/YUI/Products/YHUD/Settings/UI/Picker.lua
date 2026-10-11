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
local Assets = YUI.Assets
local STATE_CORNER_TEXTURE = Assets and Assets.Product
    and Assets:Product("yhud", "gui\\monitor-state-corner-top-left.png")
    or ("Interface\\AddOns\\" .. (YUI.AddonName or "YUI")
        .. "\\Products\\YHUD\\Media\\gui"
        .. "\\monitor-state-corner-top-left.png")

local function ApplySolidPickerButton(button, surfaceToken, borderToken)
    if not button then return end
    button.yhudSolidSurfaceToken = surfaceToken
    button.yhudSolidBorderToken = borderToken
    local function Paint(frame, hovered, pressed)
        local surface = frame.yhudSolidSurfaceToken or surfaceToken
        local border = frame.yhudSolidBorderToken or borderToken
        if frame.SetBackdropColor then
            frame:SetBackdropColor(GUI2:GetColor(surface))
        end
        GUI2:SetBorderColor(
            frame,
            pressed and "color.border.strong"
                or (hovered and "color.text.primary" or border)
        )
        if frame.SetTextColor then
            frame:SetTextColor(GUI2:GetColor("color.badge.text"))
        end
    end
    if button.yhudSolidPickerReady then
        Paint(button, button:IsMouseOver() and not button.gui2Disabled, false)
        return
    end
    button.yhudSolidPickerReady = true
    GUI2.Form:SetButtonRelief(button, "hairline")
    local baseRefreshTheme = button.RefreshTheme
    button.RefreshTheme = function(frame)
        if baseRefreshTheme then baseRefreshTheme(frame) end
        Paint(frame, frame:IsMouseOver() and not frame.gui2Disabled, false)
    end
    button:HookScript("OnEnter", function(frame)
        if not frame.gui2Disabled then Paint(frame, true, false) end
    end)
    button:HookScript("OnLeave", function(frame)
        Paint(frame, false, false)
    end)
    button:HookScript("OnMouseDown", function(frame)
        if not frame.gui2Disabled then Paint(frame, true, true) end
    end)
    button:HookScript("OnMouseUp", function(frame)
        Paint(frame, frame:IsMouseOver() and not frame.gui2Disabled, false)
    end)
    Paint(button, false, false)
end

local function SetPickerButtonTone(button, tone)
    if not button then return end
    button.gui2SurfaceToken = nil
    button.gui2HoverSurfaceToken = nil
    button.gui2PressedSurfaceToken = nil
    button.gui2BorderToken = nil
    button.gui2HoverBorderToken = nil
    button.gui2PressedBorderToken = nil
    button.gui2TextColorKey = nil
    button.gui2HoverTextColorKey = nil
    button.gui2PressedTextColorKey = nil
    button.gui2Tone = tone or "default"
    if button.SetState then button:SetState("normal") end
end

local function SetBlizzardPickerButtonStyle(button)
    if not button then return end
    button.gui2Tone = "accent"
    button.gui2SurfaceToken = "color.interaction.fill"
    button.gui2HoverSurfaceToken = "color.interaction.primaryHover"
    button.gui2PressedSurfaceToken = "color.interaction.primaryPressed"
    button.gui2BorderToken = "color.interaction.border"
    button.gui2HoverBorderToken = "color.interaction.primary"
    button.gui2PressedBorderToken = "color.interaction.border"
    button.gui2TextColorKey = "color.accent.text"
    button.gui2HoverTextColorKey = "color.accent.text"
    button.gui2PressedTextColorKey = "color.accent.text"
    GUI2.Form:SetButtonRelief(button, "hairline")
    if button.SetState then button:SetState("normal") end
end

local function ResolveCustomMonitorPreview(kind, value)
    value = tonumber(value)
    if not value or value <= 0 or value % 1 ~= 0 then return nil, nil end
    if kind == "item" then
        local itemAPI = YUI.API and YUI.API.Item
        local info = itemAPI and itemAPI.GetInfo and itemAPI.GetInfo(value)
        local name = info and info.name
            or (itemAPI and itemAPI.GetNameByID
                and itemAPI.GetNameByID(value))
            or (itemAPI and itemAPI.GetName and itemAPI.GetName(value))
        local icon = info and info.texture
            or (itemAPI and itemAPI.GetIcon and itemAPI.GetIcon(value))
        return name, icon
    end
    local spellAPI = YUI.API and YUI.API.Spell
    local info = spellAPI and spellAPI.GetInfo and spellAPI.GetInfo(value)
    local name = info and info.name
        or (spellAPI and spellAPI.GetName and spellAPI.GetName(value))
    local icon = info and (info.iconID or info.originalIconID)
        or (spellAPI and spellAPI.GetTexture and spellAPI.GetTexture(value))
    return name, icon
end

local function ResolveMonitorPickerTooltipIdentity(option)
    if type(option) ~= "table" then return nil, nil end
    local tooltipSpellID = tonumber(
        option.tooltipSpellID or option.tooltipSpellId
    )
    if tooltipSpellID and tooltipSpellID > 0 then
        return "spell", tooltipSpellID
    end
    local itemID = tonumber(option.itemID or option.itemId)
    if itemID and itemID > 0 then return "item", itemID end
    local row = option.row
    local spellID = tonumber(
        option.spellID
        or option.spellId
        or (type(row) == "table" and (
            row.overrideSpellID or row.overrideSpellId
            or row.spellID or row.spellId
        ))
        or (type(option.spellIDs) == "table" and option.spellIDs[1])
    )
    if spellID and spellID > 0 then return "spell", spellID end
    return nil, nil
end

local function MonitorPickerOptionName(option)
    local name = type(option) == "table" and option.name or nil
    name = type(name) == "string" and name ~= "" and name or "-"
    if option and option.verificationStatus == "candidate" then
        return string.format(T(
            "designer.verification.candidate_name",
            "%s（待验证）"
        ), name)
    end
    return name
end

local PICKER_OVERLAY_HEIGHT = 164
local PICKER_CUSTOM_OVERLAY_HEIGHT = 204
local PICKER_COLUMNS = 8
local PICKER_CONTENT_WIDTH = 368
local PICKER_GRID_WIDTH = 366
local PICKER_TILE_WIDTH = 42
local PICKER_TILE_HEIGHT = 42
local PICKER_COLUMN_GAP = 4
local PICKER_ICON_SIZE = 42
local PICKER_ICON_SHAPE = "wideSquare"
local PICKER_SEARCH_WIDTH = 268
local PICKER_BATCH_SEARCH_WIDTH = 192

local function BlockMonitorPickerOverlayWheel() end

local function HideMonitorPickerOverlayTooltip()
    YUI.HideGameTooltip()
end

local function ConfigureMonitorPickerInputShield(panel)
    if not panel then return end
    if panel.EnableMouse then panel:EnableMouse(true) end
    if panel.EnableMouseWheel then panel:EnableMouseWheel(true) end
    if panel.SetScript then
        panel:SetScript("OnMouseWheel", BlockMonitorPickerOverlayWheel)
        panel:SetScript("OnEnter", HideMonitorPickerOverlayTooltip)
    end
end

local CUSTOM_MONITOR_PRESENTATION = {
    item = {
        titleKey = "designer.custom.title.item",
        title = "物品冷却",
        idKey = "designer.custom.id.item",
        id = "物品ID",
        descriptionKey = "designer.custom.description.item",
        description = "输入物品ID，监控物品数量与冷却。",
        labelKey = "designer.custom.label.item",
        label = "物品",
    },
    spell = {
        titleKey = "designer.custom.title.spell",
        title = "法术冷却",
        idKey = "designer.custom.id.spell",
        id = "冷却技能ID",
        descriptionKey = "designer.custom.description.spell",
        description = "输入技能ID，监控未被暴雪冷却收录的技能冷却。",
        labelKey = "designer.custom.label.spell",
        label = "法术",
    },
    ["self-aura"] = {
        titleKey = "designer.custom.title.self_aura",
        title = "自身增益",
        idKey = "designer.custom.id.self_aura",
        id = "自身增益ID",
        descriptionKey = "designer.custom.description.self_aura",
        description = "检测玩家身上的真实增益、剩余时间和层数。",
        labelKey = "designer.custom.label.self",
        label = "自身",
    },
    ["target-debuff"] = {
        titleKey = "designer.custom.title.target_debuff",
        title = "目标减益",
        idKey = "designer.custom.id.target_debuff",
        id = "目标减益ID",
        descriptionKey = "designer.custom.description.target_debuff",
        description = "检测当前目标身上由你或宠物施加的真实减益。",
        labelKey = "designer.custom.label.target",
        label = "目标",
    },
    ["cast-timer"] = {
        titleKey = "designer.custom.title.cast_timer",
        title = "施法计时",
        idKey = "designer.custom.id.cast_timer",
        id = "施法技能ID",
        descriptionKey = "designer.custom.description.cast_timer",
        description = "施法成功后启动固定倒计时，不检测真实增益。",
        labelKey = "designer.custom.label.cast",
        label = "施法",
    },
}

local function CustomMonitorPresentation(kind)
    return CUSTOM_MONITOR_PRESENTATION[kind]
        or CUSTOM_MONITOR_PRESENTATION.spell
end

local function CustomMonitorKinds(isBuff)
    return isBuff
        and { "self-aura", "target-debuff", "cast-timer" }
        or { "item", "spell" }
end

local PICKER_SECTION_ORDER = {
    "available",
    "preset",
    "native-hidden",
    "unlearned",
}

local function MonitorPickerSectionHeading(section)
    if section == "available" then
        return T("designer.picker.section.available", "暴雪已启用")
    end
    if section == "preset" then
        return T("designer.section.preset_buff", "预设监控")
    end
    if section == "native-hidden" then
        return T(
            "designer.picker.section.native_hidden",
            "需要先在暴雪冷却中添加"
        )
    end
    return T("designer.picker.section.unlearned", "未学习 / 未选择")
end

local function MonitorPickerDisplaySection(option)
    if type(option) ~= "table" then return "available" end
    if option.displaySection then return option.displaySection end
    local section = option.section
    if section == "quick" or section == "preset" or section == "tier-set" then
        return "preset"
    end
    return "available"
end

local function MonitorPickerState(option)
    if type(option) ~= "table" then return "unavailable" end
    return option.pickerState or option.status or "unavailable"
end

local function SetMonitorPickerStateCorner(tile, state)
    local colorKey = state == "current" and "color.state.success"
        or state == "move" and "color.interaction.primary"
        or nil
    local corner = tile and tile.stateCorner
    if not corner then return end
    if colorKey then
        corner.gui2ColorKey = colorKey
        if corner.SetVertexColor then
            corner:SetVertexColor(GUI2:GetColor(colorKey))
        end
        corner:Show()
    else
        corner:Hide()
    end
end

local function MonitorPickerPresetLabel(option)
    if type(option) ~= "table" then return nil end
    if option.presetId == "blood-boil-window" or option.presetKey == "blood-boil-window"
        or option.id == "preset:buff:blood-boil-window" then return nil end
    if type(option.presetLabelKey) == "string"
        and option.presetLabelKey ~= "" then
        return T(option.presetLabelKey)
    end
    if YUI.IsForever == true then
        if option.kind == "ammo" then
            return T("designer.picker.short.ammo", "弹药")
        end
        if option.kind == "slot" then
            local slotID = tonumber(option.slotID)
            if slotID == 13 then return T("designer.picker.short.trinket1", "饰品1") end
            if slotID == 14 then return T("designer.picker.short.trinket2", "饰品2") end
        end
    end
    local bundleKind = option.bundleKind
    if not bundleKind and option.kind == "racial-bundle" then
        bundleKind = "racial"
    end
    if bundleKind == "defensive" then
        return T("designer.bundle.short.defensive", "防御")
    end
    if bundleKind == "interruptControl" then
        return T("designer.bundle.short.interrupt_control", "断控")
    end
    if bundleKind == "racial" then
        return T("designer.bundle.short.racial", "种族")
    end
    if bundleKind == (YHUD.EQUIPMENT_AURA_BUNDLE_KIND
        or "equipmentAura") then
        return T("designer.bundle.short.trinket", "饰品")
    end
    if option.sourceIdentity == "bloodlust"
        or option.sourceIdentity == "bloodlust-heroism" then
        local faction = YHUD:GetPlayerFactionToken()
        if faction == "Horde" then
            return T("designer.bundle.short.bloodlust_horde", "嗜血")
        end
        return T("designer.bundle.short.bloodlust_alliance", "英勇")
    end
    return nil
end

local function NormalizePickerSearch(value)
    value = tostring(value or ""):lower()
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function MonitorPickerMatchesSearch(option, search)
    if search == "" then return true end
    local values = {
        option.name,
        option.cooldownID,
        option.spellID,
        option.spellId,
        option.itemID,
        option.itemId,
        option.entryKey,
    }
    local row = option.row
    if type(row) == "table" then
        values[#values + 1] = row.cooldownID
        values[#values + 1] = row.spellID
        values[#values + 1] = row.overrideSpellID
        values[#values + 1] = row.equipSlot
    end
    for index = 1, #values do
        if tostring(values[index] or ""):lower():find(search, 1, true) then
            return true
        end
    end
    return false
end

local function ResolveMonitorPickerBundleTooltip(option)
    local bundleKind = option and option.bundleKind
    if option and option.kind == "racial-bundle" then
        bundleKind = "racial"
    end
    if bundleKind == "racial" then
        return "designer.picker.bundle.racial_summary",
            "统一监控当前角色可用的种族主动技能冷却。",
            "designer.picker.bundle.racial_help",
            "内容会按当前种族匹配；添加后可选择具体技能并调整顺序。"
    end
    if bundleKind == "defensive" then
        return "designer.picker.bundle.defensive_summary",
            "统一监控当前职业与专精可用的减伤、免伤和保命技能。",
            "designer.picker.bundle.spec_help",
            "内容会按当前专精匹配；添加后可选择具体技能并调整顺序。"
    end
    if bundleKind == "interruptControl" then
        return "designer.picker.bundle.interrupt_control_summary",
            "统一监控当前职业与专精可用的打断和主要控制技能。",
            "designer.picker.bundle.spec_help",
            "内容会按当前专精匹配；添加后可选择具体技能并调整顺序。"
    end
end

local function ShowMonitorPickerTooltip(control, option)
    if not (control and GameTooltip and type(option) == "table") then
        return
    end
    GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    local summaryKey, summaryFallback, helpKey, helpFallback =
        ResolveMonitorPickerBundleTooltip(option)
    if summaryKey then
        local r, g, b = GUI2:GetColor("color.tooltip.id.value")
        GameTooltip:SetText(option.name or "-", r, g, b, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T(summaryKey, summaryFallback), 1, 1, 1, true)
        GameTooltip:AddLine(T(helpKey, helpFallback), 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if option.kind == "slot"
        and (tonumber(option.slotID) == 13
            or tonumber(option.slotID) == 14) then
        local displaySlot = tonumber(option.slotID) - 12
        local r, g, b = GUI2:GetColor("color.tooltip.id.value")
        GameTooltip:SetText(string.format(T(
            "designer.picker.slot_cooldown_title",
            "饰品冷却（栏位 %d）"
        ), displaySlot), r, g, b, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T(
            "designer.picker.slot_cooldown_help",
            "监控当前装备在该栏位的主动使用冷却，更换饰品后会自动更新。"
        ), 1, 1, 1, true)
        GameTooltip:AddLine(T(
            "designer.picker.slot_cooldown_buff_help",
            "饰品触发的 Buff 请使用【饰品触发】预设。"
        ), 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if option.kind == "equipment-aura-bundle" then
        local r, g, b = GUI2:GetColor("color.tooltip.id.value")
        GameTooltip:SetText(
            T("designer.quick_equipment_auras", "饰品触发"),
            r, g, b, 1, true
        )
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T(
            "designer.picker.equipment_auras_summary",
            "统一监控主动/被动饰品触发的Buff"
        ), 1, 1, 1, true)
        GameTooltip:AddLine(T(
            "designer.picker.equipment_auras_requirement",
            "请确保在【暴雪冷却（/cdm）】-【增益】中把所有饰品相关监控移动到【追踪的增益效果】"
        ), 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if type(option.tooltipItemIDs) == "table" then
        GameTooltip:SetText(option.name or "-", 1, 1, 1, 1, true)
        local item = YUI.API.Item
        for _, itemID in ipairs(option.tooltipItemIDs) do
            local name = item.GetName(itemID) or ("#" .. itemID)
            local icon = item.GetIcon(itemID) or 134400
            GameTooltip:AddLine("|T" .. icon .. ":20:20|t " .. name, 1, 1, 1, false)
        end
        if option.tooltipNoteKey then
            GameTooltip:AddLine(T(option.tooltipNoteKey), 1, 1, 1, true)
        end
        GameTooltip:Show()
        return
    end
    local kind, id = ResolveMonitorPickerTooltipIdentity(option)
    local shown
    if kind == "item" and GameTooltip.SetItemByID then
        shown = pcall(GameTooltip.SetItemByID, GameTooltip, id)
    elseif kind == "spell" and GameTooltip.SetSpellByID then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, id)
    end
    if not shown then
        GameTooltip:SetText(option.name or "-", 1, 1, 1, 1, true)
    end
    if type(option.tooltipNoteKey) == "string"
        and option.tooltipNoteKey ~= "" then
        local r, g, b = GUI2:GetColor("color.tooltip.id.value")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T(option.tooltipNoteKey), r, g, b, true)
    end
    if option.verificationStatus == "candidate" then
        local r, g, b = GUI2:GetColor("color.state.warning")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T(
            "designer.verification.candidate_tooltip",
            "套装效果候选，尚未经过实战验证。"
        ), r, g, b, true)
    end
    GameTooltip:Show()
end

function DesignerUI:RefreshMonitorPickerCustomPreview()
    local input = self.monitorPickerCustomID
    local icon = self.monitorPickerCustomPreviewIcon
    local label = self.monitorPickerCustomPreviewName
    if not (input and icon and label) then return false end
    local value = tonumber(input:GetText())
    local customKind = self.monitorPickerCustomKind or "spell"
    local kind = customKind == "item" and "item" or "spell"
    local name, texture = ResolveCustomMonitorPreview(kind, value)
    if icon.SetIcon then
        icon:SetIcon(texture or QUESTION_ICON)
    elseif GUI2.SetIconTexture then
        GUI2:SetIconTexture(icon, texture or QUESTION_ICON)
    elseif icon.SetTexture then
        icon:SetTexture(texture or QUESTION_ICON)
    end
    icon.yhudPreviewKind = kind
    icon.yhudPreviewId = value
    icon.yhudPreviewName = name
    icon.yhudPreviewValid = name ~= nil or texture ~= nil
    if name then
        label:SetText(name)
        if GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(label, "color.text.primary")
        end
    elseif value then
        label:SetText(T(
            "designer.custom_preview_unknown",
            "未找到对应图标或名称"
        ))
        if GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(label, "color.state.danger")
        end
    else
        label:SetText(T(
            "designer.custom_preview_empty",
            "输入 ID 后预览图标和名称"
        ))
        if GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(label, "color.text.secondary")
        end
    end
    local validID = value ~= nil and value > 0 and value % 1 == 0
    local validDuration = true
    if customKind == "cast-timer" then
        local duration = self.monitorPickerCustomDuration
            and tonumber(self.monitorPickerCustomDuration:GetText())
        validDuration = duration ~= nil
            and duration >= 0.1 and duration <= 3600
    end
    if self.monitorPickerCustomAdd
        and self.monitorPickerCustomAdd.SetDisabled then
        self.monitorPickerCustomAdd:SetDisabled(
            not validID or not validDuration
        )
    end
    return name ~= nil or texture ~= nil
end

function DesignerUI:AcquireMonitorPickerHeading(index)
    local headingRow = self.monitorPickerHeadings[index]
    if headingRow then return headingRow end
    local child = self.monitorPickerScroll
        and (self.monitorPickerScroll.child or self.monitorPickerScroll.scrollChild)
    if not child then return nil end
    headingRow = GUI2:CreateFrame(child, {
        width = PICKER_GRID_WIDTH,
        height = 28,
        mouse = false,
        hidden = true,
    })
    local heading = GUI2:CreateText(
        headingRow,
        "",
        "font.size.lg",
        "color.text.accent",
        "LEFT"
    )
    heading:SetPoint("LEFT", 2, 0)
    heading:SetPoint("RIGHT", -138, 0)
    heading:SetWordWrap(false)
    local nativeButton = GUI2.Form:CreateButton(headingRow, {
        text = T("designer.picker.open_blizzard", "前往暴雪冷却"),
        width = 128,
        height = 24,
        tone = "accent",
        relief = "hairline",
        onClick = function()
            DesignerUI:OpenBlizzardCooldownSettings()
        end,
    })
    nativeButton:SetPoint("RIGHT", -2, 0)
    SetBlizzardPickerButtonStyle(nativeButton)
    headingRow.heading = heading
    headingRow.nativeButton = nativeButton
    self.monitorPickerHeadings[index] = headingRow
    self.monitorPickerRows[#self.monitorPickerRows + 1] = headingRow
    return headingRow
end

function DesignerUI:AcquireMonitorPickerTile(index)
    local tile = self.monitorPickerTiles[index]
    if tile then return tile end
    local child = self.monitorPickerScroll
        and (self.monitorPickerScroll.child or self.monitorPickerScroll.scrollChild)
    if not child then return nil end
    tile = GUI2:CreateFrame(child, {
        width = PICKER_TILE_WIDTH,
        height = PICKER_TILE_HEIGHT,
        mouse = false,
        hidden = true,
    })
    local iconSlot = GUI2:CreateIconSlot(tile, {
        icon = QUESTION_ICON,
        size = PICKER_ICON_SIZE,
        crop = true,
        variant = "bare",
        shape = PICKER_ICON_SHAPE,
        border = "thin",
        selectedBorderColor = "color.state.warning",
        hoverBorderColor = "color.state.warning",
        onClick = function()
            DesignerUI:HandleMonitorPickerOption(tile.option)
        end,
    })
    iconSlot:SetPoint("TOP", tile, "TOP", 0, 0)
    local presetLabelBackdrop = GUI2:CreatePanel(iconSlot, {
        width = PICKER_ICON_SIZE - 2,
        height = 13,
        surface = "color.surface.popup",
        border = false,
    })
    presetLabelBackdrop:SetPoint("BOTTOM", iconSlot, "BOTTOM", 0, 1)
    if presetLabelBackdrop.EnableMouse then
        presetLabelBackdrop:EnableMouse(false)
    end
    local presetLabel = GUI2:CreateText(
        presetLabelBackdrop,
        "",
        "font.size.sm",
        "color.text.primary",
        "CENTER"
    )
    presetLabel:SetPoint("CENTER", presetLabelBackdrop, "CENTER", 0, 0)
    presetLabel:SetWidth(PICKER_ICON_SIZE - 4)
    presetLabel:SetWordWrap(false)
    presetLabelBackdrop:Hide()
    presetLabel:Hide()
    local stateCorner = GUI2:CreateIcon(iconSlot, {
        icon = STATE_CORNER_TEXTURE,
        size = 9,
        crop = false,
        layer = "OVERLAY",
        subLevel = 6,
    })
    stateCorner:SetPoint("TOPLEFT", iconSlot, "TOPLEFT", 1, -1)
    stateCorner.RefreshTheme = function(texture)
        if texture.gui2ColorKey and texture.SetVertexColor then
            texture:SetVertexColor(GUI2:GetColor(texture.gui2ColorKey))
        end
    end
    GUI2:RegisterThemeObject(stateCorner)
    stateCorner:Hide()
    iconSlot:HookScript("OnEnter", function(control)
        ShowMonitorPickerTooltip(control, tile.option)
    end)
    iconSlot:HookScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    tile.iconSlot = iconSlot
    tile.presetLabelBackdrop = presetLabelBackdrop
    tile.presetLabel = presetLabel
    tile.stateCorner = stateCorner
    self.monitorPickerTiles[index] = tile
    self.monitorPickerRows[#self.monitorPickerRows + 1] = tile
    return tile
end

function DesignerUI:EnsureMonitorPicker()
    if self.monitorPicker then return true end
    if not (self.panel and GUI2.CreateScrollFrame and GUI2.CreateIconSlot
        and GUI2.Form.CreateEditBox
        and GUI2.Form.CreateSegmentedControl) then
        return nil, "gui-unavailable"
    end

    local picker = GUI2:CreatePanel(self.panel, {
        name = "YUI_YHUD_MonitorPicker",
        width = self.panel.GetWidth and self.panel:GetWidth() or 400,
        height = self.panel.GetHeight and self.panel:GetHeight() or 680,
        surface = "color.surface.popup",
        border = "color.state.success",
    })
    picker:SetAllPoints(self.panel)
    if picker.SetFrameLevel and self.panel.GetFrameLevel then
        picker:SetFrameLevel(self.panel:GetFrameLevel() + 20)
    end
    picker:EnableMouse(true)
    picker:Hide()

    local header = GUI2:CreateFrame(picker, {
        width = PICKER_CONTENT_WIDTH,
        height = 38,
        mouse = false,
    })
    header:SetPoint("TOPLEFT", 16, -8)

    local title = GUI2:CreateText(
        header,
        T("designer.picker_title", "添加监控"),
        "font.size.lg",
        "color.text.heading",
        "LEFT"
    )
    title:SetPoint("LEFT", 0, 0)
    title:SetPoint("RIGHT", -40, 0)
    title:SetWordWrap(false)

    local closeButton = GUI2.Form:CreateButton(picker, {
        text = "×",
        width = 28,
        height = 28,
        tone = "danger",
        relief = "hairline",
        onClick = function()
            DesignerUI:HideMonitorPicker()
        end,
    })
    closeButton:SetPoint("TOPRIGHT", -12, -10)
    ApplySolidPickerButton(
        closeButton,
        "color.state.danger",
        "color.state.danger"
    )

    local search = GUI2.Form:CreateEditBox(picker, {
        width = PICKER_SEARCH_WIDTH,
        height = 30,
        autoFocus = false,
    })
    search:SetPoint("TOPLEFT", 16, -50)
    local searchPlaceholder = GUI2:CreateText(
        search,
        T("designer.picker.search", "搜索技能或 ID"),
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    searchPlaceholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    searchPlaceholder:SetPoint("RIGHT", search, "RIGHT", -8, 0)
    searchPlaceholder:SetWordWrap(false)
    local function RefreshSearchPlaceholder(edit)
        local focused = edit.HasFocus and edit:HasFocus()
        SetShown(searchPlaceholder, edit:GetText() == "" and not focused)
    end
    search:SetScript("OnTextChanged", function(edit)
        RefreshSearchPlaceholder(edit)
        if DesignerUI.monitorPickerRefreshing ~= true then
            DesignerUI:RefreshMonitorPicker(false, true)
        end
    end)
    search:HookScript("OnEditFocusGained", function(edit)
        RefreshSearchPlaceholder(edit)
    end)
    search:HookScript("OnEditFocusLost", function(edit)
        RefreshSearchPlaceholder(edit)
    end)
    search:SetScript("OnEscapePressed", function(edit)
        if edit.ClearFocus then edit:ClearFocus() end
        if DesignerUI.monitorPickerBatchMode == true then
            DesignerUI:CancelMonitorPickerBatch()
        else
            DesignerUI:HideMonitorPicker()
        end
    end)
    RefreshSearchPlaceholder(search)

    local batchButton = GUI2.Form:CreateButton(picker, {
        text = T("designer.picker.batch", "批量"),
        width = 92,
        height = 30,
        tone = "default",
        relief = "hairline",
        onClick = function()
            DesignerUI:ToggleMonitorPickerBatch()
        end,
    })
    batchButton:SetPoint("TOPRIGHT", -16, -50)

    local batchCancelButton = GUI2.Form:CreateButton(picker, {
        text = T("designer.cancel", "取消"),
        width = 68,
        height = 30,
        tone = "default",
        relief = "hairline",
        onClick = function()
            DesignerUI:CancelMonitorPickerBatch()
        end,
    })
    batchCancelButton:SetPoint("RIGHT", batchButton, "LEFT", -8, 0)
    batchCancelButton:Hide()

    local scroll = GUI2:CreateScrollFrame(picker, {
        width = PICKER_CONTENT_WIDTH,
        height = 574,
        childWidth = PICKER_GRID_WIDTH,
        childHeight = 574,
        mouseWheel = true,
    })
    scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -90)
    scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -16, 16)

    local customArea = GUI2:CreatePanel(picker, {
        width = PICKER_CONTENT_WIDTH,
        height = PICKER_CUSTOM_OVERLAY_HEIGHT,
        surface = "color.surface.popup",
        border = "color.border.default",
        hidden = true,
    })
    customArea:SetPoint("BOTTOM", picker, "BOTTOM", 0, 16)
    if customArea.SetFrameLevel then
        customArea:SetFrameLevel(picker:GetFrameLevel() + 10)
    end
    ConfigureMonitorPickerInputShield(customArea)

    local customHeading = GUI2:CreateText(
        customArea,
        T("designer.section.custom_id", "自定义监控"),
        "font.size.lg",
        "color.text.accent",
        "LEFT"
    )
    customHeading:SetPoint("TOPLEFT", 12, -10)
    customHeading:SetWidth(300)
    customHeading:SetWordWrap(false)

    local customClose = GUI2.Form:CreateButton(customArea, {
        text = "×",
        width = 32,
        height = 32,
        tone = "default",
        relief = "hairline",
        onClick = function()
            DesignerUI:ClearMonitorPickerOverlay()
        end,
    })
    customClose:SetPoint("TOPRIGHT", -10, -8)

    local customDescription = GUI2:CreateText(
        customArea,
        "",
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    customDescription:SetPoint("TOPLEFT", 12, -40)
    customDescription:SetPoint("RIGHT", customArea, "RIGHT", -12, 0)
    customDescription:SetHeight(30)
    customDescription:SetWordWrap(true)

    local customDurationLabel = GUI2:CreateText(
        customArea,
        T("designer.duration_seconds", "持续时间（秒）"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    customDurationLabel:SetPoint("TOPLEFT", 12, -126)
    customDurationLabel:SetWidth(100)
    customDurationLabel:SetWordWrap(false)
    customDurationLabel:Hide()

    local customDuration = GUI2.Form:CreateEditBox(customArea, {
        width = 96,
        height = 28,
        autoFocus = false,
    })
    customDuration:SetPoint("TOPLEFT", 120, -118)
    if customDuration.SetMaxLetters then customDuration:SetMaxLetters(8) end
    if customDuration.SetText then customDuration:SetText("20") end
    customDuration:SetScript("OnTextChanged", function()
        DesignerUI:RefreshMonitorPickerCustomPreview()
    end)
    customDuration:SetScript("OnEnterPressed", function()
        local input = DesignerUI.monitorPickerCustomID
        DesignerUI:AddCustomMonitorID(input and input:GetText())
    end)
    customDuration:SetScript("OnEscapePressed", function()
        DesignerUI:ClearMonitorPickerOverlay()
    end)
    customDuration:Hide()

    local customPreviewLabel = GUI2:CreateText(
        customArea,
        T("designer.custom_preview", "预览"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    customPreviewLabel:SetPoint("TOPLEFT", 12, -126)
    customPreviewLabel:SetWidth(58)
    local customPreview = GUI2:CreatePanel(customArea, {
        width = 236,
        height = 36,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    customPreview:SetPoint("TOPLEFT", 76, -118)
    local customPreviewIcon = GUI2:CreateIconSlot(customPreview, {
        icon = QUESTION_ICON,
        size = 28,
        crop = true,
        variant = "bare",
        shape = "square",
        border = "thin",
        onClick = function() end,
    })
    customPreviewIcon:SetPoint("LEFT", 4, 0)
    customPreviewIcon:HookScript("OnEnter", function(control)
        if not GameTooltip then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        local shown
        if control.yhudPreviewValid and control.yhudPreviewId then
            if control.yhudPreviewKind == "item"
                and GameTooltip.SetItemByID then
                shown = pcall(
                    GameTooltip.SetItemByID,
                    GameTooltip,
                    control.yhudPreviewId
                )
            elseif GameTooltip.SetSpellByID then
                shown = pcall(
                    GameTooltip.SetSpellByID,
                    GameTooltip,
                    control.yhudPreviewId
                )
            end
        end
        if not shown then
            GameTooltip:SetText(
                control.yhudPreviewName
                    or T(
                        "designer.custom_preview_unknown",
                        "未找到对应图标或名称"
                    ),
                1,
                1,
                1,
                1,
                true
            )
        end
        GameTooltip:Show()
    end)
    customPreviewIcon:HookScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    local customPreviewName = GUI2:CreateText(
        customPreview,
        T("designer.custom_preview_empty", "输入 ID 后预览图标和名称"),
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    customPreviewName:SetPoint("LEFT", customPreviewIcon, "RIGHT", 10, 0)
    customPreviewName:SetPoint("RIGHT", customPreview, "RIGHT", -8, 0)
    customPreviewName:SetWordWrap(false)

    local customIDLabel = GUI2:CreateText(
        customArea,
        T("designer.monitor.id", "ID"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    customIDLabel:SetPoint("TOPLEFT", 12, -86)
    customIDLabel:SetWidth(104)
    local customID = GUI2.Form:CreateEditBox(customArea, {
        width = 144,
        height = 30,
        autoFocus = false,
    })
    customID:SetPoint("TOPLEFT", 120, -78)
    if customID.SetNumeric then customID:SetNumeric(true) end
    if customID.SetMaxLetters then customID:SetMaxLetters(10) end
    customID:SetScript("OnTextChanged", function()
        DesignerUI:RefreshMonitorPickerCustomPreview()
    end)
    customID:SetScript("OnEnterPressed", function(edit)
        DesignerUI:AddCustomMonitorID(edit:GetText())
    end)
    customID:SetScript("OnEscapePressed", function()
        DesignerUI:ClearMonitorPickerOverlay()
    end)

    local customAdd = GUI2.Form:CreateButton(customArea, {
        text = T("designer.action.add", "添加"),
        width = 86,
        height = 30,
        tone = "warning",
        relief = "hairline",
        onClick = function()
            DesignerUI:AddCustomMonitorID(customID:GetText())
        end,
    })
    customAdd:SetPoint("TOPRIGHT", -12, -78)
    ApplySolidPickerButton(
        customAdd,
        "color.badge.green",
        "color.state.success"
    )

    local manageArea = GUI2:CreatePanel(picker, {
        width = PICKER_CONTENT_WIDTH,
        height = PICKER_OVERLAY_HEIGHT,
        surface = "color.surface.popup",
        border = "color.border.default",
        hidden = true,
    })
    manageArea:SetPoint("BOTTOM", picker, "BOTTOM", 0, 16)
    if manageArea.SetFrameLevel then
        manageArea:SetFrameLevel(picker:GetFrameLevel() + 10)
    end
    ConfigureMonitorPickerInputShield(manageArea)
    local manageIcon = GUI2:CreateIconSlot(manageArea, {
        icon = QUESTION_ICON,
        size = 48,
        crop = true,
        variant = "bare",
        shape = "square",
        border = "thin",
    })
    manageIcon:SetPoint("TOPLEFT", 14, -14)
    local manageName = GUI2:CreateText(
        manageArea, "", "font.size.lg", "color.text.accent", "LEFT"
    )
    manageName:SetPoint("TOPLEFT", 76, -14)
    manageName:SetPoint("RIGHT", -48, 0)
    manageName:SetWordWrap(false)
    local manageSource = GUI2:CreateText(
        manageArea, "", "font.size.md", "color.text.secondary", "LEFT"
    )
    manageSource:SetPoint("TOPLEFT", 76, -40)
    manageSource:SetPoint("RIGHT", -14, 0)
    manageSource:SetWordWrap(false)
    local manageGroup = GUI2:CreateText(
        manageArea, "", "font.size.md", "color.text.primary", "LEFT"
    )
    manageGroup:SetPoint("TOPLEFT", 14, -76)
    manageGroup:SetPoint("RIGHT", -14, 0)
    manageGroup:SetWordWrap(false)
    local manageMessage = GUI2:CreateText(
        manageArea, "", "font.size.md", "color.text.secondary", "LEFT"
    )
    manageMessage:SetPoint("BOTTOMLEFT", 14, 14)
    manageMessage:SetPoint("RIGHT", -158, 0)
    manageMessage:SetHeight(32)
    if manageMessage.SetJustifyV then manageMessage:SetJustifyV("MIDDLE") end
    manageMessage:SetWordWrap(true)
    local manageAction = GUI2.Form:CreateButton(manageArea, {
        text = "",
        width = 132,
        height = 32,
        tone = "default",
        relief = "hairline",
        onClick = function()
            DesignerUI:ExecuteMonitorPickerOverlayAction()
        end,
    })
    manageAction:SetPoint("BOTTOMRIGHT", -14, 14)
    local manageClose = GUI2.Form:CreateButton(manageArea, {
        text = "×",
        width = 26,
        height = 24,
        tone = "default",
        relief = "hairline",
        onClick = function()
            DesignerUI:ClearMonitorPickerOverlay()
        end,
    })
    manageClose:SetPoint("TOPRIGHT", -10, -8)

    local blocker = GUI2:CreatePanel(picker, {
        width = picker:GetWidth(),
        height = picker:GetHeight(),
        surface = "color.surface.popup",
        border = false,
        mouse = true,
        hidden = true,
    })
    blocker:SetAllPoints(picker)
    blocker:EnableMouse(true)
    if blocker.EnableMouseWheel then blocker:EnableMouseWheel(true) end
    blocker:SetScript("OnMouseWheel", function() end)
    if blocker.SetFrameLevel then
        blocker:SetFrameLevel(picker:GetFrameLevel() + 20)
    end
    local blockerText = GUI2:CreateText(
        blocker,
        T(
            "designer.picker.blizzard_blocked",
            "关闭暴雪冷却后，自动同步内容。"
        ),
        "font.size.lg",
        "color.text.heading",
        "CENTER"
    )
    blockerText:SetPoint("CENTER", 0, 0)
    blockerText:SetWidth(320)
    blockerText:SetWordWrap(true)

    self.monitorPicker = picker
    self.monitorPickerTitle = title
    self.monitorPickerSearch = search
    self.monitorPickerSearchPlaceholder = searchPlaceholder
    self.monitorPickerBatchButton = batchButton
    self.monitorPickerBatchCancelButton = batchCancelButton
    self.monitorPickerScroll = scroll
    self.monitorPickerRows = {}
    self.monitorPickerHeadings = {}
    self.monitorPickerTiles = {}
    self.monitorPickerCustomArea = customArea
    self.monitorPickerCustomHeading = customHeading
    self.monitorPickerCustomDescription = customDescription
    self.monitorPickerCustomID = customID
    self.monitorPickerCustomDurationLabel = customDurationLabel
    self.monitorPickerCustomDuration = customDuration
    self.monitorPickerCustomIDLabel = customIDLabel
    self.monitorPickerCustomPreviewLabel = customPreviewLabel
    self.monitorPickerCustomPreview = customPreview
    self.monitorPickerCustomPreviewIcon = customPreviewIcon
    self.monitorPickerCustomPreviewName = customPreviewName
    self.monitorPickerCustomKind = "item"
    self.monitorPickerCustomAdd = customAdd
    self.monitorPickerManageArea = manageArea
    self.monitorPickerManageIcon = manageIcon
    self.monitorPickerManageName = manageName
    self.monitorPickerManageSource = manageSource
    self.monitorPickerManageGroup = manageGroup
    self.monitorPickerManageMessage = manageMessage
    self.monitorPickerManageAction = manageAction
    self.monitorPickerBlocker = blocker
    self.monitorPickerBlockerText = blockerText
    self.monitorPickerBatchSelection = {}
    return true
end

function DesignerUI:RefreshMonitorPicker(preserveScroll, reuseCatalog)
    if not (self.monitorPicker and self.monitorPicker:IsShown()) then
        return false
    end
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not CanAddMonitor(group) then
        self:HideMonitorPicker()
        return false
    end

    local scrollOffset = preserveScroll ~= false
        and self.monitorPickerScroll.GetVerticalScroll
        and self.monitorPickerScroll:GetVerticalScroll() or 0
    local catalog = reuseCatalog == true and self.monitorPickerCatalog or nil
    local code
    if not catalog then
        catalog, code = Designer:ListMonitorOptions(
            session.selectedGroupId,
            self.monitorPickerSemanticFamily or "cooldown",
            { includeRacials = true }
        )
    end
    if not catalog then
        self:SetStatus(T("designer.error_monitor", "无法读取监控列表。"))
        return nil, code
    end

    self.monitorPickerCatalog = catalog
    local search = NormalizePickerSearch(
        self.monitorPickerSearch and self.monitorPickerSearch:GetText()
    )
    local sections = {}
    for index = 1, #PICKER_SECTION_ORDER do
        sections[PICKER_SECTION_ORDER[index]] = {}
    end
    local options = catalog.options or {}
    for index = 1, #options do
        local option = options[index]
        local section = MonitorPickerDisplaySection(option)
        if option.pickerPresentationValid ~= false
            and MonitorPickerState(option) ~= "preset-management"
            and sections[section]
            and MonitorPickerMatchesSearch(option, search) then
            sections[section][#sections[section] + 1] = option
        end
    end

    for index = 1, #self.monitorPickerHeadings do
        self.monitorPickerHeadings[index]:Hide()
    end
    for index = 1, #self.monitorPickerTiles do
        self.monitorPickerTiles[index]:Hide()
    end

    local y = 0
    local headingIndex = 0
    local tileIndex = 0
    local batchSelection = self.monitorPickerBatchSelection or {}
    for orderIndex = 1, #PICKER_SECTION_ORDER do
        local section = PICKER_SECTION_ORDER[orderIndex]
        local sectionOptions = sections[section]
        if #sectionOptions > 0 then
            headingIndex = headingIndex + 1
            local headingRow = self:AcquireMonitorPickerHeading(headingIndex)
            headingRow:ClearAllPoints()
            headingRow:SetPoint("TOPLEFT", 0, -y)
            headingRow.heading:SetText(MonitorPickerSectionHeading(section))
            headingRow.heading:Show()
            SetShown(headingRow.nativeButton, section == "native-hidden")
            headingRow:Show()
            y = y + 30
            for optionIndex = 1, #sectionOptions do
                local option = sectionOptions[optionIndex]
                tileIndex = tileIndex + 1
                local tile = self:AcquireMonitorPickerTile(tileIndex)
                local column = (optionIndex - 1) % PICKER_COLUMNS
                local row = math.floor((optionIndex - 1) / PICKER_COLUMNS)
                tile:ClearAllPoints()
                tile:SetPoint(
                    "TOPLEFT",
                    column * (PICKER_TILE_WIDTH + PICKER_COLUMN_GAP),
                    -(y + row * PICKER_TILE_HEIGHT)
                )
                tile.option = option
                tile.iconSlot:SetIcon(option.icon or QUESTION_ICON)
                local state = MonitorPickerState(option)
                SetMonitorPickerStateCorner(tile, state)
                local presetLabel = MonitorPickerPresetLabel(option)
                tile.presetLabel:SetText(presetLabel or "")
                SetShown(tile.presetLabel, presetLabel ~= nil)
                SetShown(tile.presetLabelBackdrop, presetLabel ~= nil)
                local unavailable = state == "unavailable"
                    or state == "native-disabled"
                    or state == "preset-management"
                if tile.iconSlot.icon.SetDesaturated then
                    tile.iconSlot.icon:SetDesaturated(unavailable)
                end
                if tile.iconSlot.icon.SetAlpha then
                    tile.iconSlot.icon:SetAlpha(unavailable and 0.55 or 1)
                end
                tile.iconSlot:SetSelected(
                    batchSelection[option.key] ~= nil
                )
                tile:Show()
            end
            y = y + math.ceil(#sectionOptions / PICKER_COLUMNS)
                * PICKER_TILE_HEIGHT + 8
        end
    end

    local child = self.monitorPickerScroll.child
        or self.monitorPickerScroll.scrollChild
    if search == "" then
        headingIndex = headingIndex + 1
        local customHeadingRow = self:AcquireMonitorPickerHeading(headingIndex)
        customHeadingRow:ClearAllPoints()
        customHeadingRow:SetPoint("TOPLEFT", 0, -y)
        customHeadingRow.heading:SetText(T(
            "designer.section.custom_id",
            "自定义监控"
        ))
        customHeadingRow.heading:Show()
        SetShown(customHeadingRow.nativeButton, false)
        customHeadingRow:Show()
        y = y + 30
        local customKinds = CustomMonitorKinds(
            self.monitorPickerSemanticFamily == "buff"
        )
        for customIndex = 1, #customKinds do
            local customKind = customKinds[customIndex]
            local presentation = CustomMonitorPresentation(customKind)
            tileIndex = tileIndex + 1
            local customTile = self:AcquireMonitorPickerTile(tileIndex)
            customTile:ClearAllPoints()
            customTile:SetPoint(
                "TOPLEFT",
                (customIndex - 1)
                    * (PICKER_TILE_WIDTH + PICKER_COLUMN_GAP),
                -y
            )
            customTile.option = {
                key = "custom-entry:" .. customKind,
                kind = "custom-entry",
                customKind = customKind,
                name = T(presentation.titleKey, presentation.title),
                icon = QUESTION_ICON,
                pickerState = "custom",
                presetLabelKey = presentation.labelKey,
                tooltipNoteKey = presentation.descriptionKey,
            }
            customTile.iconSlot:SetIcon(customTile.option.icon)
            SetMonitorPickerStateCorner(customTile, "custom")
            local presetLabel = T(
                presentation.labelKey,
                presentation.label
            )
            customTile.presetLabel:SetText(presetLabel)
            SetShown(customTile.presetLabel, true)
            SetShown(customTile.presetLabelBackdrop, true)
            if customTile.iconSlot.icon.SetDesaturated then
                customTile.iconSlot.icon:SetDesaturated(false)
            end
            if customTile.iconSlot.icon.SetAlpha then
                customTile.iconSlot.icon:SetAlpha(1)
            end
            customTile.iconSlot:SetSelected(false)
            customTile:Show()
        end
        y = y + PICKER_TILE_HEIGHT + 8
    end
    local overlayShown = (self.monitorPickerCustomArea:IsShown()
        or self.monitorPickerManageArea:IsShown())
    local overlayHeight = self.monitorPickerCustomArea:IsShown()
        and PICKER_CUSTOM_OVERLAY_HEIGHT
        or (self.monitorPickerManageArea:IsShown()
            and PICKER_OVERLAY_HEIGHT or 0)
    if child then
        local viewportHeight = self.monitorPickerScroll.GetHeight
            and self.monitorPickerScroll:GetHeight() or 1
        child:SetHeight(math.max(
            y + (overlayShown and overlayHeight + 14 or 8),
            viewportHeight
        ))
    end
    local isBuff = self.monitorPickerSemanticFamily == "buff"
    self.monitorPickerTitle:SetText(string.format(
        isBuff and T(
            "designer.picker.title.buff",
            "添加【光环监控】到%s"
        ) or T(
            "designer.picker.title.cooldown",
            "添加【冷却监控】到%s"
        ),
        GroupName(group)
    ))
    if GUI2.SetBorderColor then
        GUI2:SetBorderColor(
            self.monitorPicker,
            isBuff and "color.badge.purple" or "color.state.success"
        )
    end
    local batchCount = 0
    for _ in pairs(self.monitorPickerBatchSelection or {}) do
        batchCount = batchCount + 1
    end
    self.monitorPickerBatchButton:SetText(
        self.monitorPickerBatchMode == true
            and string.format(
                T("designer.picker.batch_count", "应用 (%d)"),
                batchCount
            )
            or T("designer.picker.batch", "批量")
    )
    self.monitorPickerSearch:SetWidth(
        self.monitorPickerBatchMode == true
            and PICKER_BATCH_SEARCH_WIDTH or PICKER_SEARCH_WIDTH
    )
    SetShown(
        self.monitorPickerBatchCancelButton,
        self.monitorPickerBatchMode == true
    )
    if self.monitorPickerBatchButton.SetDisabled then
        self.monitorPickerBatchButton:SetDisabled(
            self.monitorPickerBatchMode == true and batchCount == 0
        )
    end
    if self.monitorPickerBatchMode == true and batchCount > 0 then
        SetBlizzardPickerButtonStyle(self.monitorPickerBatchButton)
    else
        SetPickerButtonTone(self.monitorPickerBatchButton, "default")
    end
    local customKind = self.monitorPickerCustomKind
        or (isBuff and "self-aura" or "item")
    local presentation = CustomMonitorPresentation(customKind)
    self.monitorPickerCustomHeading:SetText(T(
        presentation.titleKey,
        presentation.title
    ))
    self.monitorPickerCustomDescription:SetText(T(
        presentation.descriptionKey,
        presentation.description
    ))
    self.monitorPickerCustomIDLabel:SetText(T(
        presentation.idKey,
        presentation.id
    ))
    local timed = customKind == "cast-timer"
    SetShown(self.monitorPickerCustomDurationLabel, timed)
    SetShown(self.monitorPickerCustomDuration, timed)
    SetShown(self.monitorPickerCustomIDLabel, true)
    SetShown(self.monitorPickerCustomPreviewLabel, true)
    self.monitorPickerCustomPreviewLabel:ClearAllPoints()
    self.monitorPickerCustomPreview:ClearAllPoints()
    if timed then
        self.monitorPickerCustomPreviewLabel:SetPoint("TOPLEFT", 12, -166)
        self.monitorPickerCustomPreview:SetPoint("TOPLEFT", 120, -158)
    else
        self.monitorPickerCustomPreviewLabel:SetPoint("TOPLEFT", 12, -126)
        self.monitorPickerCustomPreview:SetPoint("TOPLEFT", 120, -118)
    end
    ApplySolidPickerButton(
        self.monitorPickerCustomAdd,
        isBuff and "color.badge.purple" or "color.badge.green",
        isBuff and "color.badge.purple" or "color.state.success"
    )
    self:RefreshMonitorPickerCustomPreview()
    self.monitorPickerRefreshing = true
    if self.monitorPickerScroll.SetVerticalScroll then
        local maxScroll = self.monitorPickerScroll.GetVerticalScrollRange
            and self.monitorPickerScroll:GetVerticalScrollRange() or scrollOffset
        self.monitorPickerScroll:SetVerticalScroll(math.min(scrollOffset, maxScroll or 0))
    end
    self.monitorPickerRefreshing = nil
    return true
end

function DesignerUI:ClearMonitorPickerOverlay()
    if self.monitorPickerCustomArea then self.monitorPickerCustomArea:Hide() end
    if self.monitorPickerManageArea then self.monitorPickerManageArea:Hide() end
    self.monitorPickerOverlayOption = nil
    self.monitorPickerOverlayAction = nil
    if self.monitorPickerCustomID and self.monitorPickerCustomID.ClearFocus then
        self.monitorPickerCustomID:ClearFocus()
    end
    if self.monitorPicker and self.monitorPicker:IsShown() then
        self:RefreshMonitorPicker(true, true)
    end
    return true
end

function DesignerUI:ShowMonitorPickerOverlay(option)
    if type(option) ~= "table" then return false end
    YUI.HideGameTooltip()
    if option.kind == "custom-entry" then
        if self.monitorPickerManageArea then self.monitorPickerManageArea:Hide() end
        self.monitorPickerCustomKind = option.customKind
            or (self.monitorPickerSemanticFamily == "buff"
                and "self-aura" or "item")
        self.monitorPickerOverlayOption = option
        self.monitorPickerOverlayAction = "custom"
        if self.monitorPickerCustomID then
            self.monitorPickerCustomID:SetText("")
        end
        self.monitorPickerCustomArea:Show()
        self:RefreshMonitorPicker(true, true)
        if self.monitorPickerCustomID.SetFocus then
            self.monitorPickerCustomID:SetFocus()
        end
        return true
    end

    self.monitorPickerCustomArea:Hide()
    self.monitorPickerOverlayOption = option
    local state = MonitorPickerState(option)
    local profile = Designer:GetProfile()
    local source = option.kind == "official"
        and (self.monitorPickerSemanticFamily == "buff"
            and T("designer.section.native_buff", "暴雪光环")
            or T("designer.section.official", "暴雪冷却"))
        or T("designer.section.preset_buff", "预设监控")
    local fromGroup = profile and profile.groups and profile.groups.items
        and profile.groups.items[option.fromGroupId]
    self.monitorPickerManageName:SetText(MonitorPickerOptionName(option))
    self.monitorPickerManageSource:SetText(string.format(
        T("designer.picker.source", "来源：%s"),
        source
    ))
    self.monitorPickerManageGroup:SetText(fromGroup and string.format(
        T("designer.picker.group", "所在分组：%s"),
        GroupName(fromGroup)
    ) or "")
    self.monitorPickerManageIcon:SetIcon(option.icon or QUESTION_ICON)

    local actionText
    local message
    local messageColor = "color.text.secondary"
    if state == "current" then
        self.monitorPickerOverlayAction = "delete"
        actionText = T("designer.monitor.delete", "删除监控")
        SetPickerButtonTone(self.monitorPickerManageAction, "danger")
        message = ""
    elseif state == "move" then
        self.monitorPickerOverlayAction = "move"
        actionText = T("designer.picker.move_here", "移动到当前分组")
        SetPickerButtonTone(self.monitorPickerManageAction, "warning")
        message = T(
            "designer.picker.move_help",
            "确认后将从原分组移动到当前分组。"
        )
    elseif state == "native-disabled" then
        self.monitorPickerOverlayAction = "open-blizzard"
        actionText = T("designer.picker.open_blizzard", "前往暴雪冷却")
        SetBlizzardPickerButtonStyle(self.monitorPickerManageAction)
        message = T(
            "designer.picker.native_disabled_help",
            "温馨提醒：先在暴雪冷却中添加并保存，关闭设置后会自动同步。"
        )
        messageColor = "color.state.success"
    elseif state == "preset-management" then
        self.monitorPickerOverlayAction = nil
        SetPickerButtonTone(self.monitorPickerManageAction, "default")
        message = T(
            "designer.picker.preset_managed_help",
            "该条目由预设监控管理，请通过对应预设图标调整。"
        )
    else
        self.monitorPickerOverlayAction = nil
        SetPickerButtonTone(self.monitorPickerManageAction, "default")
        message = T(
            "designer.picker.unavailable_help",
            "当前专精尚未学习或选择该技能。"
        )
    end
    self.monitorPickerManageMessage:SetText(message or "")
    if GUI2.SetTextColorKey then
        GUI2:SetTextColorKey(
            self.monitorPickerManageMessage,
            messageColor
        )
    end
    self.monitorPickerManageAction:SetText(actionText or "")
    SetShown(self.monitorPickerManageAction, actionText ~= nil)
    self.monitorPickerManageArea:Show()
    self:RefreshMonitorPicker(true, true)
    return true
end

function DesignerUI:ExecuteMonitorPickerOverlayAction()
    local option = self.monitorPickerOverlayOption
    local action = self.monitorPickerOverlayAction
    if type(option) ~= "table" or not action then return false end
    if action == "open-blizzard" then
        return self:OpenBlizzardCooldownSettings()
    end
    if action == "move" then
        local result, code = self:ApplyMonitorOption(option)
        if result then self:ClearMonitorPickerOverlay() end
        return result, code
    end
    if action == "delete" and option.monitorId then
        local selected, code = Designer:SelectMonitor(option.monitorId)
        if not selected then return nil, code end
        self.monitorPickerKeepOpenDelete = true
        return self:RequestRemoveSelectedMonitor({ keepPicker = true })
    end
    return false
end

function DesignerUI:ApplyMonitorPickerBatch()
    local selected = self.monitorPickerBatchSelection or {}
    local options = {}
    for _, option in pairs(selected) do
        local state = MonitorPickerState(option)
        if state == "add" or state == "move" then
            options[#options + 1] = option
        end
    end
    if #options == 0 then return false end
    table.sort(options, function(left, right)
        return tostring(left.key or "") < tostring(right.key or "")
    end)
    local results, code = Designer:AddMonitorOptions(options)
    if not results then
        self:SetMutationError(
            code,
            "designer.error_monitor",
            "无法批量处理监控。"
        )
        return nil, code
    end
    self.monitorPickerBatchSelection = {}
    self.monitorPickerBatchMode = false
    self:RefreshAfterStructuralMutation(false)
    self:RefreshMonitorPicker(true)
    self:SetStatus(string.format(
        T("designer.picker.batch_applied", "已应用 %d 个监控。"),
        #results
    ))
    return results
end

function DesignerUI:ToggleMonitorPickerBatch()
    if self.monitorPickerBatchMode == true then
        local count = 0
        for _ in pairs(self.monitorPickerBatchSelection or {}) do
            count = count + 1
        end
        if count > 0 then return self:ApplyMonitorPickerBatch() end
        return self:CancelMonitorPickerBatch()
    else
        if self.monitorPickerCustomArea then self.monitorPickerCustomArea:Hide() end
        if self.monitorPickerManageArea then self.monitorPickerManageArea:Hide() end
        self.monitorPickerOverlayOption = nil
        self.monitorPickerOverlayAction = nil
        self.monitorPickerBatchMode = true
    end
    self.monitorPickerBatchSelection = {}
    self:RefreshMonitorPicker(true, true)
    return true
end

function DesignerUI:CancelMonitorPickerBatch()
    if self.monitorPickerBatchMode ~= true then return false end
    self.monitorPickerBatchMode = false
    self.monitorPickerBatchSelection = {}
    if self.monitorPickerSearch and self.monitorPickerSearch.ClearFocus then
        self.monitorPickerSearch:ClearFocus()
    end
    self:RefreshMonitorPicker(true, true)
    return true
end

function DesignerUI:SetMonitorPickerBlocked(blocked, syncing)
    self.monitorPickerBlocked = blocked == true
    if not self.monitorPickerBlocker then return false end
    self.monitorPickerBlockerText:SetText(syncing and T(
        "designer.picker.blizzard_syncing",
        "正在同步暴雪冷却内容…"
    ) or T(
        "designer.picker.blizzard_blocked",
        "关闭暴雪冷却后，自动同步内容。"
    ))
    SetShown(self.monitorPickerBlocker, blocked == true)
    if blocked and self.monitorPickerSearch
        and self.monitorPickerSearch.ClearFocus then
        self.monitorPickerSearch:ClearFocus()
    end
    return true
end

function DesignerUI:SynchronizeMonitorPickerFromBlizzard()
    if not (self.monitorPicker and self.monitorPicker:IsShown()) then
        self:SetMonitorPickerBlocked(false)
        return true
    end
    self:SetMonitorPickerBlocked(true, true)
    local ok, code = self:RefreshMonitorPicker(true)
    self:SetMonitorPickerBlocked(false)
    if not ok then
        self:SetStatus(T(
            "designer.picker.blizzard_sync_failed",
            "无法同步暴雪冷却内容，已保留原列表。"
        ))
        return nil, code
    end
    self:SetStatus(T(
        "designer.picker.blizzard_synced",
        "已同步暴雪冷却内容"
    ))
    return true
end

function DesignerUI:OpenMonitorPicker(groupId, semanticFamily)
    if InCombat() then
        self:SetStatus(T("designer.error_combat", "战斗中不能修改内容设置。"))
        return false
    end
    self:HideGlowEditor()
    if groupId then
        local session = Designer:GetSession()
        if not session or session.selectedGroupId ~= groupId then
            local selected = Designer:SelectGroup(groupId)
            if not selected then return false end
            self.manualPanel = false
            self:Refresh(true)
        end
    end

    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not CanAddMonitor(group) then
        self:SetStatus(T(
            "designer.error_monitor_type",
            "当前显示类型暂不支持添加图标监控。"
        ))
        return false
    end
    semanticFamily = semanticFamily == "buff" and "buff" or "cooldown"
    local capabilities = YHUD:GetGroupAddCapabilities(group)
    if not capabilities[semanticFamily] then
        self:SetStatus(T(
            "designer.error_monitor_type",
            "当前分组不能接收这种监控。"
        ))
        return false
    end

    local ready, code = self:EnsureMonitorPicker()
    if not ready then
        self:SetStatus(T("designer.error_monitor", "无法打开监控列表。"))
        return nil, code
    end
    self.monitorPickerSemanticFamily = semanticFamily
    self.monitorPickerCustomKind =
        semanticFamily == "buff" and "spell" or self.monitorPickerCustomKind
    self.monitorPickerExpandedFolders = {}
    self.monitorPickerBatchMode = false
    self.monitorPickerBatchSelection = {}
    self.monitorPickerOverlayOption = nil
    self.monitorPickerOverlayAction = nil
    self.monitorPickerCustomArea:Hide()
    self.monitorPickerManageArea:Hide()
    if self.monitorPickerSearch.SetText then
        self.monitorPickerRefreshing = true
        self.monitorPickerSearch:SetText("")
        self.monitorPickerRefreshing = nil
    end
    self.monitorPicker:Show()
    local refreshed, refreshCode = self:RefreshMonitorPicker(false)
    local cooldownSettings = _G.CooldownViewerSettings
    if cooldownSettings and cooldownSettings.IsShown
        and cooldownSettings:IsShown() then
        self:SetMonitorPickerBlocked(true)
    else
        self:SetMonitorPickerBlocked(false)
    end
    return refreshed, refreshCode
end

function DesignerUI:HideMonitorPicker()
    if self.monitorPicker then self.monitorPicker:Hide() end
    if self.monitorPickerSearch and self.monitorPickerSearch.ClearFocus then
        self.monitorPickerSearch:ClearFocus()
    end
    if self.monitorPickerCustomID and self.monitorPickerCustomID.ClearFocus then
        self.monitorPickerCustomID:ClearFocus()
    end
    if self.monitorPickerCustomArea then self.monitorPickerCustomArea:Hide() end
    if self.monitorPickerManageArea then self.monitorPickerManageArea:Hide() end
    if self.monitorPickerBlocker then self.monitorPickerBlocker:Hide() end
    self.monitorPickerSemanticFamily = nil
    self.monitorPickerExpandedFolders = {}
    self.monitorPickerBatchMode = false
    self.monitorPickerBatchSelection = {}
    self.monitorPickerOverlayOption = nil
    self.monitorPickerOverlayAction = nil
    self.monitorPickerBlocked = false
    self.monitorPickerCatalog = nil
    self.monitorPickerKeepOpenDelete = nil
end

function DesignerUI:HandleMonitorPickerOption(option)
    if type(option) ~= "table" then return false end
    if self.monitorPickerBlocked == true then return false end
    local state = MonitorPickerState(option)
    if self.monitorPickerBatchMode == true then
        if state ~= "add" and state ~= "move" then return false end
        self.monitorPickerBatchSelection = self.monitorPickerBatchSelection or {}
        if self.monitorPickerBatchSelection[option.key] then
            self.monitorPickerBatchSelection[option.key] = nil
        else
            self.monitorPickerBatchSelection[option.key] = option
        end
        return self:RefreshMonitorPicker(true, true)
    end
    if state == "add" then return self:ApplyMonitorOption(option) end
    return self:ShowMonitorPickerOverlay(option)
end

function DesignerUI:ApplyMonitorOption(option)
    if type(option) ~= "table" then return false end
    local result, code = Designer:AddMonitorOption(option)
    if not result then
        self:SetMutationError(
            code,
            "designer.error_monitor",
            "无法添加监控。"
        )
        return nil, code
    end
    self:RefreshAfterStructuralMutation(false)
    self:RefreshMonitorPicker(true)
    if result.action == "move" then
        self:SetStatus(T("designer.status_monitor_moved", "监控已移动到当前分组。"))
    elseif result.action == "current" then
        self:SetStatus(T("designer.status_monitor_current", "该监控已在当前分组。"))
    else
        local profile = Designer:GetProfile()
        local group = profile and result.groupId and profile.groups
            and profile.groups.items[result.groupId]
        self:SetStatus(string.format(
            T("designer.picker.added_to", "已添加到：%s"),
            GroupName(group)
        ))
    end
    return result
end

function DesignerUI:AddCustomSpell(spellID)
    local result, code = Designer:AddCustomSpell(spellID)
    if not result then
        self:SetStatus(T("designer.error_spell", "无法添加该法术。"))
        return nil, code
    end
    if self.monitorPickerCustomID then
        self.monitorPickerCustomID:SetText("")
    end
    self:RefreshAfterStructuralMutation(false)
    self:RefreshMonitorPicker()
    if result.action == "move" then
        self:SetStatus(T("designer.status_monitor_moved", "监控已移动到当前分组。"))
    elseif result.action == "current" then
        self:SetStatus(T("designer.status_monitor_current", "该监控已在当前分组。"))
    else
        self:SetStatus(T("designer.status_monitor_added", "监控已添加。"))
    end
    return result
end

function DesignerUI:AddCustomItem(itemID)
    local result, code = Designer:AddCustomItem(itemID)
    if not result then
        self:SetMutationError(
            code,
            "designer.error_item",
            "无法添加该物品。"
        )
        return nil, code
    end
    if self.monitorPickerCustomID then
        self.monitorPickerCustomID:SetText("")
    end
    self:RefreshAfterStructuralMutation(false)
    self:RefreshMonitorPicker()
    if result.action == "move" then
        self:SetStatus(T("designer.status_monitor_moved", "监控已移动到当前分组。"))
    elseif result.action == "current" then
        self:SetStatus(T("designer.status_monitor_current", "该监控已在当前分组。"))
    else
        self:SetStatus(T("designer.status_monitor_added", "监控已添加。"))
    end
    return result
end

function DesignerUI:AddCustomAura(spellID, scopeKey)
    local result, code = Designer:AddCustomAura(spellID, scopeKey)
    if not result then
        self:SetMutationError(
            code,
            "designer.error_custom_aura",
            "无法添加该光环。"
        )
        return nil, code
    end
    if self.monitorPickerCustomID then
        self.monitorPickerCustomID:SetText("")
    end
    self:RefreshAfterStructuralMutation(false)
    self:RefreshMonitorPicker()
    if result.action == "move" then
        self:SetStatus(T(
            "designer.status_monitor_moved",
            "监控已移动到当前分组。"
        ))
    elseif result.action == "current" then
        self:SetStatus(T(
            "designer.status_monitor_current",
            "该监控已在当前分组。"
        ))
    else
        self:SetStatus(T(
            "designer.status_custom_aura_added",
            "光环监控已添加。"
        ))
    end
    return result
end

function DesignerUI:AddCustomMonitorID(value)
    local kind = self.monitorPickerCustomKind
    if kind == "self-aura" then
        return self:AddCustomAura(
            value,
            YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
        )
    end
    if kind == "target-debuff" then
        return self:AddCustomAura(
            value,
            YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL
        )
    end
    if kind == "cast-timer" then
        local duration = self.monitorPickerCustomDuration
            and self.monitorPickerCustomDuration:GetText()
        local result, code = Designer:AddCustomBuffTimer(value, duration)
        if not result then
            self:SetStatus(T(
                "designer.error_timed_buff",
                "无法添加该施法计时。"
            ))
            return nil, code
        end
        if self.monitorPickerCustomID then
            self.monitorPickerCustomID:SetText("")
        end
        self:RefreshAfterStructuralMutation(false)
        self:RefreshMonitorPicker()
        self:SetStatus(T(
            "designer.status_timed_buff_added",
            "施法计时已添加。"
        ))
        return result
    end
    if self.monitorPickerCustomKind == "item" then
        return self:AddCustomItem(value)
    end
    return self:AddCustomSpell(value)
end

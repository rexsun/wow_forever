local YUI = _G.YUI
if not YUI then return end

local Dev = YUI.Dev
if not Dev then return end

local Lab = Dev.MonitorDev or {}
Dev.MonitorDev = Lab

local function CoreText(key, fallback)
    local locale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("Core") or nil
    local value = locale and locale[key]
    if value and value ~= key then return value end
    return fallback or key
end

local ipairs = ipairs
local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pairs = pairs
local pcall = pcall
local string_format = string.format
local string_find = string.find
local string_gsub = string.gsub
local string_lower = string.lower
local string_match = string.match
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type
local unpack = unpack

local WINDOW_NAME = "YUI_MonitorDevLabFrame"
local DEV_PREFIX = "dev.monitor."
local DEFAULT_MONITOR_ID = "test"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_ICON_TEXCOORDS = { 0.08, 0.92, 0.08, 0.92 }
local ICON_PICKER_RECENT_LIMIT = 24
local ICON_PICKER_SEARCH_LIMIT = 360
local ICON_PICKER_COLUMNS = 8
local ICON_PICKER_ROWS = 5
local ICON_PICKER_PAGE_SIZE = ICON_PICKER_COLUMNS * ICON_PICKER_ROWS
local FIELD_LABEL_WIDTH = 112
local FIELD_CONTROL_WIDTH = 300

local TAB_ORDER = {
    { id = "visual", label = "图示", width = 76 },
    { id = "triggers", label = "触发器", width = 86 },
    { id = "conditions", label = "条件", width = 76 },
    { id = "load", label = "载入", width = 76 },
    { id = "logs", label = "日志", width = 76 },
}

local LOG_EVENT_OPTIONS = {
    { text = "全部", value = "" },
    { text = "register", value = "register" },
    { text = "unregister", value = "unregister" },
    { text = "set-enabled", value = "set-enabled" },
    { text = "load", value = "load" },
    { text = "refresh", value = "refresh" },
    { text = "trigger", value = "trigger" },
    { text = "trigger-inject", value = "trigger-inject" },
    { text = "expression", value = "expression" },
    { text = "active-change", value = "active-change" },
    { text = "presenter", value = "presenter" },
    { text = "tick", value = "tick" },
    { text = "error", value = "error" },
}

local UNIT_OPTIONS = {
    { text = "玩家", value = "player" },
    { text = "目标", value = "target" },
    { text = "焦点", value = "focus" },
    { text = "鼠标指向", value = "mouseover" },
    { text = "宠物", value = "pet" },
}

local COMMON_EVENT_NAMES = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGIN",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
    "UNIT_SPELLCAST_SUCCEEDED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "SPELLS_CHANGED",
}

local APPEARANCE_TYPES = {
    { text = "图标", value = "icon" },
    { text = "条", value = "bar" },
    { text = "文字", value = "text" },
}

local ICON_SHAPE_OPTIONS = {
    { text = "方形", value = "square" },
    { text = "圆角", value = "rounded" },
}

local ICON_MODE_OPTIONS = {
    { text = "自动", value = "auto" },
    { text = "手动", value = "manual" },
}

local TEXT_FONT_SIZE_OPTIONS = {
    { text = "小", value = "font.size.sm" },
    { text = "中", value = "font.size.md" },
    { text = "大", value = "font.size.lg" },
    { text = "标题", value = "font.size.xl" },
}

local STRATA_OPTIONS = {
    { text = "BACKGROUND", value = "BACKGROUND" },
    { text = "LOW", value = "LOW" },
    { text = "MEDIUM", value = "MEDIUM" },
    { text = "HIGH", value = "HIGH" },
    { text = "DIALOG", value = "DIALOG" },
    { text = "FULLSCREEN", value = "FULLSCREEN" },
}

local LOAD_MODE_OPTIONS = {
    { text = "总是启用", value = "always" },
    { text = "总是禁用", value = "never" },
    { text = "声明式条件", value = "table" },
}

local TRI_BOOL_OPTIONS = {
    { text = "任意", value = "" },
    { text = "是", value = "true" },
    { text = "否", value = "false" },
}

local EXPRESSION_TEMPLATE_OPTIONS = {
    { text = "自定义表达式", value = "custom" },
    { text = "任意触发器", value = "any" },
    { text = "全部触发器", value = "all" },
    { text = "第一个触发器", value = "first" },
    { text = "始终激活", value = "always" },
    { text = "始终不激活", value = "never" },
}

local CONDITION_OPERATOR_OPTIONS = {
    { text = "为真", value = "truthy" },
    { text = "为假", value = "falsy" },
    { text = "等于", value = "equals" },
    { text = "不等于", value = "notEquals" },
    { text = "大于", value = "gt" },
    { text = "大于等于", value = "gte" },
    { text = "小于", value = "lt" },
    { text = "小于等于", value = "lte" },
    { text = "包含文本", value = "contains" },
}

local CONDITION_BASE_ACTION_OPTIONS = {
    { text = "可见性", value = "visible" },
    { text = "框体宽度", value = "frame.width" },
    { text = "框体高度", value = "frame.height" },
    { text = "基础图标", value = "base.icon" },
    { text = "基础尺寸", value = "base.size" },
    { text = "基础文本", value = "base.text" },
    { text = "基础文本颜色", value = "base.color" },
    { text = "基础进度值", value = "base.value" },
    { text = "基础进度颜色", value = "base.fillColor" },
}

local FIELD_LABELS = {
    type = "类型",
    unit = "单位",
    event = "事件",
    spellID = "法术 ID",
    spellId = "法术 ID",
    duration = "持续时间(秒)",
    icon = "图标",
    matchBaseSpellID = "匹配基础法术 ID",
    template = "模板",
    threshold = "阈值",
}

local FIELD_HELP = {
    event = "选择触发事件。不同事件会显示不同参数。",
    duration = "脉冲持续时间，单位秒。事件、施法成功、冷却窗口触发后，会在这段时间内保持 active。",
    matchBaseSpellID = "开启后，冷却事件的基础法术 ID 也可匹配；关闭后只匹配事件传入的法术 ID。",
}

local TRIGGER_HELP = {
    playerAura = "玩家光环：检查 player 身上的指定法术光环。",
    unitAura = "单位光环：检查指定单位身上的指定法术光环。",
    unitSpellcastSucceeded = "施法成功：指定单位成功施放某个法术时产生一个短暂脉冲。",
    event = "事件：指定 WoW/YUI 事件发生时产生一个短暂脉冲。",
    spellCooldownWindow = "技能冷却窗口：技能进入冷却窗口时触发，并按持续时间更新进度。",
    derived = "派生触发：从上下文或模板计算出来的触发器，常用于组合和测试。",
}

local CONDITION_NAMES = {
    "onEnable",
    "onDisable",
    "onActivate",
    "onDeactivate",
    "onStateChange",
    "onTrigger",
    "onUpdate",
    "onDestroy",
}

local TRIGGER_TYPE_LABELS = {
    playerAura = "玩家光环",
    unitAura = "单位光环",
    unitSpellcastSucceeded = "施法成功",
    event = "事件",
    spellCooldownWindow = "技能冷却窗口",
    derived = "派生触发",
}

local STAT_LABELS = {
    instances = "实例",
    activeTickers = "活动 ticker",
    refreshes = "刷新",
    triggerUpdates = "触发更新",
    presenterUpdates = "渲染更新",
    logEnabled = "日志启用",
    logCount = "日志数量",
    logLimit = "日志上限",
    triggerSchemas = "触发器 schema",
}

local function Trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SplitCSV(text)
    local rows = {}
    text = tostring(text or "")
    for item in string.gmatch(text, "[^,%s]+") do
        rows[#rows + 1] = item
    end
    return rows
end

local function JoinCSV(list)
    if type(list) ~= "table" then return "" end
    local rows = {}
    for _, value in ipairs(list) do
        rows[#rows + 1] = tostring(value)
    end
    return table_concat(rows, ",")
end

local function Print(...)
    if YUI.Print then
        YUI:Print(...)
    else
        print(...)
    end
end

local function GUI2()
    return YUI.GUI2 or YUI.GUI
end

local function Monitor()
    return YUI.Monitor
end

local function InCombat()
    return _G.InCombatLockdown and _G.InCombatLockdown()
end

local function ClearFrame(frame)
    if not frame then return end
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        region:Hide()
        region:SetParent(nil)
    end
end

local function CopyTable(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = CopyTable(value)
    end
    return copy
end

local function StartsWith(text, prefix)
    return type(text) == "string" and string.sub(text, 1, #prefix) == prefix
end

local function FormatBool(value)
    return value and "是" or "否"
end

local function FormatTime(value)
    if type(value) ~= "number" then return "-" end
    return string_format("%.2f", value)
end

local function ClampNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function BoolToTri(value)
    if value == true then return "true" end
    if value == false then return "false" end
    return ""
end

local function TriToBool(value)
    if value == "true" then return true end
    if value == "false" then return false end
    return nil
end

local function ShortLabel(text, maxLen)
    text = tostring(text or "")
    maxLen = maxLen or 34
    if #text <= maxLen then return text end
    local tail = string_match(text, "([^%.]+)$") or text
    if #tail <= maxLen then return tail end
    return string.sub(tail, 1, maxLen - 3) .. "..."
end

local function GetMonitorNameFromDefinition(definition, fallback)
    if type(definition) == "table" then
        local name = Trim(definition.name or definition.displayName or "")
        if name ~= "" then return name end
    end
    return tostring(fallback or DEFAULT_MONITOR_ID)
end

local function GetMonitorName(row)
    local name = Trim(row and (row.name or row.displayName) or "")
    if name ~= "" then return name end
    return tostring(row and row.id or DEFAULT_MONITOR_ID)
end

local function BuildMonitorNameSet(excludeId)
    local monitor = Monitor()
    local names = {}
    if monitor and monitor.ListDetailed then
        for _, row in ipairs(monitor:ListDetailed()) do
            if row.id ~= excludeId then
                local name = string_lower(GetMonitorName(row))
                if name ~= "" then names[name] = true end
            end
        end
    end
    return names
end

local function MakeUniqueMonitorName(base, excludeId)
    base = Trim(base or "")
    if base == "" then base = "新建监控" end
    local used = BuildMonitorNameSet(excludeId)
    local candidate = base
    local index = 2
    while used[string_lower(candidate)] do
        candidate = base .. " " .. tostring(index)
        index = index + 1
    end
    return candidate
end

local function MakeUniqueDevRawId()
    local monitor = Monitor()
    local index = 1
    while true do
        local rawId = "custom" .. tostring(index)
        local fullId = DEV_PREFIX .. rawId
        if not (monitor and monitor.Get and monitor:Get(fullId)) then
            return rawId
        end
        index = index + 1
    end
end

local function ValidateMonitorName(name, excludeId)
    name = Trim(name or "")
    if name == "" then
        return false, "名称不能为空。"
    end
    local used = BuildMonitorNameSet(excludeId)
    if used[string_lower(name)] then
        return false, "名称不能重复。"
    end
    return true
end

local function ParseBoolText(value)
    if value == true or value == "true" or value == "1" or value == 1 or value == "是" then return true end
    if value == false or value == "false" or value == "0" or value == 0 or value == "否" then return false end
    return nil
end

local function ParseColorText(value)
    if type(value) == "table" then return CopyTable(value) end
    local parts = SplitCSV(value)
    if #parts < 3 then return nil end
    return {
        tonumber(parts[1]) or 1,
        tonumber(parts[2]) or 1,
        tonumber(parts[3]) or 1,
        tonumber(parts[4]) or 1,
    }
end

local function FormatColorText(value, fallback)
    if type(value) == "table" then return JoinCSV(value) end
    if value ~= nil and value ~= "" then return tostring(value) end
    return fallback or ""
end

local function ApplyTextColor(fontString, value)
    local color = ParseColorText(value)
    if fontString and color and fontString.SetTextColor then
        fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function LooksLikeIconPath(value)
    return type(value) == "string" and (value:find("\\", 1, true) or value:find("/", 1, true) or value:find("^Interface") or value:find("%.") or value:find("^atlas:"))
end

local function ApplyIconSource(texture, source, fallback)
    if not texture then return false end
    local iconSource = source
    if iconSource == nil or iconSource == "" then iconSource = fallback end
    if iconSource == nil or iconSource == "" then iconSource = DEFAULT_ICON end
    if type(iconSource) == "string" and string.sub(iconSource, 1, 6) == "atlas:" and texture.SetAtlas then
        texture:SetTexture(nil)
        texture:SetAtlas(string.sub(iconSource, 7), false)
        texture.yuiMonitorAtlas = true
        return true
    end
    texture:SetTexture(iconSource)
    texture.yuiMonitorAtlas = nil
    return false
end

local function GetCoverTexCoords(width, height)
    local left, right, top, bottom = DEFAULT_ICON_TEXCOORDS[1], DEFAULT_ICON_TEXCOORDS[2], DEFAULT_ICON_TEXCOORDS[3], DEFAULT_ICON_TEXCOORDS[4]
    width = tonumber(width) or 1
    height = math_max(tonumber(height) or 1, 1)
    local targetRatio = width / height
    local sourceRatio = (right - left) / math_max(bottom - top, 0.0001)
    if targetRatio > sourceRatio then
        local visibleHeight = (right - left) / targetRatio
        local center = (top + bottom) / 2
        top = center - (visibleHeight / 2)
        bottom = center + (visibleHeight / 2)
    elseif targetRatio < sourceRatio then
        local visibleWidth = (bottom - top) * targetRatio
        local center = (left + right) / 2
        left = center - (visibleWidth / 2)
        right = center + (visibleWidth / 2)
    end
    return left, right, top, bottom
end

local function ApplyIconTextureFit(texture, width, height, base)
    if not texture or texture.yuiMonitorAtlas then return end
    base = type(base) == "table" and base or {}
    if type(base.texCoords) == "table" then
        texture:SetTexCoord(unpack(base.texCoords))
        return
    end
    if base.textureFit == "contain" then
        texture:SetTexCoord(DEFAULT_ICON_TEXCOORDS[1], DEFAULT_ICON_TEXCOORDS[2], DEFAULT_ICON_TEXCOORDS[3], DEFAULT_ICON_TEXCOORDS[4])
        return
    end
    texture:SetTexCoord(GetCoverTexCoords(width, height))
end

local function FormatRuleValue(value)
    if type(value) == "table" then return JoinCSV(value) end
    if value == true then return "true" end
    if value == false then return "false" end
    return tostring(value or "")
end

local function ParseRuleActionValue(target, value)
    if target == "visible" or string_match(tostring(target or ""), "%.visible$") then
        local boolValue = ParseBoolText(value)
        if boolValue ~= nil then return boolValue end
        return value
    end
    if target == "frame.width" or target == "frame.height" or target == "base.size" or target == "base.value" or string_match(tostring(target or ""), "%.value$") then
        return tonumber(value) or value
    end
    if target == "base.color" or target == "base.fillColor" or string_match(tostring(target or ""), "%.color$") or string_match(tostring(target or ""), "%.fillColor$") then
        return ParseColorText(value) or value
    end
    return value
end

local CreateButton

local function CreateGroupHeader(parent, key, title, x, y, width)
    local collapsed = Lab.collapsedGroups and Lab.collapsedGroups[key] == true
    local button = CreateButton(parent, (collapsed and "+ " or "- ") .. title, width or 660, function()
        Lab.collapsedGroups = Lab.collapsedGroups or {}
        Lab.collapsedGroups[key] = not collapsed
        Lab:Render()
    end)
    button:SetPoint("TOPLEFT", x or 14, y)
    return y - 34, not collapsed
end

local function CreateText(parent, text, size, color, justify)
    local gui = GUI2()
    if not (gui and gui.CreateText) then return nil end
    local fontSize = size or "font.size.sm"
    local colorKey = color or "color.text.primary"
    local label = gui:CreateText(parent, text or "", fontSize, colorKey, justify or "LEFT")
    return label
end

function CreateButton(parent, text, width, onClick, tooltip)
    local gui = GUI2()
    if gui and gui.Form and gui.Form.CreateButton then
        return gui.Form:CreateButton(parent, {
            text = text or "",
            width = width or 92,
            height = 26,
            tooltip = tooltip,
            onClick = onClick,
        })
    end
    local button = gui:CreateButtonFrame(parent, { template = "BackdropTemplate", width = width or 92, height = 26 })
    button.text = gui:CreateText(button, text or "", "font.size.sm", "color.text.primary", "CENTER")
    button.text:SetPoint("CENTER")
    button:SetScript("OnClick", onClick)
    return button
end

local function AttachSimpleTooltip(frame, tooltip)
    if not (frame and tooltip and tooltip ~= "" and GameTooltip) then return end
    frame:HookScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsOwned(frame) and YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        elseif GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function SetButtonDisabled(button, disabled)
    if not button then return end
    if button.SetDisabled then
        button:SetDisabled(disabled == true)
    elseif button.SetState then
        button:SetState(disabled and "disabled" or "normal")
    else
        button.gui2Disabled = disabled == true
    end
end

local function CreateActionButton(parent, text, width, onClick, disabled, tooltip)
    local button = CreateButton(parent, text, width, function()
        if disabled then return end
        if onClick then onClick() end
    end, tooltip)
    SetButtonDisabled(button, disabled == true)
    return button
end

local function SetButtonSelected(button, selected)
    if not button then return end
    if button.SetSelected then
        button:SetSelected(selected == true)
    elseif button.SetState then
        button:SetState(selected and "selected" or "normal")
    end
end

local function CreateEdit(parent, value, width, onChange, numeric, tooltip)
    local gui = GUI2()
    local edit = gui.Form:CreateEditBox(parent, {
        width = width or 180,
        height = 24,
        numeric = numeric == true,
        autoFocus = false,
        text = "",
        tooltip = tooltip,
    })
    local previousOnTextChanged = edit.GetScript and edit:GetScript("OnTextChanged")
    if edit.SetScript then
        edit:SetScript("OnTextChanged", function(box, userInput)
            if previousOnTextChanged then previousOnTextChanged(box, userInput) end
            if box.monitorDevSettingText then return end
            if onChange then onChange(box:GetText()) end
        end)
    end
    if edit.SetText and value ~= nil then
        edit.monitorDevSettingText = true
        edit:SetText(tostring(value))
        edit.monitorDevSettingText = nil
    end
    return edit
end

local function CreateDropdown(parent, value, options, width, onChange, tooltip)
    local gui = GUI2()
    return gui.Form:CreateDropdown(parent, {
        width = width or 180,
        height = 24,
        value = value,
        options = options or {},
        tooltip = tooltip,
        set = function(nextValue)
            if onChange then onChange(nextValue) end
        end,
    })
end

local function CreateCheckbox(parent, text, checked, width, onChange, tooltip)
    local gui = GUI2()
    return gui.Form:CreateCheckbox(parent, {
        width = width or 160,
        height = 22,
        text = text or "",
        checked = checked == true,
        tooltip = tooltip,
        set = function(value)
            if onChange then onChange(value == true) end
        end,
    })
end

local function CreatePanel(parent, opts)
    local gui = GUI2()
    return gui:CreatePanel(parent, opts or {})
end

local function CreateLine(parent, y, text, color, width)
    local label = CreateText(parent, text, "font.size.sm", color or "color.text.secondary")
    if not label then return nil end
    label:SetPoint("TOPLEFT", 14, y)
    label:SetSize(width or 560, 20)
    return label
end

local function CreateSectionTitle(parent, y, text)
    local label = CreateText(parent, text, "font.size.md", "color.text.heading")
    label:SetPoint("TOPLEFT", 14, y)
    label:SetSize(560, 22)
    return y - 28
end

local function CreateDividerHeader(parent, key, y, text, width)
    local x = 14
    width = width or 800
    local collapsed = Lab.collapsedGroups and Lab.collapsedGroups[key] == true
    local function toggleSection(nextCollapsed)
        Lab.collapsedGroups = Lab.collapsedGroups or {}
        Lab.collapsedGroups[key] = nextCollapsed == true
        Lab:Render()
    end

    local gui = GUI2()
    if gui and gui.CreateDivider then
        local divider = gui:CreateDivider(parent, {
            width = width,
            height = 24,
            label = text,
            alignLeft = true,
            collapsible = true,
            collapsed = collapsed,
            labelWidth = 118,
            onToggle = toggleSection,
        })
        divider:SetPoint("TOPLEFT", x, y)
        return y - 26, not collapsed
    end

    local label = CreateText(parent, text, "font.size.md", "color.text.heading")
    label:SetPoint("TOPLEFT", x, y - 1)
    label:SetSize(118, 18)
    local line = CreatePanel(parent, { width = math_max(width - 128, 120), height = 1, surface = "color.border.subtle" })
    line:SetPoint("TOPLEFT", x + 128, y - 10)
    return y - 26, not collapsed
end

local function CreateFieldLabel(parent, x, y, text, width)
    local label = CreateText(parent, text, "font.size.sm", "color.text.secondary")
    label:SetPoint("TOPLEFT", x, y - 2)
    label:SetSize(width or 112, 20)
    return label
end

local function CreateEditField(parent, x, y, label, value, width, onChange, numeric, tooltip, labelWidth)
    labelWidth = labelWidth or 112
    CreateFieldLabel(parent, x, y, label, labelWidth)
    local edit = CreateEdit(parent, value, width or 180, onChange, numeric, tooltip)
    edit:SetPoint("TOPLEFT", x + labelWidth, y)
    return edit
end

local function CreateDropdownField(parent, x, y, label, value, options, width, onChange, tooltip, labelWidth)
    labelWidth = labelWidth or 112
    CreateFieldLabel(parent, x, y, label, labelWidth)
    local dropdown = CreateDropdown(parent, value, options, width or 180, onChange, tooltip)
    dropdown:SetPoint("TOPLEFT", x + labelWidth, y)
    return dropdown
end

local function CreateSpellIDField(parent, x, y, label, value, width, onChange, tooltip, labelWidth)
    labelWidth = labelWidth or 112
    CreateFieldLabel(parent, x, y, label, labelWidth)
    local gui = GUI2()
    if gui and gui.Form and gui.Form.CreateSpellIDInput then
        local input = gui.Form:CreateSpellIDInput(parent, {
            width = width or 300,
            inputWidth = 96,
            height = 24,
            value = value,
            fallbackIcon = DEFAULT_ICON,
            tooltip = tooltip,
            onChange = function(nextValue)
                if onChange then onChange(nextValue) end
            end,
        })
        input:SetPoint("TOPLEFT", x + labelWidth, y)
        return input
    end
    return CreateEditField(parent, x, y, label, value, width or 190, onChange, true, tooltip, labelWidth)
end

local function CreateCheckboxField(parent, x, y, label, checked, onChange, tooltip)
    local checkbox = CreateCheckbox(parent, label, checked, 220, onChange, tooltip)
    checkbox:SetPoint("TOPLEFT", x, y)
    return checkbox
end

local function CreateRectIcon(parent, width, height, source, base)
    local gui = GUI2()
    if not (gui and parent) then return nil end
    base = type(base) == "table" and base or {}
    local slot = CreatePanel(parent, {
        width = width or 64,
        height = height or 64,
        surface = "color.surface.sunken",
        border = "color.border.default",
        radiusKey = base.shape == "rounded" and "layout.radius.control" or "layout.radius.icon",
    })
    local icon
    if gui.CreateIcon then
        icon = gui:CreateIcon(slot, {
            icon = DEFAULT_ICON,
            crop = false,
            fillParent = true,
            padding = tonumber(base.padding) or 0,
        })
    else
        icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(slot)
    end
    slot.icon = icon
    slot.SetIcon = function(frame, nextSource, nextBase)
        nextBase = type(nextBase) == "table" and nextBase or base
        ApplyIconSource(frame.icon, nextSource, DEFAULT_ICON)
        ApplyIconTextureFit(frame.icon, frame:GetWidth() or width or 64, frame:GetHeight() or height or 64, nextBase)
    end
    slot.SetIconLayout = function(frame, nextWidth, nextHeight, nextBase)
        nextBase = type(nextBase) == "table" and nextBase or base
        frame:SetSize(nextWidth or width or 64, nextHeight or height or 64)
        local padding = tonumber(nextBase.padding) or 0
        frame.icon:ClearAllPoints()
        if padding <= 0 then
            frame.icon:SetAllPoints(frame)
        else
            frame.icon:SetPoint("TOPLEFT", padding, -padding)
            frame.icon:SetPoint("BOTTOMRIGHT", -padding, padding)
        end
        frame:SetIcon(nextBase.icon or source or DEFAULT_ICON, nextBase)
    end
    slot:SetIconLayout(width or 64, height or 64, base)
    slot:SetIcon(source or base.icon or DEFAULT_ICON, base)
    return slot
end

function Lab:SetStatus(message, tone)
    self.statusMessage = message
    self.statusTone = tone or "info"
end

function Lab:GetStatusColor()
    if self.statusTone == "success" then return "color.state.success" end
    if self.statusTone == "warning" then return "color.state.warning" end
    if self.statusTone == "error" then return "color.state.error" end
    return "color.text.secondary"
end

function Lab:RenderStatus(parent, y)
    if not self.statusMessage then return y end
    CreateLine(parent, y, self.statusMessage, self:GetStatusColor(), 620)
    return y - 24
end

function Lab:ResetDraft()
    self.draft = {
        id = DEFAULT_MONITOR_ID,
        name = "新建监控",
        moduleId = "dev.monitor",
        appearance = {
            type = "icon",
            width = 64,
            height = 64,
            point = { point = "CENTER", x = 0, y = -160 },
            strata = "MEDIUM",
            mouse = false,
            clampedToScreen = true,
            base = { type = "icon", iconMode = "auto", icon = DEFAULT_ICON, padding = 0, shape = "square", textureFit = "cover" },
            overlays = {
                { type = "text", text = "预览", point = { point = "BOTTOM", x = 0, y = -16 }, fontSize = "font.size.sm" },
            },
        },
        triggers = {},
        triggerType = "event",
        fieldValues = {},
        expression = "t[1]",
        expressionTemplate = "custom",
        conditionRules = {},
        load = { mode = "always" },
        update = {
            interval = 0.1,
            whileVisible = true,
        },
    }
    self.selectedDraftIndex = nil
    self.selectedOverlayIndex = nil
    self.selectedElementToken = "base"
    self.selectedConditionIndex = nil
end

local function GetCurrentDraft()
    if type(Lab.draft) ~= "table" then
        Lab:ResetDraft()
    end
    return Lab.draft
end

local function CurrentMonitorId(raw)
    local id = Trim(raw or GetCurrentDraft().id or DEFAULT_MONITOR_ID)
    if id == "" then id = DEFAULT_MONITOR_ID end
    if StartsWith(id, DEV_PREFIX) then return id end
    return DEV_PREFIX .. id
end

local function IsDevMonitorId(id)
    return StartsWith(id, DEV_PREFIX)
end

local function GetSelectedId()
    return Lab.selectedMonitorId
end

local function IsDraftSelected(id)
    return false
end

local function GetMonitorModeLabel(stateOrRow)
    if not stateOrRow then return "未选择" end
    if stateOrRow.dev == true or IsDevMonitorId(stateOrRow.id) then return "自定义" end
    return "已注册"
end

local function GetMonitorRunLabel(stateOrRow)
    if not stateOrRow then return "未选择" end
    if stateOrRow.active then return "激活" end
    if stateOrRow.running then return "运行" end
    if stateOrRow.loaded == true then return "已载入" end
    if stateOrRow.loadDiagnostic and stateOrRow.loadDiagnostic.ok == false then return "未加载" end
    if stateOrRow.loadDiagnostic and stateOrRow.loadDiagnostic.ok == true then return "载入通过" end
    if stateOrRow.requestedEnabled == false then return "已暂停" end
    return "待机"
end

local function GetMonitorDiagnosis(state)
    if not state then return "没有运行实例" end
    if state.running then return "运行中" end
    if state.requestedEnabled ~= true then return "未启用" end
    if state.loadDiagnostic and state.loadDiagnostic.summary then
        return state.loadDiagnostic.summary
    end
    return "未运行"
end

local function GetSelectedState()
    local monitor = Monitor()
    local selected = GetSelectedId()
    if not (selected and monitor and monitor.GetDebugState) then return nil end
    return monitor:GetDebugState(selected)
end

local function GetRuntimeState()
    local monitor = Monitor()
    if not (monitor and monitor.GetDebugState) then return nil end
    local selected = GetSelectedId()
    if not selected then return nil end
    return monitor:GetDebugState(selected)
end

local function GetSelectedInstance()
    local monitor = Monitor()
    local selected = GetSelectedId()
    if not (selected and monitor and monitor.Get) then return nil end
    return monitor:Get(selected)
end

local function IsEditableSelection()
    local selected = GetSelectedId()
    if not selected then return false end
    local state = GetSelectedState()
    return state and (state.dev == true or IsDevMonitorId(state.id)) or false
end

local function SafeDraftAppearance()
    local draft = GetCurrentDraft()
    if type(draft.appearance) ~= "table" then
        draft.appearance = {}
    end
    local appearance = draft.appearance
    appearance.type = appearance.type or "icon"
    if type(appearance.base) ~= "table" then appearance.base = {} end
    local fallbackSize = tonumber(appearance.base.size) or 64
    appearance.width = tonumber(appearance.width) or (appearance.type == "bar" and 180 or (appearance.type == "text" and 180 or fallbackSize))
    appearance.height = tonumber(appearance.height) or (appearance.type == "bar" and 24 or (appearance.type == "text" and 32 or fallbackSize))
    if type(appearance.point) ~= "table" then
        appearance.point = { point = "CENTER", x = 0, y = -160 }
    end
    if type(appearance.overlays) ~= "table" then appearance.overlays = {} end
    return appearance
end

local function MakeExpression(kind, count)
    count = tonumber(count) or #GetCurrentDraft().triggers
    if kind == "always" then return "true" end
    if kind == "never" then return "false" end
    if count <= 0 or kind == "first" then return "t[1]" end
    local parts = {}
    for index = 1, count do
        parts[#parts + 1] = "t[" .. index .. "]"
    end
    if kind == "all" then
        return table_concat(parts, " and ")
    end
    return table_concat(parts, " or ")
end

local function GetTriggerSchema(triggerType)
    local monitor = Monitor()
    return monitor and monitor.GetTriggerSchema and monitor:GetTriggerSchema(triggerType) or nil
end

local function GetSchemaOptions(includeFuture)
    local monitor = Monitor()
    local rows = monitor and monitor.ListTriggerSchemas and monitor:ListTriggerSchemas(includeFuture == true) or {}
    local options = {}
    for _, row in ipairs(rows) do
        if row.future ~= true and row.type ~= "playerAura" then
            options[#options + 1] = { text = row.label or row.type, value = row.type }
        end
    end
    if #options == 0 then
        options[1] = { text = "event", value = "event" }
    end
    return options
end

local function BuildUnitOptions(currentUnit)
    local options, seen = {}, {}
    for _, option in ipairs(UNIT_OPTIONS) do
        options[#options + 1] = option
        seen[option.value] = true
    end
    if type(currentUnit) == "string" and currentUnit ~= "" and not seen[currentUnit] then
        table_insert(options, 1, { text = currentUnit, value = currentUnit })
    end
    return options
end

local EVENT_PARAMETER_KEYS = {
    unit = true,
    spellID = true,
    spellId = true,
    matchBaseSpellID = true,
}

local function IsUnitEvent(eventName)
    return type(eventName) == "string" and string.sub(eventName, 1, 5) == "UNIT_"
end

local function GetEventSchema()
    return GetTriggerSchema("event") or {}
end

local function GetEventParameterFields(eventName, schema)
    schema = schema or GetEventSchema()
    local eventFields = type(schema.eventFields) == "table" and schema.eventFields or {}
    if type(eventName) == "string" and type(eventFields[eventName]) == "table" then
        return eventFields[eventName]
    end
    if IsUnitEvent(eventName) and type(eventFields.unitDefault) == "table" then
        return eventFields.unitDefault
    end
    return type(eventFields.default) == "table" and eventFields.default or {}
end

local function GetEventDefaultValue(schema, eventName, key)
    schema = schema or GetEventSchema()
    local defaults = type(schema.eventDefaults) == "table" and schema.eventDefaults[eventName] or nil
    if type(defaults) == "table" and defaults[key] ~= nil then
        return defaults[key]
    end
    for _, field in ipairs(schema.fields or {}) do
        if field.key == key then return field.default end
    end
    return nil
end

local function ApplyEventTriggerShape(trigger, eventName, previousEvent)
    if type(trigger) ~= "table" then return end
    local schema = GetEventSchema()
    eventName = eventName or trigger.event or "PLAYER_ENTERING_WORLD"
    trigger.event = eventName

    local allowed = { event = true, duration = true }
    local parameterFields = GetEventParameterFields(eventName, schema)
    for _, field in ipairs(parameterFields) do
        if field.key then allowed[field.key] = true end
    end
    for key in pairs(EVENT_PARAMETER_KEYS) do
        if not allowed[key] then trigger[key] = nil end
    end

    local nextDurationDefault = GetEventDefaultValue(schema, eventName, "duration")
    local previousDurationDefault = previousEvent and GetEventDefaultValue(schema, previousEvent, "duration") or nil
    if nextDurationDefault ~= nil and (trigger.duration == nil or trigger.duration == previousDurationDefault) then
        trigger.duration = nextDurationDefault
    end

    for _, field in ipairs(parameterFields) do
        if field.key and trigger[field.key] == nil and field.default ~= nil then
            trigger[field.key] = field.default
        end
    end
    local defaults = type(schema.eventDefaults) == "table" and schema.eventDefaults[eventName] or nil
    if type(defaults) == "table" then
        for key, value in pairs(defaults) do
            if key ~= "duration" and trigger[key] == nil then
                trigger[key] = value
            end
        end
    end
end

local function NormalizeDraftTriggerForEditor(trigger)
    if type(trigger) ~= "table" then return trigger end
    if trigger.type == "playerAura" then
        trigger.type = "unitAura"
        trigger.unit = trigger.unit or "player"
    end
    if trigger.type == "event" then
        trigger["events"] = nil
        trigger["units"] = nil
        ApplyEventTriggerShape(trigger, trigger.event)
    end
    return trigger
end

local function DefaultTriggerForType(triggerType)
    if triggerType == "playerAura" then triggerType = "unitAura" end
    local schema = GetTriggerSchema(triggerType)
    local trigger = { type = triggerType or "event" }
    if schema and type(schema.example) == "table" then
        trigger = CopyTable(schema.example)
        trigger.type = triggerType or trigger.type or "event"
    end
    NormalizeDraftTriggerForEditor(trigger)
    trigger.id = trigger.id or trigger.type or "event"
    if trigger.type == "derived" and trigger.template == nil then
        trigger.template = "alwaysInactive"
    end
    return trigger
end

local function AutoTriggerId(index)
    return "trigger" .. tostring(index or 1)
end

local function EnsureDraftTriggerIds(draft)
    if type(draft) ~= "table" or type(draft.triggers) ~= "table" then return end
    for index, trigger in ipairs(draft.triggers) do
        if type(trigger) == "table" then
            NormalizeDraftTriggerForEditor(trigger)
            trigger.id = AutoTriggerId(index)
            trigger.activation = nil
            trigger.keepArgs = nil
            trigger.sticky = nil
        end
    end
end

local function CopyDraftTriggerForDefinition(trigger, index)
    local copy = CopyTable(trigger)
    NormalizeDraftTriggerForEditor(copy)
    copy.id = AutoTriggerId(index)
    copy.activation = nil
    copy.keepArgs = nil
    copy.sticky = nil
    return copy
end

local function BuildCommonEventOptions(currentEvent)
    local options, seen = {}, {}
    for _, eventName in ipairs(COMMON_EVENT_NAMES) do
        options[#options + 1] = {
            text = CoreText("monitor.event." .. eventName, eventName),
            value = eventName,
        }
        seen[eventName] = true
    end
    if type(currentEvent) == "string" and currentEvent ~= "" and not seen[currentEvent] then
        table_insert(options, 1, { text = currentEvent, value = currentEvent })
    end
    return options
end

local function ApplyFieldValue(trigger, field, value)
    if not (trigger and field and field.key) then return end
    local key = field.key
    if field.type == "number" then
        value = tonumber(value)
    elseif field.type == "boolean" then
        value = value == true or value == "true" or value == "1"
    end
    if value == "" then value = nil end
    trigger[key] = value
end

local function NormalizeOverlay(overlay)
    overlay = type(overlay) == "table" and overlay or {}
    overlay.type = overlay.type or "text"
    if type(overlay.point) ~= "table" then
        overlay.point = { point = overlay.type == "bar" and "BOTTOM" or "CENTER", x = 0, y = 0 }
    end
    if overlay.type == "bar" then
        overlay.width = tonumber(overlay.width) or 120
        overlay.height = tonumber(overlay.height) or 5
        overlay.value = tonumber(overlay.value) or 0.5
        overlay.fillColor = ParseColorText(overlay.fillColor) or overlay.fillColor or { 0.25, 0.65, 1, 1 }
    else
        overlay.text = overlay.text or "文本"
        overlay.fontSize = overlay.fontSize or "font.size.sm"
        overlay.color = ParseColorText(overlay.color) or overlay.color
    end
    return overlay
end

local function FindOverlayIndexByToken(appearance, token)
    if type(appearance) ~= "table" or type(appearance.overlays) ~= "table" then return nil end
    for index, overlay in ipairs(appearance.overlays) do
        if overlay.id == token then return index, overlay end
    end
    return nil
end

local function EnsureOverlayId(appearance, overlay)
    if type(appearance) ~= "table" or type(overlay) ~= "table" then return nil end
    local used = {}
    if type(appearance.overlays) == "table" then
        for _, other in ipairs(appearance.overlays) do
            if other ~= overlay and type(other.id) == "string" and other.id ~= "" then
                used[other.id] = true
            end
        end
    end
    local current = Trim(overlay.id)
    if current ~= "" and not used[current] then
        overlay.id = current
        return current
    end

    local prefix = overlay.type == "bar" and "bar" or "text"
    local index = 1
    local candidate
    repeat
        candidate = prefix .. tostring(index)
        index = index + 1
    until not used[candidate]
    overlay.id = candidate
    return candidate
end

local function EnsureAppearanceLayerOrder(appearance)
    appearance = type(appearance) == "table" and appearance or {}
    appearance.overlays = type(appearance.overlays) == "table" and appearance.overlays or {}
    local valid, seen, order = { base = true }, {}, {}
    for _, overlay in ipairs(appearance.overlays) do
        NormalizeOverlay(overlay)
        valid[EnsureOverlayId(appearance, overlay)] = true
    end

    local existing = type(appearance.layerOrder) == "table" and appearance.layerOrder or nil
    if existing and #existing > 0 then
        for _, token in ipairs(existing) do
            if valid[token] and not seen[token] then
                order[#order + 1] = token
                seen[token] = true
            end
        end
        if not seen.base then
            table_insert(order, 1, "base")
            seen.base = true
        end
    else
        order[#order + 1] = "base"
        seen.base = true
    end

    for _, overlay in ipairs(appearance.overlays) do
        if overlay.id and not seen[overlay.id] then
            order[#order + 1] = overlay.id
            seen[overlay.id] = true
        end
    end
    appearance.layerOrder = order
    return order
end

local function GetSelectedElementToken(lab, appearance)
    local order = EnsureAppearanceLayerOrder(appearance)
    local token = lab.selectedElementToken
    if token == "base" or FindOverlayIndexByToken(appearance, token) then return token end
    if lab.selectedOverlayIndex and appearance.overlays[lab.selectedOverlayIndex] then
        token = appearance.overlays[lab.selectedOverlayIndex].id
    else
        token = order[#order] or "base"
    end
    lab.selectedElementToken = token
    if token == "base" then lab.selectedOverlayIndex = nil end
    return token
end

local function BuildLayerRows(appearance)
    local order = EnsureAppearanceLayerOrder(appearance)
    local rows = {}
    for position = #order, 1, -1 do
        local token = order[position]
        if token == "base" then
            rows[#rows + 1] = { token = token, label = "背景", kind = "base", layerIndex = position }
        else
            local overlayIndex, overlay = FindOverlayIndexByToken(appearance, token)
            if overlay then
                rows[#rows + 1] = {
                    token = token,
                    label = string_format("%d. %s", overlayIndex, overlay.type == "bar" and "进度条" or "文字"),
                    kind = overlay.type,
                    overlayIndex = overlayIndex,
                    layerIndex = position,
                }
            end
        end
    end
    return rows
end

local function FindLayerPosition(appearance, token)
    local order = EnsureAppearanceLayerOrder(appearance)
    for index, value in ipairs(order) do
        if value == token then return index, order end
    end
    return nil, order
end

local function RemoveLayerToken(appearance, token)
    local order = EnsureAppearanceLayerOrder(appearance)
    for index = #order, 1, -1 do
        if order[index] == token then table_remove(order, index) end
    end
end

local function MoveLayerToken(appearance, token, delta)
    local index, order = FindLayerPosition(appearance, token)
    if not index then return false end
    local nextIndex = index + delta
    if nextIndex < 1 or nextIndex > #order then return false end
    order[index], order[nextIndex] = order[nextIndex], order[index]
    return true
end

local function GetAppearanceSummary(definition)
    local appearance = definition and definition.appearance
    if type(appearance) ~= "table" then return "未声明，使用 Monitor 默认通用图示" end
    if appearance.presenter then return "自定义 presenter，只读" end
    local base = appearance.base or {}
    local kind = base.type or appearance.type or "icon"
    return string_format("%s %sx%s overlays=%s", tostring(kind), tostring(appearance.width or base.width or "-"), tostring(appearance.height or base.height or "-"), tostring(type(appearance.overlays) == "table" and #appearance.overlays or 0))
end

local function GetLoadSummaryFromDefinition(definition)
    local load = definition and (definition.load or definition.loadConditions)
    if load == nil then return "未声明，默认通过" end
    if load == true then return "true，总是通过" end
    if load == false then return "false，总是不加载" end
    if type(load) == "function" then return "function，只读诊断" end
    if type(load) == "table" then return "声明式 load table" end
    return tostring(load)
end

local function CopyTriggerForDraft(trigger)
    local copy = {
        type = trigger.type,
    }
    if trigger.unit then copy.unit = trigger.unit end
    if trigger.event then copy.event = trigger.event end
    if trigger.spellID then copy.spellID = trigger.spellID end
    if trigger.duration then copy.duration = trigger.duration end
    if trigger.icon then copy.icon = trigger.icon end
    if trigger.type == "derived" then
        copy.template = trigger.active and "alwaysActive" or "alwaysInactive"
    end
    return copy
end

local function NormalizeCopiedAppearance(definition)
    local appearance = definition and definition.appearance
    if type(appearance) ~= "table" or appearance.presenter then
        return CopyTable(GetCurrentDraft().appearance)
    end
    local copy = CopyTable(appearance)
    copy.type = copy.type or (copy.base and copy.base.type) or "icon"
    if type(copy.point) ~= "table" then copy.point = { point = "CENTER", x = 0, y = -160 } end
    if type(copy.base) ~= "table" then copy.base = { type = copy.type } end
    if copy.type == "icon" then
        local fallbackSize = tonumber(copy.base.size) or 64
        copy.width = tonumber(copy.width) or fallbackSize
        copy.height = tonumber(copy.height) or fallbackSize
        copy.base.icon = copy.base.icon or DEFAULT_ICON
        copy.base.textureFit = copy.base.textureFit or "cover"
        copy.base.shape = copy.base.shape or "square"
        copy.base.padding = tonumber(copy.base.padding) or 0
    end
    if copy.type == "icon" or copy.type == "bar" then
        copy.base.iconMode = copy.base.iconMode == "auto" and "auto" or "manual"
    end
    if type(copy.overlays) ~= "table" then copy.overlays = {} end
    EnsureAppearanceLayerOrder(copy)
    return copy
end

local function NormalizeCopiedLoad(definition)
    local load = definition and (definition.load or definition.loadConditions)
    if load == false then return { mode = "never" } end
    if type(load) == "table" then
        local copied = { mode = "table" }
        copied.retail = load.retail
        copied.mists = load.mists
        copied.wrath = load.wrath
        copied.class = load.class
        copied.specID = load.specID
        if type(load.classes) == "table" then copied.classesText = JoinCSV(load.classes) end
        if type(load.specIDs) == "table" then copied.specIDsText = JoinCSV(load.specIDs) end
        return copied
    end
    return { mode = "always" }
end

function Lab:CopyMonitorToDraft(state)
    if not state then return false end
    local monitor = Monitor()
    local instance = monitor and monitor.Get and monitor:Get(state.id)
    local definition = instance and instance.definition or {}
    local draft = GetCurrentDraft()

    draft.id = MakeUniqueDevRawId()
    draft.name = MakeUniqueMonitorName("复制：" .. GetMonitorNameFromDefinition(definition, state.id))
    draft.moduleId = "dev.monitor"
    draft.expression = state.expressionSource or "t[1]"
    draft.expressionTemplate = "custom"
    draft.triggers = {}
    for _, trigger in ipairs(state.triggers or {}) do
        draft.triggers[#draft.triggers + 1] = CopyTriggerForDraft(trigger)
    end
    EnsureDraftTriggerIds(draft)
    if #draft.triggers > 0 then
        self.selectedDraftIndex = 1
        draft.triggerType = draft.triggers[1].type or "event"
        draft.fieldValues = CopyTable(draft.triggers[1])
    else
        self.selectedDraftIndex = nil
    end
    draft.appearance = NormalizeCopiedAppearance(definition)
    draft.load = NormalizeCopiedLoad(definition)
    draft.conditionRules = CopyTable(definition.conditionRules or {})
    self.selectedOverlayIndex = nil
    self.selectedElementToken = "base"
    self.selectedConditionIndex = #draft.conditionRules > 0 and 1 or nil
    self.activeTab = "visual"
    local instance = self:SaveEditedMonitor(true, true)
    if instance then
        self:LoadInstanceToEditor(instance.id)
    end
    self:SetStatus("已复制为自定义监控。函数型内容保持诊断，不复制任意 Lua。", "success")
    return true
end

local function BuildLoadFromDraft(draft)
    local load = draft.load or {}
    if load.mode == "never" then return false end
    if load.mode ~= "table" then return true end
    local result = {}
    if load.retail ~= nil then result.retail = load.retail end
    if load.mists ~= nil then result.mists = load.mists end
    if load.wrath ~= nil then result.wrath = load.wrath end
    local class = Trim(load.class)
    if class ~= "" then result.class = class end
    local classes = SplitCSV(load.classesText)
    if #classes > 0 then result.classes = classes end
    local specID = tonumber(load.specID)
    if specID then result.specID = specID end
    local specIDsText = SplitCSV(load.specIDsText)
    if #specIDsText > 0 then
        result.specIDs = {}
        for _, value in ipairs(specIDsText) do
            local numberValue = tonumber(value)
            if numberValue then result.specIDs[#result.specIDs + 1] = numberValue end
        end
    end
    if next(result) == nil then return true end
    return result
end

local function BuildAppearanceFromDraft(draft)
    local appearance = CopyTable(draft.appearance or {})
    appearance.type = appearance.type or "icon"
    local copiedBase = type(appearance.base) == "table" and appearance.base or {}
    local fallbackSize = tonumber(copiedBase.size) or 64
    appearance.width = tonumber(appearance.width) or (appearance.type == "bar" and 180 or (appearance.type == "text" and 180 or fallbackSize))
    appearance.height = tonumber(appearance.height) or (appearance.type == "bar" and 24 or (appearance.type == "text" and 32 or fallbackSize))
    if type(appearance.point) ~= "table" then appearance.point = { point = "CENTER", x = 0, y = -160 } end
    appearance.point.x = tonumber(appearance.point.x) or 0
    appearance.point.y = tonumber(appearance.point.y) or -160
    appearance.strata = appearance.strata or "MEDIUM"
    appearance.mouse = appearance.mouse == true
    appearance.clampedToScreen = appearance.clampedToScreen ~= false

    local base = copiedBase
    base.type = appearance.type
    if appearance.type == "bar" then
        base.value = tonumber(base.value) or 0.5
        base.fillColor = ParseColorText(base.fillColor) or base.fillColor or { 0.25, 0.65, 1, 1 }
        base.icon = base.icon
    elseif appearance.type == "text" then
        base.text = base.text or draft.id or "监控"
        base.fontSize = base.fontSize or "font.size.lg"
        base.color = ParseColorText(base.color or base.textColor) or base.color
    else
        base.icon = base.icon or DEFAULT_ICON
        base.shape = base.shape or "square"
        base.padding = tonumber(base.padding) or 0
        base.textureFit = base.textureFit or "cover"
    end
    appearance.base = base

    local overlays = {}
    if type(appearance.overlays) == "table" then
        for _, overlay in ipairs(appearance.overlays) do
            overlays[#overlays + 1] = NormalizeOverlay(CopyTable(overlay))
        end
    end
    appearance.overlays = overlays
    EnsureAppearanceLayerOrder(appearance)
    return appearance
end

local function BuildConditionRulesFromDraft(draft)
    local rules = {}
    for _, rule in ipairs(draft.conditionRules or {}) do
        local target = rule.actionTarget or (rule.actions and rule.actions[1] and rule.actions[1].target)
        local value = rule.actionValue
        if value == nil and rule.actions and rule.actions[1] then value = rule.actions[1].value end
        if type(rule.source) == "string" and rule.source ~= "" and type(target) == "string" and target ~= "" and target ~= "glow.disabled" then
            rules[#rules + 1] = {
                id = Trim(rule.id or "") ~= "" and Trim(rule.id) or ("rule" .. tostring(#rules + 1)),
                enabled = rule.enabled ~= false,
                source = rule.source,
                operator = rule.operator or "truthy",
                value = rule.value,
                actions = {
                    {
                        target = target,
                        value = ParseRuleActionValue(target, value),
                    },
                },
            }
        end
    end
    return rules
end

function Lab:BuildDefinition()
    local draft = GetCurrentDraft()
    EnsureDraftTriggerIds(draft)
    local triggers = {}
    for index, trigger in ipairs(draft.triggers or {}) do
        triggers[#triggers + 1] = CopyDraftTriggerForDefinition(trigger, index)
    end
    if #triggers == 0 then
        triggers[1] = CopyDraftTriggerForDefinition(DefaultTriggerForType(draft.triggerType or "event"), 1)
    end
    return {
        id = draft.id or DEFAULT_MONITOR_ID,
        name = Trim(draft.name or "") ~= "" and Trim(draft.name) or (draft.id or DEFAULT_MONITOR_ID),
        displayName = Trim(draft.name or "") ~= "" and Trim(draft.name) or (draft.id or DEFAULT_MONITOR_ID),
        moduleId = "dev.monitor",
        enabled = true,
        load = BuildLoadFromDraft(draft),
        activation = {
            expression = Trim(draft.expression or "") ~= "" and Trim(draft.expression) or "t[1]",
            triggers = triggers,
        },
        update = {
            interval = tonumber(draft.update and draft.update.interval) or 0.1,
            whileVisible = draft.update and draft.update.whileVisible ~= false,
        },
        conditionRules = BuildConditionRulesFromDraft(draft),
        appearance = BuildAppearanceFromDraft(draft),
    }
end

function Lab:PauseMonitorsForEdit()
    if self.editSessionActive then return end
    local monitor = Monitor()
    if not (monitor and monitor.List and monitor.GetDebugState and monitor.SetEnabled) then return end
    self.editSessionActive = true
    self.pausedMonitors = {}
    self.resumeOnClose = {}
    for _, id in ipairs(monitor:List()) do
        local state = monitor:GetDebugState(id)
        local instance = monitor.Get and monitor:Get(id)
        if state and state.requestedEnabled == true then
            self.pausedMonitors[id] = true
            monitor:SetEnabled(id, false)
        end
        if instance and instance.Hide and state and (state.running == true or state.visible == true) then
            instance:Hide()
        end
    end
end

function Lab:SaveEditedMonitor(restoreOnClose, silent)
    local monitor = Monitor()
    if not (monitor and monitor.RegisterDevDefinition) then
        if not silent then self:SetStatus("RegisterDevDefinition 不可用。", "error") end
        return nil
    end
    if InCombat() then
        if not silent then self:SetStatus("战斗中不能保存或重建监控。", "warning") end
        return nil
    end
    local definition = self:BuildDefinition()
    definition.enabled = false
    local instance = monitor:RegisterDevDefinition(definition)
    if not instance then
        if not silent then self:SetStatus("监控更新失败。", "error") end
        return nil
    end
    self.selectedMonitorId = instance.id
    self.selectedListMonitorId = instance.id
    if restoreOnClose ~= false then
        self.resumeOnClose = self.resumeOnClose or {}
        self.resumeOnClose[instance.id] = true
    end
    self.editorDirty = false
    self.hasSavedEditedMonitor = true
    if not silent then
        self:SetStatus("监控已更新：" .. tostring(instance.definition.name or instance.id), "success")
    end
    return instance
end

function Lab:MarkChanged(updatePreview)
    if IsEditableSelection() then
        self:SaveEditedMonitor(true, true)
    else
        self.editorDirty = true
    end
    if updatePreview ~= false then
        self:UpdatePreview()
    end
end

function Lab:ResumeMonitorsAfterEdit()
    if not self.editSessionActive then
        self:CloseMonitorMenu()
        self:CloseMonitorPopup()
        self:DestroyPreview()
        return
    end
    if self.editorDirty and IsEditableSelection() then
        self:SaveEditedMonitor(true, true)
    end
    self:CloseMonitorMenu()
    self:CloseMonitorPopup()
    self:DestroyPreview()
    local monitor = Monitor()
    if monitor and monitor.SetEnabled then
        local restore = {}
        for id in pairs(self.pausedMonitors or {}) do restore[id] = true end
        for id in pairs(self.resumeOnClose or {}) do restore[id] = true end
        for id in pairs(restore) do
            monitor:SetEnabled(id, true)
        end
        if monitor.Refresh then monitor:Refresh(nil, "monitor-editor-close") end
    end
    self.editSessionActive = false
    self.editorDirty = false
    self.hasSavedEditedMonitor = false
    self.pausedMonitors = nil
    self.resumeOnClose = nil
end

function Lab:DestroyPreview()
    if self.CloseIconPicker then self:CloseIconPicker() end
    local preview = self.preview
    if preview and preview.frame then
        preview.frame:Hide()
        preview.frame:SetScript("OnDragStart", nil)
        preview.frame:SetScript("OnDragStop", nil)
        ClearFrame(preview.frame)
        preview.frame:SetParent(nil)
    end
    self.preview = nil
end

local function ApplyPreviewPoint(frame, appearance)
    local point = appearance.point or {}
    frame:ClearAllPoints()
    frame:SetPoint(point.point or "CENTER", UIParent, point.relativePoint or point.point or "CENTER", tonumber(point.x) or 0, tonumber(point.y) or 0)
end

local function UpdateDraftPointFromFrame(frame, appearance)
    if not (frame and appearance and UIParent and frame.GetCenter and UIParent.GetCenter) then return end
    local left, bottom = frame:GetCenter()
    local parentLeft, parentBottom = UIParent:GetCenter()
    if not (left and bottom and parentLeft and parentBottom) then return end
    appearance.point = appearance.point or { point = "CENTER" }
    appearance.point.point = "CENTER"
    appearance.point.x = math_floor((left - parentLeft) + 0.5)
    appearance.point.y = math_floor((bottom - parentBottom) + 0.5)
end

local function AttachPreviewDrag(lab, widget, root)
    if not (lab and widget and root and widget.SetScript and widget.RegisterForDrag) then return end
    if widget.EnableMouse then widget:EnableMouse(true) end
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", function()
        if root.StartMoving then root:StartMoving() end
    end)
    widget:SetScript("OnDragStop", function()
        if root.StopMovingOrSizing then root:StopMovingOrSizing() end
        UpdateDraftPointFromFrame(root, SafeDraftAppearance())
        lab:MarkChanged(false)
        lab:SetStatus("预览位置已更新。", "success")
        lab:Render()
    end)
end

local function CreatePreviewTextSlot(gui, parent, width, height, textValue, fontSize, colorKey, justifyH, colorValue)
    if not (gui and gui.CreateFrame and gui.CreateText and parent) then return nil end
    local slot = gui:CreateFrame(parent, {
        width = math_max(tonumber(width) or 120, 24),
        height = math_max(tonumber(height) or 24, 16),
        mouse = true,
    })
    local text = gui:CreateText(slot, tostring(textValue or ""), fontSize or "font.size.md", colorKey or "color.text.primary", justifyH or "CENTER")
    text:SetPoint("CENTER", slot, "CENTER", 0, 0)
    text:SetSize(math_max(tonumber(width) or 120, 24), math_max(tonumber(height) or 24, 16))
    ApplyTextColor(text, colorValue)
    slot.text = text
    slot.SetText = function(frame, value)
        if frame.text and frame.text.SetText then frame.text:SetText(tostring(value or "")) end
    end
    slot.SetTextColor = function(frame, r, g, b, a)
        if frame.text and frame.text.SetTextColor then frame.text:SetTextColor(r, g, b, a or 1) end
    end
    return slot
end

local function ApplyPreviewElementLayer(widget, rootFrame, rank)
    if not widget then return end
    if widget.SetFrameLevel and rootFrame and rootFrame.GetFrameLevel then
        widget:SetFrameLevel((rootFrame:GetFrameLevel() or 0) + rank)
    end
    if widget.SetDrawLayer then
        widget:SetDrawLayer("OVERLAY", math_min(rank, 7))
    end
    if widget.text and widget.text.SetDrawLayer then
        widget.text:SetDrawLayer("OVERLAY", math_min(rank, 7))
    end
end

local function ApplyPreviewLayerOrder(visual, appearance)
    if not (visual and appearance) then return end
    local order = EnsureAppearanceLayerOrder(appearance)
    local baseWidget = visual.icon or visual.bar or visual.text
    for rank, token in ipairs(order) do
        if token == "base" then
            ApplyPreviewElementLayer(baseWidget, visual.frame, rank)
        else
            local overlayIndex = FindOverlayIndexByToken(appearance, token)
            ApplyPreviewElementLayer(visual.overlays and visual.overlays[overlayIndex], visual.frame, rank)
        end
    end
end

function Lab:UpdatePreview()
    if not (self.frame and self.frame:IsShown() and UIParent) then
        self:DestroyPreview()
        return
    end
    if not GetSelectedId() then
        self:DestroyPreview()
        return
    end
    local gui = GUI2()
    if not (gui and gui.CreateFrame) then return end
    local draft = GetCurrentDraft()
    local appearance = BuildAppearanceFromDraft(draft)
    local base = appearance.base or {}
    local baseType = base.type or appearance.type or "icon"
    local width = tonumber(appearance.width or base.width) or (baseType == "bar" and 180 or 64)
    local height = tonumber(appearance.height or base.height) or (baseType == "bar" and 24 or 64)
    local previewStrata = "TOOLTIP"
    local visual = self.preview
    local frame = visual and visual.frame
    if frame then
        ClearFrame(frame)
        frame:SetSize(width, height)
        if frame.SetClampedToScreen then
            frame:SetClampedToScreen(appearance.clampedToScreen ~= false)
        end
    else
        frame = gui:CreateFrame(UIParent, {
            width = width,
            height = height,
            strata = previewStrata,
            clampedToScreen = appearance.clampedToScreen ~= false,
            mouse = true,
        })
    end
    frame:SetFrameStrata(previewStrata)
    if self.frame and self.frame.GetFrameLevel and frame.SetFrameLevel then
        frame:SetFrameLevel((self.frame:GetFrameLevel() or 0) + 20)
    end
    frame:SetMovable(true)
    AttachPreviewDrag(self, frame, frame)
    ApplyPreviewPoint(frame, appearance)

    visual = { frame = frame, overlays = {} }
    self.preview = visual
    if baseType == "bar" and gui.Data and gui.Data.CreateProgressBar then
        visual.bar = gui.Data:CreateProgressBar(frame, {
            width = width,
            height = height,
            value = tonumber(base.value) or 0.5,
            icon = base.icon,
            fillColor = base.fillColor,
        })
        visual.bar:SetPoint("CENTER", frame, "CENTER", 0, 0)
        AttachPreviewDrag(self, visual.bar, frame)
    elseif baseType == "text" and gui.CreateText then
        visual.text = CreatePreviewTextSlot(gui, frame, width, height, base.text or draft.id or "监控", base.fontSize or "font.size.lg", base.colorKey or "color.text.primary", base.justifyH or "CENTER", base.color or base.textColor)
        visual.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        AttachPreviewDrag(self, visual.text, frame)
    else
        visual.icon = CreateRectIcon(frame, width, height, base.icon or DEFAULT_ICON, base)
        if visual.icon then
            visual.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
            AttachPreviewDrag(self, visual.icon, frame)
        end
    end

    if type(appearance.overlays) == "table" then
        for _, overlayDef in ipairs(appearance.overlays) do
            local overlay
            if overlayDef.type == "bar" and gui.Data and gui.Data.CreateProgressBar then
                overlay = gui.Data:CreateProgressBar(frame, {
                    width = overlayDef.width or width,
                    height = overlayDef.height or 5,
                    value = tonumber(overlayDef.value) or 0.5,
                    fillColor = overlayDef.fillColor,
                })
            elseif gui.CreateText then
                overlay = CreatePreviewTextSlot(gui, frame, overlayDef.width or math_max((tonumber(width) or 64) * 4, 240), overlayDef.height or 28, overlayDef.text or "", overlayDef.fontSize or "font.size.md", overlayDef.colorKey or "color.text.primary", overlayDef.justifyH or "CENTER", overlayDef.color)
            end
            if overlay then
                local point = overlayDef.point or { point = "CENTER" }
                overlay:ClearAllPoints()
                overlay:SetPoint(point.point or "CENTER", frame, point.relativePoint or point.point or "CENTER", tonumber(point.x) or 0, tonumber(point.y) or 0)
                AttachPreviewDrag(self, overlay, frame)
                visual.overlays[#visual.overlays + 1] = overlay
            end
        end
    end
    ApplyPreviewLayerOrder(visual, appearance)
    frame:Show()
    self.preview = visual
end

function Lab:CloseIconPicker()
    if self.iconPicker and self.iconPicker.Close then
        self.iconPicker:Close()
    end
end

function Lab:ApplyIconPickerSelection()
    if self.iconPicker and self.iconPicker.ApplySelection then
        self.iconPicker:ApplySelection()
    end
end

function Lab:OpenIconPicker(targetPath)
    if not self.frame then return end
    local gui = GUI2()
    if not (gui and gui.Application and gui.Application.CreateIconPicker) then return end
    local appearance = SafeDraftAppearance()
    appearance.base = appearance.base or {}
    local base = appearance.base
    local currentValue = base.icon or DEFAULT_ICON
    self.iconPickerRecent = self.iconPickerRecent or {}
    if not self.iconPicker or self.iconPicker:GetParent() ~= self.frame then
        self.iconPicker = gui.Application:CreateIconPicker(self.frame, {
            title = "选择图标",
            recent = self.iconPickerRecent,
        })
    else
        self.iconPicker.recent = self.iconPickerRecent
    end
    self.iconPicker:Open({
        value = currentValue,
        title = "选择图标",
        modeHint = targetPath == "base.icon" and "图示图标" or nil,
        onApply = function(value)
            local draftAppearance = SafeDraftAppearance()
            draftAppearance.base = draftAppearance.base or {}
            draftAppearance.base.icon = Trim(value) ~= "" and value or DEFAULT_ICON
            self:MarkChanged(false)
            self:Render()
        end,
    })
end

function Lab:StartDraftMonitor()
    local monitor = Monitor()
    if not (monitor and monitor.RegisterDevDefinition) then
        self:SetStatus("RegisterDevDefinition 不可用。", "error")
        return false
    end
    if InCombat() then
        self:SetStatus("战斗中不能启动或重建监控。", "warning")
        return false
    end
    local definition = self:BuildDefinition()
    local instance = monitor:RegisterDevDefinition(definition)
    if instance then
        instance:SetEnabled(true)
        self.selectedMonitorId = instance.id
        self.selectedListMonitorId = instance.id
        self:SetStatus("已启动监控：" .. tostring(instance.id), "success")
        self:Render()
        return true
    end
    self:SetStatus("启动监控失败。", "error")
    self:Render()
    return false
end

function Lab:StopSelectedDevMonitor()
    local monitor = Monitor()
    local selected = GetSelectedId()
    if not IsDevMonitorId(selected) then
        self:SetStatus("只能停止自定义监控。", "warning")
        return false
    end
    if InCombat() then
        self:SetStatus("战斗中不能停止监控。", "warning")
        return false
    end
    if monitor and monitor.Unregister and monitor:Unregister(selected) then
        self.selectedMonitorId = nil
        self.selectedListMonitorId = nil
        self:EnsureSelection()
        self:SetStatus("监控已停止：" .. tostring(selected), "success")
        self:Render()
        return true
    end
    self:SetStatus("没有找到可停止的监控。", "warning")
    self:Render()
    return false
end

function Lab:RefreshSelectedMonitor()
    local monitor = Monitor()
    local selected = GetSelectedId()
    local ok = monitor and monitor.Refresh and monitor:Refresh(selected, "dev-console")
    self:SetStatus(ok and "实例已刷新。" or "刷新未执行：实例不存在或未运行。", ok and "success" or "warning")
    self:Render()
end

function Lab:InjectSelectedTrigger(index)
    local monitor = Monitor()
    local selected = GetSelectedId()
    if not IsDevMonitorId(selected) then
        self:SetStatus("只能注入自定义监控的触发器。", "warning")
        return
    end
    local draft = GetCurrentDraft()
    EnsureDraftTriggerIds(draft)
    local trigger = draft.triggers[index or self.selectedDraftIndex or 1]
    local triggerId = trigger and trigger.id or index or self.selectedDraftIndex or 1
    local ok, message = monitor and monitor.InjectTrigger and monitor:InjectTrigger(selected, triggerId, {
        active = true,
        data = {
            progress = 1,
            count = 3,
            applications = 3,
            remaining = tonumber(trigger and trigger.duration) or 5,
            spellID = trigger and trigger.spellID,
            event = trigger and trigger.event,
        },
    })
    self:SetStatus(ok and ("已注入触发器：" .. tostring(triggerId)) or ("注入失败：" .. tostring(message)), ok and "success" or "error")
    self:Render()
end

function Lab:Create()
    local gui = GUI2()
    if not (gui and gui.CreatePanel and gui.Form and UIParent) then
        Print("监控控制台：GUI2 不可用。")
        return nil
    end
    if self.frame then return self.frame end
    if InCombat() then
        Print("监控控制台：战斗中不能创建窗口。")
        return nil
    end

    local frame = gui:CreatePanel(UIParent, {
        name = WINDOW_NAME,
        width = 1180,
        height = 720,
        surface = "color.surface.window",
        border = "color.border.strong",
        shadow = true,
    })
    self.frame = frame
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        if self.CloseIconPicker then self:CloseIconPicker() end
        self:ResumeMonitorsAfterEdit()
    end)
    frame:Hide()
    table_insert(UISpecialFrames, WINDOW_NAME)

    local title = CreateText(frame, "YUI.Monitor", "font.size.title", "color.text.heading")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetSize(220, 30)

    local close = gui:CreateCloseButton(frame, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -18, -18)

    local search = CreateEdit(frame, self.searchText or "", 290, function(value)
        self.searchText = value
        self:Render()
    end)
    search:SetPoint("TOPLEFT", 22, -62)
    frame.search = search

    local tabBar = gui:CreateFrame(frame, { width = 540, height = 30 })
    tabBar:SetPoint("LEFT", search, "RIGHT", 10, 0)
    frame.tabBar = tabBar
    frame.tabButtons = {}
    local previous
    for _, tab in ipairs(TAB_ORDER) do
        local button = CreateButton(tabBar, tab.label, tab.width, function()
            self:SelectTab(tab.id)
        end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", 0, 0)
        end
        frame.tabButtons[tab.id] = button
        previous = button
    end

    local listPanel = CreatePanel(frame, { width = 270, height = 570, surface = "color.surface.sunken", border = "color.border.subtle" })
    listPanel:SetPoint("TOPLEFT", 22, -100)
    frame.listPanel = listPanel

    local content = CreatePanel(frame, { width = 840, height = 570, surface = "color.surface.sunken", border = "color.border.subtle" })
    content:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 12, 0)
    frame.content = content

    local actions = gui:CreateFrame(frame, { width = 1120, height = 30 })
    actions:SetPoint("BOTTOMLEFT", 22, 18)
    frame.actions = actions

    if not self.activeTab then self.activeTab = "visual" end
    return frame
end

function Lab:Open()
    local frame = self:Create()
    if not frame then return end
    self:PauseMonitorsForEdit()
    self:EnsureSelection()
    frame:Show()
    self:Render()
end

function Lab:Toggle()
    local frame = self:Create()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        self:Open()
    end
end

function Lab:Close(cleanup)
    if cleanup then self:ResumeMonitorsAfterEdit() end
    if self.frame then self.frame:Hide() end
end

function Lab:SelectTab(tabId)
    if tabId ~= self.activeTab and self.CloseIconPicker then self:CloseIconPicker() end
    self.activeTab = tabId or "visual"
    self:Render()
end

function Lab:Render()
    local frame = self.frame
    if not frame then return end
    if not self.activeTab then self.activeTab = "visual" end
    self:EnsureSelection()

    for id, button in pairs(frame.tabButtons or {}) do
        SetButtonSelected(button, id == self.activeTab)
    end
    ClearFrame(frame.listPanel)
    ClearFrame(frame.content)
    ClearFrame(frame.actions)
    self:RenderMonitorList(frame.listPanel)
    if self.activeTab == "triggers" then
        self:RenderTriggersPage(frame.content)
    elseif self.activeTab == "conditions" then
        self:RenderConditionsPage(frame.content)
    elseif self.activeTab == "load" then
        self:RenderLoadPage(frame.content)
    elseif self.activeTab == "logs" then
        self:RenderLogsPage(frame.content)
    else
        self.activeTab = "visual"
        self:RenderVisualPage(frame.content)
    end
    self:RenderActions(frame.actions)
    self:UpdatePreview()
end

function Lab:Refresh()
    if self.frame and self.frame:IsShown() then self:Render() end
end

function Lab:CleanupDevMonitors()
    local monitor = Monitor()
    if not (monitor and monitor.List and monitor.Unregister) then return end
    for _, id in ipairs(monitor:List()) do
        if StartsWith(id, DEV_PREFIX) then
            monitor:Unregister(id)
        end
    end
end

function Lab:CloseMonitorMenu()
    if self.monitorContextMenu then
        self.monitorContextMenu:Hide()
        ClearFrame(self.monitorContextMenu)
        self.monitorContextMenu:SetParent(nil)
        self.monitorContextMenu = nil
    end
end

function Lab:CloseMonitorPopup()
    if self.monitorPopup then
        self.monitorPopup:Hide()
        ClearFrame(self.monitorPopup)
        self.monitorPopup:SetParent(nil)
        self.monitorPopup = nil
    end
end

function Lab:GetMonitorRows()
    local monitor = Monitor()
    local rows = {}
    if monitor and monitor.ListDetailed then
        for _, row in ipairs(monitor:ListDetailed()) do
            rows[#rows + 1] = {
                id = row.id,
                name = GetMonitorName(row),
                status = GetMonitorRunLabel(row),
                mode = GetMonitorModeLabel(row),
                access = row.editable and "可编辑" or "已锁定",
                row = row,
            }
        end
    end
    table_sort(rows, function(a, b)
        if a.row.editable ~= b.row.editable then
            return a.row.editable == true
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

function Lab:SelectMonitor(id)
    self:CloseMonitorMenu()
    self:CloseMonitorPopup()
    if self:LoadInstanceToEditor(id) then
        self:Render()
    end
end

function Lab:OpenRenamePopup(id)
    local monitor = Monitor()
    local instance = monitor and monitor.Get and monitor:Get(id)
    if not (instance and instance.dev == true) then
        self:SetStatus("生产注册监控已锁定，不能更名。", "warning")
        self:Render()
        return
    end
    self:CloseMonitorMenu()
    self:CloseMonitorPopup()
    local gui = GUI2()
    if not (gui and self.frame) then return end
    local popup = CreatePanel(self.frame, { width = 360, height = 142, surface = "color.surface.popup", border = "color.border.default", shadow = true })
    popup:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    if popup.SetFrameLevel and self.frame.GetFrameLevel then
        popup:SetFrameLevel((self.frame:GetFrameLevel() or 0) + 90)
    end
    self.monitorPopup = popup
    CreateLine(popup, -14, "更名监控", "color.text.heading", 320)
    local edit = CreateEdit(popup, GetMonitorNameFromDefinition(instance.definition, id), 300, nil, false)
    edit:SetPoint("TOPLEFT", 24, -48)
    local function Confirm()
        local nextName = Trim(edit:GetText())
        local ok, message = ValidateMonitorName(nextName, id)
        if not ok then
            self:SetStatus(message, "warning")
            self:Render()
            return
        end
        self:LoadInstanceToEditor(id)
        local draft = GetCurrentDraft()
        draft.name = nextName
        self:SaveEditedMonitor(true, true)
        self:CloseMonitorPopup()
        self:SetStatus("已更名为：" .. nextName, "success")
        self:Render()
    end
    edit:SetScript("OnEnterPressed", function(box)
        Confirm()
        box:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        self:CloseMonitorPopup()
    end)
    local cancel = CreateButton(popup, "取消", 78, function()
        self:CloseMonitorPopup()
    end)
    cancel:SetPoint("BOTTOMRIGHT", -18, 16)
    local okButton = CreateButton(popup, "确认", 78, Confirm)
    okButton:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
end

function Lab:DeleteMonitor(id)
    local monitor = Monitor()
    local instance = monitor and monitor.Get and monitor:Get(id)
    if not (instance and instance.dev == true) then
        self:SetStatus("生产注册监控已锁定，不能删除。", "warning")
        self:Render()
        return
    end
    if InCombat() then
        self:SetStatus("战斗中不能删除监控。", "warning")
        self:Render()
        return
    end
    self:CloseMonitorMenu()
    self:CloseMonitorPopup()
    local rows = self:GetMonitorRows()
    local nextSelection
    for index, row in ipairs(rows) do
        if row.id == id then
            nextSelection = rows[index + 1] and rows[index + 1].id or rows[index - 1] and rows[index - 1].id
            break
        end
    end
    if monitor:Unregister(id) then
        self.resumeOnClose = self.resumeOnClose or {}
        self.resumeOnClose[id] = nil
        self.pausedMonitors = self.pausedMonitors or {}
        self.pausedMonitors[id] = nil
        self.selectedMonitorId = nil
        self.selectedListMonitorId = nil
        self:ResetDraft()
        self:SetStatus("已删除监控：" .. tostring(instance.definition.name or id), "success")
        if nextSelection and monitor.Get and monitor:Get(nextSelection) then
            self:LoadInstanceToEditor(nextSelection)
        else
            self:EnsureSelection()
        end
        self:Render()
    end
end

function Lab:OpenDeletePopup(id)
    local monitor = Monitor()
    local instance = monitor and monitor.Get and monitor:Get(id)
    if not (instance and instance.dev == true) then
        self:SetStatus("生产注册监控已锁定，不能删除。", "warning")
        self:Render()
        return
    end
    self:CloseMonitorMenu()
    self:CloseMonitorPopup()
    if not self.frame then return end
    local popup = CreatePanel(self.frame, { width = 360, height = 134, surface = "color.surface.popup", border = "color.border.default", shadow = true })
    popup:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    if popup.SetFrameLevel and self.frame.GetFrameLevel then
        popup:SetFrameLevel((self.frame:GetFrameLevel() or 0) + 90)
    end
    self.monitorPopup = popup
    CreateLine(popup, -14, "删除监控", "color.state.error", 320)
    CreateLine(popup, -44, "确认删除：" .. GetMonitorNameFromDefinition(instance.definition, id), "color.text.primary", 320)
    local cancel = CreateButton(popup, "取消", 78, function()
        self:CloseMonitorPopup()
    end)
    cancel:SetPoint("BOTTOMRIGHT", -18, 16)
    local okButton = CreateButton(popup, "删除", 78, function()
        self:DeleteMonitor(id)
    end)
    okButton:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
end

function Lab:OpenMonitorContextMenu(id, owner)
    local monitor = Monitor()
    local instance = monitor and monitor.Get and monitor:Get(id)
    local editable = instance and instance.dev == true
    local gui = GUI2()
    if not (gui and gui.Overlay and gui.Overlay.CreateContextMenu and self.frame) then return end
    self:CloseMonitorMenu()
    local menu = gui.Overlay:CreateContextMenu(self.frame, {
        width = 158,
        items = {
            { text = editable and "更名" or "更名（已锁定）", disabled = not editable, onClick = function() self:OpenRenamePopup(id) end },
            { text = editable and "删除" or "删除（已锁定）", disabled = not editable, danger = editable, onClick = function() self:OpenDeletePopup(id) end },
        },
    })
    if owner and menu.SetPoint then
        menu:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
    else
        menu:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    end
    if menu.SetFrameLevel and self.frame.GetFrameLevel then
        menu:SetFrameLevel((self.frame:GetFrameLevel() or 0) + 80)
    end
    self.monitorContextMenu = menu
end

function Lab:EnsureSelection()
    local selected = self.selectedMonitorId
    local monitor = Monitor()
    if selected and monitor and monitor.Get and monitor:Get(selected) then
        return selected
    end
    for _, row in ipairs(self:GetMonitorRows()) do
        self:LoadInstanceToEditor(row.id)
        return row.id
    end
    return nil
end

function Lab:RenderMonitorList(parent)
    local gui = GUI2()
    local y = -12
    CreateLine(parent, y, "监控", "color.text.heading", 240)
    y = y - 28

    local query = string_lower(Trim(self.searchText or ""))
    local rows = self:GetMonitorRows()
    local shown = 0
    local selectedListId = self.selectedListMonitorId
    for _, item in ipairs(rows) do
        local statusText = string_format("%s · %s · %s", item.mode, item.status, item.access)
        local haystack = string_lower(tostring(item.name) .. " " .. tostring(item.id) .. " " .. statusText)
        if query == "" or haystack:find(query, 1, true) then
            shown = shown + 1
            if shown <= 11 then
                local selected = item.id == selectedListId
                local row = CreatePanel(parent, {
                    width = 238,
                    height = 44,
                    surface = selected and "color.control.hover" or "color.surface.panel",
                    border = selected and "color.border.accent" or "color.border.subtle",
                })
                row:SetPoint("TOPLEFT", 14, y)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(frame)
                    if item.id ~= self.selectedListMonitorId then
                        gui:ApplyBackdrop(frame, "color.surface.raised")
                    end
                end)
                row:SetScript("OnLeave", function(frame)
                    if item.id ~= self.selectedListMonitorId then
                        gui:ApplyBackdrop(frame, "color.surface.panel")
                    end
                end)
                row:SetScript("OnMouseUp", function(frame, button)
                    if button == "RightButton" then
                        self:OpenMonitorContextMenu(item.id, frame)
                    else
                        self:SelectMonitor(item.id)
                    end
                end)
                local name = CreateText(row, ShortLabel(item.name, 28), "font.size.md", "color.text.heading")
                name:SetPoint("TOPLEFT", 10, -6)
                name:SetSize(210, 18)
                local status = CreateText(row, statusText, "font.size.xs", item.row.locked and "color.text.disabled" or "color.text.secondary")
                status:SetPoint("TOPLEFT", 10, -25)
                status:SetSize(220, 16)
                y = y - 50
            end
        end
    end
    if shown == 0 then
        CreateLine(parent, y, query == "" and "没有已注册监控。" or "没有匹配的监控。", "color.text.secondary", 240)
    end
end

function Lab:LoadInstanceToEditor(id)
    local monitor = Monitor()
    local instance = monitor and monitor.Get and monitor:Get(id)
    if not (instance and instance.definition) then return false end
    local definition = instance.definition
    local activation = definition.activation or {}
    local draft = GetCurrentDraft()
    local rawId = tostring(definition.id or id)
    if StartsWith(rawId, DEV_PREFIX) then
        rawId = string.sub(rawId, #DEV_PREFIX + 1)
    end
    draft.id = rawId
    draft.name = GetMonitorNameFromDefinition(definition, rawId)
    draft.expression = type(activation.expression) == "string" and activation.expression or "t[1]"
    draft.expressionTemplate = "custom"
    draft.triggers = CopyTable(activation.triggers or definition.triggers or {})
    EnsureDraftTriggerIds(draft)
    draft.appearance = NormalizeCopiedAppearance(definition)
    draft.load = NormalizeCopiedLoad(definition)
    draft.conditionRules = CopyTable(definition.conditionRules or {})
    self.selectedDraftIndex = #draft.triggers > 0 and 1 or nil
    self.selectedConditionIndex = #draft.conditionRules > 0 and 1 or nil
    if self.selectedDraftIndex then
        draft.triggerType = draft.triggers[1].type or "event"
        draft.fieldValues = CopyTable(draft.triggers[1])
    end
    self.selectedMonitorId = id
    self.selectedListMonitorId = id
    self.selectedOverlayIndex = nil
    self.selectedElementToken = "base"
    self.editorDirty = false
    self:SetStatus("已选择监控：" .. tostring(draft.name or id), "success")
    return true
end

function Lab:LoadDevInstanceToDraft(id)
    return self:LoadInstanceToEditor(id)
end

function Lab:RenderHeader(parent, title, subtitle)
    local y = -14
    CreateText(parent, title, "font.size.lg", "color.text.heading"):SetPoint("TOPLEFT", 14, y)
    y = y - 26
    if subtitle and subtitle ~= "" then
        CreateLine(parent, y, subtitle, "color.text.secondary", 670)
        y = y - 26
    end
    return self:RenderStatus(parent, y)
end

function Lab:RenderReadOnlyBanner(parent, y, text)
    CreateLine(parent, y, text or "当前监控使用自定义函数或 presenter，编辑器只能显示诊断。", "color.state.warning", 660)
    return y - 26
end

function Lab:RenderVisualPage(parent)
    local state = GetSelectedState()
    local editable = IsEditableSelection()
    local y = self:RenderHeader(parent, "图示", "编辑当前监控的基础图示和子元素；屏幕上会显示可拖动预览。")
    local draft = GetCurrentDraft()
    local appearance = SafeDraftAppearance()

    if not editable then
        y = self:RenderReadOnlyBanner(parent, y)
        local instance = GetSelectedInstance()
        CreateLine(parent, y, "外观：" .. GetAppearanceSummary(instance and instance.definition), "color.text.primary", 660)
        y = y - 24
        if state then
            CreateLine(parent, y, "状态：" .. GetMonitorModeLabel(state) .. " / " .. GetMonitorRunLabel(state) .. " / " .. GetMonitorDiagnosis(state), "color.text.secondary", 660)
        end
        return
    end

    appearance.base = appearance.base or {}
    local base = appearance.base

    CreateDropdownField(parent, 20, y, "基础类型", appearance.type or "icon", APPEARANCE_TYPES, 180, function(value)
        appearance.type = value
        appearance.base = appearance.base or {}
        appearance.base.type = value
        if value == "bar" then
            appearance.width = 180
            appearance.height = 24
            appearance.base.value = tonumber(appearance.base.value) or 0.5
            appearance.base.fillColor = appearance.base.fillColor or { 0.25, 0.65, 1, 1 }
            appearance.base.iconMode = appearance.base.iconMode or "auto"
        elseif value == "text" then
            appearance.width = 180
            appearance.height = 32
            appearance.base.text = appearance.base.text or draft.id or "监控"
            appearance.base.fontSize = appearance.base.fontSize or "font.size.lg"
            appearance.base.color = appearance.base.color or { 1, 1, 1, 1 }
        else
            appearance.width = 64
            appearance.height = 64
            appearance.base.iconMode = appearance.base.iconMode or "auto"
            appearance.base.icon = appearance.base.icon or DEFAULT_ICON
            appearance.base.padding = tonumber(appearance.base.padding) or 0
            appearance.base.shape = appearance.base.shape or "square"
            appearance.base.textureFit = appearance.base.textureFit or "cover"
        end
        self:MarkChanged(false)
        self:Render()
    end)
    y = y - 42

    local expanded
    if appearance.type == "bar" then
        y, expanded = CreateDividerHeader(parent, "visual.base.bar", y, "条", 800)
        if expanded then
            CreateEditField(parent, 20, y, "当前值", base.value or 0.5, 110, function(value)
                base.value = ClampNumber(value, base.value or 0.5)
                self:MarkChanged()
            end, true, "0-1 之间的测试值，用于预览条填充比例。", 88)
            CreateEditField(parent, 300, y, "颜色", FormatColorText(base.fillColor, "0.25,0.65,1,1"), 180, function(value)
                base.fillColor = value
                self:MarkChanged()
            end, false, "颜色格式：r,g,b,a，例如 0.25,0.65,1,1。", 88)
            y = y - 34
            base.iconMode = base.iconMode or "auto"
            CreateDropdownField(parent, 20, y, "图标模式", base.iconMode, ICON_MODE_OPTIONS, 120, function(value)
                base.iconMode = value == "manual" and "manual" or "auto"
                self:MarkChanged(false)
                self:Render()
            end, "自动：使用最新触发器图标；手动：固定使用下方图标。", 88)
            local modeHelp = CreateLine(parent, y - 2, base.iconMode == "auto" and "自动使用最新触发器图标。" or "固定显示手动图标。", "color.text.secondary", 260)
            if modeHelp and modeHelp.ClearAllPoints then
                modeHelp:ClearAllPoints()
                modeHelp:SetPoint("TOPLEFT", 300, y - 2)
            end
            y = y - 34
            local iconLabel = base.iconMode == "auto" and "备用图标" or "可选图标"
            local iconTooltip = base.iconMode == "auto" and "自动模式缺少触发器图标时使用。支持法术贴图 ID、贴图路径或 atlas:名称。" or "手动模式固定显示。支持法术贴图 ID、贴图路径或 atlas:名称。"
            CreateEditField(parent, 20, y, iconLabel, base.icon or "", 340, function(value)
                base.icon = Trim(value) ~= "" and value or nil
                self:MarkChanged()
            end, false, iconTooltip, 88)
            local pick = CreateButton(parent, "选择", 58, function()
                self:OpenIconPicker("base.icon")
            end)
            pick:SetPoint("TOPLEFT", 20 + 88 + 340 + 8, y)
            y = y - 38
        end
    elseif appearance.type == "text" then
        y, expanded = CreateDividerHeader(parent, "visual.base.text", y, "文字", 800)
        if expanded then
            CreateEditField(parent, 20, y, "文本", base.text or draft.id or "监控", 320, function(value)
                base.text = value
                self:MarkChanged()
            end, false, "预览和通用 presenter 显示的文字。", 88)
            y = y - 34
            CreateDropdownField(parent, 20, y, "字体", base.fontSize or "font.size.lg", TEXT_FONT_SIZE_OPTIONS, 160, function(value)
                base.fontSize = value
                self:MarkChanged(false)
                self:Render()
            end, "使用 GUI2 字体 token。", 88)
            CreateEditField(parent, 300, y, "颜色", FormatColorText(base.color or base.textColor, "1,1,1,1"), 180, function(value)
                base.color = value
                self:MarkChanged()
            end, false, "颜色格式：r,g,b,a，例如 1,1,1,1。", 88)
            y = y - 38
        end
    else
        y, expanded = CreateDividerHeader(parent, "visual.base.icon", y, "图标", 800)
        if expanded then
            base.iconMode = base.iconMode or "auto"
            CreateDropdownField(parent, 20, y, "图标模式", base.iconMode, ICON_MODE_OPTIONS, 120, function(value)
                base.iconMode = value == "manual" and "manual" or "auto"
                self:MarkChanged(false)
                self:Render()
            end, "自动：使用最新触发器图标；手动：固定使用下方图标。", 88)
            local modeHelp = CreateLine(parent, y - 2, base.iconMode == "auto" and "自动使用最新触发器图标；下方为备用图标。" or "固定显示手动图标。", "color.text.secondary", 340)
            if modeHelp and modeHelp.ClearAllPoints then
                modeHelp:ClearAllPoints()
                modeHelp:SetPoint("TOPLEFT", 300, y - 2)
            end
            y = y - 34
            local iconLabel = base.iconMode == "auto" and "备用图标" or "图标"
            local iconTooltip = base.iconMode == "auto" and "自动模式缺少触发器图标时使用。支持法术贴图 ID、贴图路径或 atlas:名称。" or "手动模式固定显示。支持法术贴图 ID、贴图路径或 atlas:名称。"
            CreateEditField(parent, 20, y, iconLabel, base.icon or DEFAULT_ICON, 340, function(value)
                base.icon = Trim(value) ~= "" and value or DEFAULT_ICON
                self:MarkChanged()
            end, false, iconTooltip, 88)
            local pick = CreateButton(parent, "选择", 58, function()
                self:OpenIconPicker("base.icon")
            end)
            pick:SetPoint("TOPLEFT", 20 + 88 + 340 + 8, y)
            y = y - 34
            CreateEditField(parent, 20, y, "内边距", base.padding or 0, 110, function(value)
                base.padding = ClampNumber(value, base.padding or 0)
                self:MarkChanged()
            end, true, "图标纹理距离外框的像素。", 88)
            CreateDropdownField(parent, 300, y, "形状", base.shape or "square", ICON_SHAPE_OPTIONS, 160, function(value)
                base.shape = value
                self:MarkChanged(false)
                self:Render()
            end, "只影响外框形状；图标默认按裁切填满。", 88)
            base.textureFit = base.textureFit or "cover"
            y = y - 38
        end
    end

    y, expanded = CreateDividerHeader(parent, "visual.position", y, "位置和尺寸", 800)
    if expanded then
        CreateEditField(parent, 20, y, "宽度", appearance.width, 100, function(value)
            appearance.width = ClampNumber(value, appearance.width)
            self:MarkChanged()
        end, true, "监控主框体宽度；图标支持宽高不同。", 88)
        CreateEditField(parent, 300, y, "高度", appearance.height, 100, function(value)
            appearance.height = ClampNumber(value, appearance.height)
            self:MarkChanged()
        end, true, "监控主框体高度；图标会按比例裁切填满，不拉伸。", 88)
        y = y - 34
        CreateEditField(parent, 20, y, "X 偏移", appearance.point.x or 0, 100, function(value) appearance.point.x = ClampNumber(value, appearance.point.x or 0); self:MarkChanged() end, true, "相对屏幕中心的 X 偏移；拖动预览会自动回写。", 88)
        CreateEditField(parent, 300, y, "Y 偏移", appearance.point.y or -160, 100, function(value) appearance.point.y = ClampNumber(value, appearance.point.y or -160); self:MarkChanged() end, true, "相对屏幕中心的 Y 偏移；拖动预览会自动回写。", 88)
        y = y - 34
        CreateDropdownField(parent, 20, y, "层级", appearance.strata or "MEDIUM", STRATA_OPTIONS, 170, function(value) appearance.strata = value; self:MarkChanged() end, "WoW frame strata。", 88)
        CreateCheckboxField(parent, 300, y, "启用鼠标", appearance.mouse == true, function(value) appearance.mouse = value; self:MarkChanged() end)
        CreateCheckboxField(parent, 520, y, "贴屏限制", appearance.clampedToScreen ~= false, function(value) appearance.clampedToScreen = value; self:MarkChanged() end)
        y = y - 42
    end

    y, expanded = CreateDividerHeader(parent, "visual.overlays", y, "子元素", 800)
    if expanded then
        y = self:RenderOverlayEditor(parent, y)
    end
end

function Lab:RenderOverlayEditor(parent, y)
    local appearance = SafeDraftAppearance()
    appearance.overlays = type(appearance.overlays) == "table" and appearance.overlays or {}
    local overlays = appearance.overlays
    local selectedToken = GetSelectedElementToken(self, appearance)
    local selectedOverlayIndex, selected = FindOverlayIndexByToken(appearance, selectedToken)
    self.selectedOverlayIndex = selectedOverlayIndex

    local panel = CreatePanel(parent, { width = 800, height = 164, surface = "color.surface.window", border = "color.border.subtle" })
    panel:SetPoint("TOPLEFT", 20, y)
    local list = CreatePanel(panel, { width = 285, height = 104, surface = "color.surface.sunken", border = "color.border.subtle" })
    list:SetPoint("TOPLEFT", 14, -12)
    local detail = CreatePanel(panel, { width = 470, height = 104, surface = "color.surface.sunken", border = "color.border.subtle" })
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)

    local rows = BuildLayerRows(appearance)
    local rowY = -8
    for index, row in ipairs(rows) do
        if index > 4 then
            CreateLine(list, rowY, "还有 " .. tostring(#rows - 4) .. " 个层级未显示。", "color.text.secondary", 240)
            break
        end
        local button = CreateButton(list, row.label, 245, function()
            self.selectedElementToken = row.token
            self.selectedOverlayIndex = row.overlayIndex
            self:Render()
        end)
        button:SetPoint("TOPLEFT", 14, rowY)
        SetButtonSelected(button, selectedToken == row.token)
        rowY = rowY - 24
    end

    if selectedToken == "base" then
        CreateLine(detail, -14, "背景代表上方基础元素。", "color.text.primary", 420)
        CreateLine(detail, -42, "背景的类型、图标、尺寸、位置在上方编辑；这里仅调整它和子元素的前后层级。", "color.text.secondary", 430)
    elseif selected then
        selected = NormalizeOverlay(selected)
        local dy = -12
        if selected.type == "bar" then
            CreateEditField(detail, 14, dy, "值", selected.value, 80, function(value) selected.value = ClampNumber(value, selected.value or 0.5); self:MarkChanged() end, true, "0-1 之间的测试值。", 56)
            CreateEditField(detail, 205, dy, "颜色", FormatColorText(selected.fillColor, "0.25,0.65,1,1"), 150, function(value) selected.fillColor = value; self:MarkChanged() end, false, "颜色格式：r,g,b,a。", 56)
            dy = dy - 32
            CreateEditField(detail, 14, dy, "宽度", selected.width, 80, function(value) selected.width = ClampNumber(value, selected.width or 120); self:MarkChanged() end, true, nil, 56)
            CreateEditField(detail, 205, dy, "高度", selected.height, 80, function(value) selected.height = ClampNumber(value, selected.height or 5); self:MarkChanged() end, true, nil, 56)
            dy = dy - 32
            CreateEditField(detail, 14, dy, "X", selected.point.x or 0, 80, function(value) selected.point.x = ClampNumber(value, selected.point.x or 0); self:MarkChanged() end, true, nil, 56)
            CreateEditField(detail, 205, dy, "Y", selected.point.y or 0, 80, function(value) selected.point.y = ClampNumber(value, selected.point.y or 0); self:MarkChanged() end, true, nil, 56)
        else
            CreateEditField(detail, 14, dy, "文本", selected.text, 290, function(value) selected.text = value; self:MarkChanged() end, false, nil, 56)
            dy = dy - 32
            CreateDropdownField(detail, 14, dy, "字体", selected.fontSize or "font.size.sm", TEXT_FONT_SIZE_OPTIONS, 110, function(value) selected.fontSize = value; self:MarkChanged(false); self:Render() end, nil, 56)
            CreateEditField(detail, 205, dy, "颜色", FormatColorText(selected.color, ""), 150, function(value) selected.color = value; self:MarkChanged() end, false, "可选：r,g,b,a。", 56)
            dy = dy - 32
            CreateEditField(detail, 14, dy, "X", selected.point.x or 0, 80, function(value) selected.point.x = ClampNumber(value, selected.point.x or 0); self:MarkChanged() end, true, nil, 56)
            CreateEditField(detail, 205, dy, "Y", selected.point.y or 0, 80, function(value) selected.point.y = ClampNumber(value, selected.point.y or 0); self:MarkChanged() end, true, nil, 56)
        end
    else
        CreateLine(detail, -14, "选择左侧元素进行编辑。", "color.text.secondary", 420)
    end

    local addText = CreateButton(panel, "添加文本", 92, function()
        local overlay = NormalizeOverlay({ type = "text", text = "文本", point = { point = "CENTER", x = 0, y = 0 } })
        overlays[#overlays + 1] = overlay
        EnsureOverlayId(appearance, overlay)
        EnsureAppearanceLayerOrder(appearance)
        self.selectedOverlayIndex = #overlays
        self.selectedElementToken = overlay.id
        self:MarkChanged(false)
        self:Render()
    end)
    addText:SetPoint("BOTTOMLEFT", 14, 10)
    local addBar = CreateButton(panel, "添加进度条", 104, function()
        local overlay = NormalizeOverlay({ type = "bar", point = { point = "BOTTOM", x = 0, y = 0 } })
        overlays[#overlays + 1] = overlay
        EnsureOverlayId(appearance, overlay)
        EnsureAppearanceLayerOrder(appearance)
        self.selectedOverlayIndex = #overlays
        self.selectedElementToken = overlay.id
        self:MarkChanged(false)
        self:Render()
    end)
    addBar:SetPoint("LEFT", addText, "RIGHT", 8, 0)
    local layerIndex, order = FindLayerPosition(appearance, selectedToken)
    local up = CreateActionButton(panel, "上移", 60, function()
        if MoveLayerToken(appearance, selectedToken, 1) then
            self:MarkChanged(false)
            self:Render()
        end
    end, not (layerIndex and layerIndex < #order), "列表越上越靠前；上移会让元素盖在更多内容上。")
    up:SetPoint("LEFT", addBar, "RIGHT", 8, 0)
    local down = CreateActionButton(panel, "下移", 60, function()
        if MoveLayerToken(appearance, selectedToken, -1) then
            self:MarkChanged(false)
            self:Render()
        end
    end, not (layerIndex and layerIndex > 1), "列表越下越靠后；下移会让元素更接近背景。")
    down:SetPoint("LEFT", up, "RIGHT", 8, 0)
    local remove = CreateActionButton(panel, "删除", 76, function()
        if selectedOverlayIndex and overlays[selectedOverlayIndex] then
            RemoveLayerToken(appearance, selectedToken)
            table_remove(overlays, selectedOverlayIndex)
            EnsureAppearanceLayerOrder(appearance)
            self.selectedOverlayIndex = nil
            self.selectedElementToken = "base"
        end
        self:MarkChanged(false)
        self:Render()
    end, selectedToken == "base" or not selectedOverlayIndex, "背景不可删除；文本和进度条可删除。")
    remove:SetPoint("LEFT", down, "RIGHT", 8, 0)
    return y - 176
end

function Lab:RenderTriggerCombinationPanel(parent, y, editable, state)
    local panel = CreatePanel(parent, { width = 800, height = 108, surface = "color.surface.window", border = "color.border.subtle" })
    panel:SetPoint("TOPLEFT", 20, y)
    CreateLine(panel, -12, "触发器组合条件", "color.text.heading", 760)
    if not editable then
        CreateLine(panel, -42, "表达式类型：" .. tostring(state and state.expressionKind or "-"), "color.text.primary", 760)
        CreateLine(panel, -66, "表达式：" .. tostring(state and state.expressionSource or state and state.expressionKind or "-"), "color.text.secondary", 760)
        if state and state.expressionError then
            CreateLine(panel, -90, "解析错误：" .. tostring(state.expressionError), "color.state.error", 760)
        end
        return y - 122
    end

    local draft = GetCurrentDraft()
    CreateDropdownField(panel, 14, -42, "组合方式", draft.expressionTemplate or "custom", EXPRESSION_TEMPLATE_OPTIONS, 190, function(value)
        draft.expressionTemplate = value
        if value ~= "custom" then
            draft.expression = MakeExpression(value, #draft.triggers)
        end
        self:MarkChanged(false)
        self:Render()
    end)
    CreateEditField(panel, 360, -42, "表达式", draft.expression or "t[1]", 300, function(value)
        draft.expression = value
        draft.expressionTemplate = "custom"
        self:MarkChanged()
    end)
    CreateLine(panel, -74, "语法：t[1]、t[2]、and/or/not、括号、true/false；也支持 & | ! 简写。", "color.text.secondary", 760)
    if state and state.expressionError then
        CreateLine(panel, -96, "解析错误：" .. tostring(state.expressionError), "color.state.error", 760)
    end
    return y - 122
end

function Lab:RenderTriggersPage(parent)
    local editable = IsEditableSelection()
    local state = GetRuntimeState()
    local y = self:RenderHeader(parent, "触发器", "配置触发器组合条件和多个触发器。不同类型会显示不同参数。")
    y = self:RenderTriggerCombinationPanel(parent, y, editable, state)
    if not editable then
        y = self:RenderReadOnlyBanner(parent, y)
        self:RenderReadOnlyTriggers(parent, y)
        return
    end

    local draft = GetCurrentDraft()
    if #draft.triggers == 0 then
        draft.triggers[1] = DefaultTriggerForType(draft.triggerType or "event")
        self.selectedDraftIndex = 1
    end
    local listPanel = CreatePanel(parent, { width = 340, height = 386, surface = "color.surface.window", border = "color.border.subtle" })
    listPanel:SetPoint("TOPLEFT", 20, y)
    local detailPanel = CreatePanel(parent, { width = 448, height = 386, surface = "color.surface.window", border = "color.border.subtle" })
    detailPanel:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 12, 0)
    self:RenderDraftTriggerList(listPanel)
    self:RenderTriggerFieldForm(detailPanel)
end

function Lab:RenderReadOnlyTriggers(parent, y)
    local state = GetSelectedState()
    if not state then
        CreateLine(parent, y, "没有选中的运行实例。", "color.text.secondary", 660)
        return
    end
    for index, trigger in ipairs(state.triggers or {}) do
        if index > 12 then break end
        local text = string_format("触发器 %d · %s 激活=%s 变化=%s 技能=%s 单位=%s",
            index,
            tostring(TRIGGER_TYPE_LABELS[trigger.type] or trigger.type),
            FormatBool(trigger.active),
            FormatBool(trigger.changed),
            tostring(trigger.spellID or "-"),
            tostring(trigger.unit or "-")
        )
        CreateLine(parent, y, text, "color.text.primary", 660)
        y = y - 24
    end
end

function Lab:RenderDraftTriggerList(parent)
    local draft = GetCurrentDraft()
    EnsureDraftTriggerIds(draft)
    local y = -12
    CreateLine(parent, y, "触发器列表", "color.text.heading", 300)
    y = y - 30
    for index, trigger in ipairs(draft.triggers) do
        if index > 8 then break end
        local label = string_format("触发器 %d · %s", index, tostring(TRIGGER_TYPE_LABELS[trigger.type] or trigger.type or "event"))
        local button = CreateButton(parent, label, 300, function()
            self.selectedDraftIndex = index
            self:Render()
        end)
        button:SetPoint("TOPLEFT", 14, y)
        SetButtonSelected(button, self.selectedDraftIndex == index)
        y = y - 32
    end

    local add = CreateButton(parent, "添加", 60, function()
        local trigger = DefaultTriggerForType(draft.triggerType or "event")
        table_insert(draft.triggers, trigger)
        EnsureDraftTriggerIds(draft)
        self.selectedDraftIndex = #draft.triggers
        self:MarkChanged(false)
        self:Render()
    end)
    add:SetPoint("BOTTOMLEFT", 14, 14)
    local duplicate = CreateActionButton(parent, "复制", 60, function()
        table_insert(draft.triggers, CopyTable(draft.triggers[self.selectedDraftIndex]))
        EnsureDraftTriggerIds(draft)
        self.selectedDraftIndex = #draft.triggers
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedDraftIndex and draft.triggers[self.selectedDraftIndex]))
    duplicate:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local remove = CreateActionButton(parent, "删除", 60, function()
        table_remove(draft.triggers, self.selectedDraftIndex)
        EnsureDraftTriggerIds(draft)
        if #draft.triggers == 0 then
            self.selectedDraftIndex = nil
        elseif self.selectedDraftIndex > #draft.triggers then
            self.selectedDraftIndex = #draft.triggers
        end
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedDraftIndex and draft.triggers[self.selectedDraftIndex]))
    remove:SetPoint("LEFT", duplicate, "RIGHT", 6, 0)
    local up = CreateActionButton(parent, "上移", 50, function()
        local index = self.selectedDraftIndex
        draft.triggers[index], draft.triggers[index - 1] = draft.triggers[index - 1], draft.triggers[index]
        EnsureDraftTriggerIds(draft)
        self.selectedDraftIndex = index - 1
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedDraftIndex and self.selectedDraftIndex > 1))
    up:SetPoint("LEFT", remove, "RIGHT", 6, 0)
    local down = CreateActionButton(parent, "下移", 50, function()
        local index = self.selectedDraftIndex
        draft.triggers[index], draft.triggers[index + 1] = draft.triggers[index + 1], draft.triggers[index]
        EnsureDraftTriggerIds(draft)
        self.selectedDraftIndex = index + 1
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedDraftIndex and self.selectedDraftIndex < #draft.triggers))
    down:SetPoint("LEFT", up, "RIGHT", 6, 0)
end

function Lab:RenderTriggerFieldForm(parent)
    local draft = GetCurrentDraft()
    EnsureDraftTriggerIds(draft)
    local index = self.selectedDraftIndex or 1
    local trigger = draft.triggers[index]
    if not trigger then
        CreateLine(parent, -12, "请选择触发器。", "color.text.secondary", 340)
        return
    end
    local y = -12
    CreateLine(parent, y, "触发器 " .. tostring(index), "color.text.heading", 340)
    y = y - 32
    CreateDropdownField(parent, 14, y, "类型", trigger.type or "event", GetSchemaOptions(false), FIELD_CONTROL_WIDTH, function(value)
        local nextTrigger = DefaultTriggerForType(value)
        draft.triggers[index] = nextTrigger
        EnsureDraftTriggerIds(draft)
        draft.triggerType = value
        self:MarkChanged(false)
        self:Render()
    end, TRIGGER_HELP[trigger.type or "event"] or "当前触发器类型。")
    y = y - 36

    local schema = GetTriggerSchema(trigger.type or "event")
    local function RenderField(field)
        if field.key ~= "type" and field.key ~= "icon" then
            local label = FIELD_LABELS[field.key] or field.key
            local value = trigger[field.key]
            if value == nil then value = field.default end
            if field.readOnly == true then
                CreateFieldLabel(parent, 14, y, label)
                local valueText = CreateText(parent, tostring(value or "-"), "font.size.sm", "color.text.primary")
                valueText:SetPoint("TOPLEFT", 14 + FIELD_LABEL_WIDTH, y - 2)
                valueText:SetSize(FIELD_CONTROL_WIDTH, 20)
            elseif field.key == "spellID" or field.key == "spellId" then
                CreateSpellIDField(parent, 14, y, label, value, FIELD_CONTROL_WIDTH, function(nextValue)
                    ApplyFieldValue(trigger, field, nextValue)
                    self:MarkChanged()
                end, FIELD_HELP[field.key])
            elseif field.type == "boolean" then
                CreateCheckboxField(parent, 14, y, label, value == true, function(nextValue)
                    trigger[field.key] = nextValue
                    self:MarkChanged()
                end, FIELD_HELP[field.key])
            elseif field.type == "enum" and type(field.options) == "table" then
                local options = {}
                for _, optionValue in ipairs(field.options) do
                    options[#options + 1] = { text = tostring(optionValue), value = optionValue }
                end
                CreateDropdownField(parent, 14, y, label, value, options, FIELD_CONTROL_WIDTH, function(nextValue)
                    ApplyFieldValue(trigger, field, nextValue)
                    self:MarkChanged(false)
                    self:Render()
                end, FIELD_HELP[field.key])
            elseif field.type == "unit" then
                CreateDropdownField(parent, 14, y, label, value or "player", BuildUnitOptions(value), FIELD_CONTROL_WIDTH, function(nextValue)
                    ApplyFieldValue(trigger, field, nextValue)
                    self:MarkChanged()
                end, FIELD_HELP[field.key])
            elseif field.type == "event" then
                CreateDropdownField(parent, 14, y, label, value or "PLAYER_ENTERING_WORLD", BuildCommonEventOptions(value), FIELD_CONTROL_WIDTH, function(nextValue)
                    if trigger.type == "event" then
                        ApplyEventTriggerShape(trigger, nextValue, trigger.event)
                        self:MarkChanged(false)
                        self:Render()
                    else
                        ApplyFieldValue(trigger, field, nextValue)
                        self:MarkChanged()
                    end
                end, FIELD_HELP[field.key])
            else
                CreateEditField(parent, 14, y, label, value, FIELD_CONTROL_WIDTH, function(nextValue)
                    ApplyFieldValue(trigger, field, nextValue)
                    self:MarkChanged()
                end, field.type == "number", FIELD_HELP[field.key])
            end
            y = y - 32
        end
    end

    if trigger.type == "event" then
        ApplyEventTriggerShape(trigger, trigger.event)
        RenderField({ key = "event", type = "event", default = "PLAYER_ENTERING_WORLD" })
        for _, field in ipairs(GetEventParameterFields(trigger.event, schema)) do
            RenderField(field)
        end
        RenderField({ key = "duration", type = "number", default = GetEventDefaultValue(schema, trigger.event, "duration") or 0.25 })
    else
        for _, field in ipairs(schema and schema.fields or {}) do
            RenderField(field)
        end
    end
end

local function GetRuleFirstAction(rule)
    if type(rule) ~= "table" then return nil end
    if type(rule.actions) == "table" and rule.actions[1] then return rule.actions[1] end
    if rule.actionTarget then
        return { target = rule.actionTarget, value = rule.actionValue }
    end
    return nil
end

local function NormalizeConditionRule(rule, index)
    rule = type(rule) == "table" and rule or {}
    local action = GetRuleFirstAction(rule)
    rule.id = Trim(rule.id or "") ~= "" and Trim(rule.id) or ("rule" .. tostring(index or 1))
    rule.enabled = rule.enabled ~= false
    rule.source = rule.source or "t[1].active"
    rule.operator = rule.operator or "truthy"
    rule.value = rule.value
    rule.actionTarget = rule.actionTarget or (action and action.target) or "base.text"
    rule.actionValue = rule.actionValue
    if rule.actionValue == nil and action then rule.actionValue = action.value end
    if rule.actionValue == nil then rule.actionValue = "命中" end
    return rule
end

local function BuildConditionSourceOptions(draft, state)
    local options = {
        { text = "上下文：已激活", value = "context.active" },
        { text = "上下文：运行中", value = "context.running" },
        { text = "上下文：已载入", value = "context.loaded" },
        { text = "上下文：可见", value = "context.visible" },
        { text = "上下文：进度", value = "context.progress" },
    }
    local source = draft and draft.triggers or {}
    if #source == 0 and state then source = state.triggers or {} end
    for index, trigger in ipairs(source) do
        local prefix = "触发器 " .. tostring(index) .. "：" .. tostring(TRIGGER_TYPE_LABELS[trigger.type] or trigger.type or "-")
        options[#options + 1] = { text = prefix .. "：激活", value = "t[" .. index .. "].active" }
        options[#options + 1] = { text = prefix .. "：变化", value = "t[" .. index .. "].changed" }
        options[#options + 1] = { text = prefix .. "：层数/数量", value = "t[" .. index .. "].data.count" }
        options[#options + 1] = { text = prefix .. "：光环层数", value = "t[" .. index .. "].data.applications" }
        options[#options + 1] = { text = prefix .. "：剩余时间", value = "t[" .. index .. "].data.remaining" }
        options[#options + 1] = { text = prefix .. "：进度", value = "t[" .. index .. "].data.progress" }
        options[#options + 1] = { text = prefix .. "：事件名", value = "t[" .. index .. "].data.event" }
        options[#options + 1] = { text = prefix .. "：法术 ID", value = "t[" .. index .. "].data.spellID" }
    end
    return options
end

local function BuildConditionActionOptions(draft)
    local options = CopyTable(CONDITION_BASE_ACTION_OPTIONS)
    local overlays = draft and draft.appearance and draft.appearance.overlays or {}
    for index, overlay in ipairs(overlays) do
        local prefix = "子元素 " .. tostring(index) .. " " .. (overlay.type == "bar" and "进度条" or "文字")
        options[#options + 1] = { text = prefix .. "：可见性", value = "overlay[" .. index .. "].visible" }
        if overlay.type == "bar" then
            options[#options + 1] = { text = prefix .. "：进度值", value = "overlay[" .. index .. "].value" }
            options[#options + 1] = { text = prefix .. "：进度颜色", value = "overlay[" .. index .. "].fillColor" }
        else
            options[#options + 1] = { text = prefix .. "：文本", value = "overlay[" .. index .. "].text" }
            options[#options + 1] = { text = prefix .. "：文本颜色", value = "overlay[" .. index .. "].color" }
        end
    end
    options[#options + 1] = { text = "发光（预留，当前禁用）", value = "glow.disabled" }
    return options
end

function Lab:RenderConditionsPage(parent)
    local editable = IsEditableSelection()
    local state = GetRuntimeState()
    local y = self:RenderHeader(parent, "条件", "根据触发器状态或数据修改显示属性；不执行任意 Lua。")
    if not editable then
        y = self:RenderReadOnlyBanner(parent, y, "函数型 conditions 不反编译，只显示诊断。")
        CreateLine(parent, y, "声明式规则：" .. tostring(state and state.conditionRuleCount or 0) .. " 条，当前命中：" .. tostring(state and state.conditionRuleMatchCount or 0), "color.text.primary", 760)
        y = y - 30
        y = self:RenderConditionCallbacks(parent, y)
        self:RenderConditionTriggerStates(parent, y, state)
        return
    end

    local draft = GetCurrentDraft()
    if type(draft.conditionRules) ~= "table" then draft.conditionRules = {} end
    if #draft.conditionRules > 0 and not self.selectedConditionIndex then
        self.selectedConditionIndex = 1
    end
    local listPanel = CreatePanel(parent, { width = 320, height = 430, surface = "color.surface.window", border = "color.border.subtle" })
    listPanel:SetPoint("TOPLEFT", 20, y)
    local detailPanel = CreatePanel(parent, { width = 468, height = 430, surface = "color.surface.window", border = "color.border.subtle" })
    detailPanel:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 12, 0)
    self:RenderConditionRuleList(listPanel)
    self:RenderConditionRuleDetail(detailPanel, state)
end

function Lab:RenderConditionRuleList(parent)
    local draft = GetCurrentDraft()
    local rules = draft.conditionRules or {}
    local y = -12
    CreateLine(parent, y, "条件规则", "color.text.heading", 280)
    y = y - 30
    if #rules == 0 then
        CreateLine(parent, y, "没有规则。添加后可用触发器状态驱动显示变化。", "color.text.secondary", 280)
    end
    for index, rule in ipairs(rules) do
        if index > 9 then break end
        NormalizeConditionRule(rule, index)
        local label = string_format("%d. %s -> %s", index, ShortLabel(rule.source, 16), ShortLabel(rule.actionTarget, 14))
        local button = CreateButton(parent, label, 280, function()
            self.selectedConditionIndex = index
            self:Render()
        end)
        button:SetPoint("TOPLEFT", 14, y)
        SetButtonSelected(button, self.selectedConditionIndex == index)
        y = y - 32
    end

    local add = CreateButton(parent, "添加", 60, function()
        rules[#rules + 1] = NormalizeConditionRule({ id = "rule" .. tostring(#rules + 1) }, #rules + 1)
        self.selectedConditionIndex = #rules
        self:MarkChanged(false)
        self:Render()
    end)
    add:SetPoint("BOTTOMLEFT", 14, 14)
    local duplicate = CreateActionButton(parent, "复制", 60, function()
        table_insert(rules, CopyTable(rules[self.selectedConditionIndex]))
        self.selectedConditionIndex = #rules
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedConditionIndex and rules[self.selectedConditionIndex]))
    duplicate:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local remove = CreateActionButton(parent, "删除", 60, function()
        table_remove(rules, self.selectedConditionIndex)
        if #rules == 0 then
            self.selectedConditionIndex = nil
        elseif self.selectedConditionIndex > #rules then
            self.selectedConditionIndex = #rules
        end
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedConditionIndex and rules[self.selectedConditionIndex]))
    remove:SetPoint("LEFT", duplicate, "RIGHT", 6, 0)
    local up = CreateActionButton(parent, "上移", 50, function()
        local index = self.selectedConditionIndex
        rules[index], rules[index - 1] = rules[index - 1], rules[index]
        self.selectedConditionIndex = index - 1
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedConditionIndex and self.selectedConditionIndex > 1))
    up:SetPoint("LEFT", remove, "RIGHT", 6, 0)
    local down = CreateActionButton(parent, "下移", 50, function()
        local index = self.selectedConditionIndex
        rules[index], rules[index + 1] = rules[index + 1], rules[index]
        self.selectedConditionIndex = index + 1
        self:MarkChanged(false)
        self:Render()
    end, not (self.selectedConditionIndex and self.selectedConditionIndex < #rules))
    down:SetPoint("LEFT", up, "RIGHT", 6, 0)
end

function Lab:RenderConditionRuleDetail(parent, state)
    local draft = GetCurrentDraft()
    local rules = draft.conditionRules or {}
    local index = self.selectedConditionIndex or 1
    local rule = rules[index]
    if not rule then
        CreateLine(parent, -12, "选择左侧规则进行编辑。", "color.text.secondary", 420)
        return
    end
    rule = NormalizeConditionRule(rule, index)
    rules[index] = rule
    local y = -12
    CreateLine(parent, y, "规则 " .. tostring(index), "color.text.heading", 420)
    y = y - 32
    CreateEditField(parent, 14, y, "ID", rule.id, 210, function(value) rule.id = Trim(value); self:MarkChanged() end)
    y = y - 32
    CreateCheckboxField(parent, 14, y, "启用规则", rule.enabled ~= false, function(value) rule.enabled = value; self:MarkChanged() end)
    y = y - 34
    CreateDropdownField(parent, 14, y, "来源", rule.source, BuildConditionSourceOptions(draft, state), 250, function(value)
        rule.source = value
        self:MarkChanged(false)
        self:Render()
    end)
    y = y - 34
    CreateDropdownField(parent, 14, y, "判断", rule.operator, CONDITION_OPERATOR_OPTIONS, 150, function(value)
        rule.operator = value
        self:MarkChanged(false)
        self:Render()
    end)
    if rule.operator ~= "truthy" and rule.operator ~= "falsy" then
        CreateEditField(parent, 250, y, "值", rule.value or "", 90, function(value) rule.value = value; self:MarkChanged() end)
    end
    y = y - 42
    y = CreateSectionTitle(parent, y, "命中后修改")
    CreateDropdownField(parent, 14, y, "动作", rule.actionTarget, BuildConditionActionOptions(draft), 250, function(value)
        if value == "glow.disabled" then
            self:SetStatus("发光动作暂未接入稳定控件，当前仅作为预留项。", "warning")
            self:Render()
            return
        end
        rule.actionTarget = value
        self:MarkChanged(false)
        self:Render()
    end)
    y = y - 34
    CreateEditField(parent, 14, y, "动作值", FormatRuleValue(rule.actionValue), 250, function(value)
        rule.actionValue = value
        self:MarkChanged()
    end)
    y = y - 30
    CreateLine(parent, y, "颜色格式：r,g,b,a；布尔值：true/false；数值字段会自动转数字。", "color.text.secondary", 420)
    y = y - 26
    if state then
        CreateLine(parent, y, "运行状态：规则总数=" .. tostring(state.conditionRuleCount or 0) .. " 当前命中=" .. tostring(state.conditionRuleMatchCount or 0), "color.text.primary", 420)
    end
end

function Lab:RenderConditionCallbacks(parent, y)
    local instance = GetSelectedInstance()
    local conditions = instance and instance.definition and instance.definition.conditions
    y = CreateSectionTitle(parent, y, "函数回调")
    if type(conditions) ~= "table" then
        CreateLine(parent, y, "未声明 conditions。", "color.text.secondary", 660)
        return y - 28
    end
    local parts = {}
    for _, name in ipairs(CONDITION_NAMES) do
        if type(conditions[name]) == "function" then
            parts[#parts + 1] = name
        end
    end
    if #parts == 0 then
        CreateLine(parent, y, "conditions 存在，但没有已知函数回调。", "color.text.secondary", 660)
        return y - 28
    end
    CreateLine(parent, y, "已声明：" .. table_concat(parts, "、"), "color.text.primary", 660)
    return y - 28
end

function Lab:RenderConditionTriggerStates(parent, y, state)
    y = CreateSectionTitle(parent, y, "触发器状态")
    local draft = GetCurrentDraft()
    local runtimeById = {}
    if state then
        for _, trigger in ipairs(state.triggers or {}) do
            runtimeById[trigger.id] = trigger
        end
    end
    local source = draft.triggers
    if not IsEditableSelection() and state then source = state.triggers or {} end
    if #source == 0 then
        CreateLine(parent, y, "没有触发器。", "color.text.secondary", 660)
        return
    end
    for index, trigger in ipairs(source) do
        if index > 10 then break end
        local runtime = runtimeById[trigger.id] or trigger
        local text = string_format("触发器 %d · %s 激活=%s 变化=%s",
            index,
            tostring(TRIGGER_TYPE_LABELS[trigger.type] or trigger.type or "-"),
            FormatBool(runtime.active == true),
            FormatBool(runtime.changed == true)
        )
        CreateLine(parent, y, text, "color.text.primary", 660)
        y = y - 24
    end
end

function Lab:RenderLoadPage(parent)
    local editable = IsEditableSelection()
    local state = GetRuntimeState()
    local y = self:RenderHeader(parent, "载入", "决定这个监控是否应该加载运行。函数型 load 只做诊断，不在这里编辑。")

    local instance = GetSelectedInstance()
    if not editable then
        y = self:RenderReadOnlyBanner(parent, y, "函数型载入条件只显示诊断。")
        local expanded
        y, expanded = CreateGroupHeader(parent, "load.readonly.definition", "定义", 20, y, 800)
        if expanded then
            CreateLine(parent, y, "定义：" .. GetLoadSummaryFromDefinition(instance and instance.definition), "color.text.primary", 760)
            y = y - 26
            CreateLine(parent, y, "支持项：Retail/Mists/Wrath、职业、职业列表、专精 ID、专精 ID 列表、enabled 函数、all/any。", "color.text.secondary", 760)
            y = y - 32
        end
        y, expanded = CreateGroupHeader(parent, "load.readonly.diagnostic", "当前诊断", 20, y, 800)
        if expanded and state and state.loadDiagnostic then
            CreateLine(parent, y, tostring(state.loadDiagnostic.summary), state.loadDiagnostic.ok and "color.state.success" or "color.state.warning", 760)
            y = y - 24
            for index, reason in ipairs(state.loadDiagnostic.reasons or {}) do
                if index > 8 then break end
                CreateLine(parent, y, "原因 " .. index .. "：" .. tostring(reason), "color.text.secondary", 760)
                y = y - 22
            end
        end
        return
    end

    local draft = GetCurrentDraft()
    if type(draft.load) ~= "table" then draft.load = { mode = "always" } end
    CreateDropdownField(parent, 20, y, "载入模式", draft.load.mode or "always", LOAD_MODE_OPTIONS, 190, function(value)
        draft.load.mode = value
        self:MarkChanged(false)
        self:Render()
    end)
    y = y - 40
    if draft.load.mode == "table" then
        local expanded
        y, expanded = CreateGroupHeader(parent, "load.player", "职业 / 专精", 20, y, 800)
        if expanded then
            CreateEditField(parent, 36, y, "职业", draft.load.class or "", 170, function(value) draft.load.class = Trim(value); self:MarkChanged() end)
            CreateEditField(parent, 360, y, "职业列表", draft.load.classesText or "", 240, function(value) draft.load.classesText = value; self:MarkChanged() end)
            y = y - 34
            CreateEditField(parent, 36, y, "专精 ID", draft.load.specID or "", 170, function(value) draft.load.specID = value; self:MarkChanged() end, true)
            CreateEditField(parent, 360, y, "专精列表", draft.load.specIDsText or "", 240, function(value) draft.load.specIDsText = value; self:MarkChanged() end)
            y = y - 30
            CreateLine(parent, y, "列表用逗号分隔，例如 MAGE,WARLOCK 或 62,63,64。", "color.text.secondary", 760)
            y = y - 30
        end
        y, expanded = CreateGroupHeader(parent, "load.version", "版本", 20, y, 800)
        if expanded then
            CreateDropdownField(parent, 36, y, "Retail", BoolToTri(draft.load.retail), TRI_BOOL_OPTIONS, 130, function(value) draft.load.retail = TriToBool(value); self:MarkChanged() end)
            CreateDropdownField(parent, 286, y, "Mists", BoolToTri(draft.load.mists), TRI_BOOL_OPTIONS, 130, function(value) draft.load.mists = TriToBool(value); self:MarkChanged() end)
            y = y - 34
            CreateDropdownField(parent, 36, y, "Wrath", BoolToTri(draft.load.wrath), TRI_BOOL_OPTIONS, 130, function(value) draft.load.wrath = TriToBool(value); self:MarkChanged() end)
            y = y - 40
        end
    else
        CreateLine(parent, y, draft.load.mode == "never" and "该监控启动后会被 load 阻止。" or "该监控启动后默认通过 load。", "color.text.secondary", 760)
        y = y - 30
    end

    local expanded
    y, expanded = CreateGroupHeader(parent, "load.diagnostic", "函数 / 诊断", 20, y, 800)
    if expanded then
        CreateLine(parent, y, "编辑器不执行自定义 load 函数；函数型 load 只显示诊断。", "color.text.secondary", 760)
        y = y - 24
        if state and state.loadDiagnostic then
            CreateLine(parent, y, "当前诊断：" .. tostring(state.loadDiagnostic.summary), state.loadDiagnostic.ok and "color.state.success" or "color.state.warning", 760)
            y = y - 24
            for index, reason in ipairs(state.loadDiagnostic.reasons or {}) do
                if index > 6 then break end
                CreateLine(parent, y, "原因 " .. index .. "：" .. tostring(reason), "color.text.secondary", 760)
                y = y - 22
            end
        else
            CreateLine(parent, y, "当前诊断：监控尚未运行。", "color.text.secondary", 760)
        end
    end
end

function Lab:RenderLogsPage(parent)
    local monitor = Monitor()
    local y = self:RenderHeader(parent, "日志", "查看 Monitor ring buffer 日志。")
    if not (monitor and monitor.GetLog and monitor.GetStats) then
        CreateLine(parent, y, "YUI.Monitor 日志不可用。", "color.state.error", 660)
        return
    end
    local stats = monitor:GetStats()
    CreateLine(parent, y, string_format("启用=%s 数量=%s 上限=%s", FormatBool(stats.logEnabled), tostring(stats.logCount), tostring(stats.logLimit)), "color.text.primary", 660)
    y = y - 34

    local selected = GetSelectedId()
    local filterId = selected or self.logFilterMonitorId or ""
    CreateEditField(parent, 20, y, "monitorId", filterId, 260, function(value)
        self.logFilterMonitorId = Trim(value)
    end)
    CreateDropdownField(parent, 430, y, "事件", self.logFilterEventType or "", LOG_EVENT_OPTIONS, 160, function(value)
        self.logFilterEventType = value
        self:Render()
    end)
    y = y - 42

    local on = CreateButton(parent, "开启日志", 82, function()
        monitor:SetLogEnabled(true)
        self:Render()
    end)
    on:SetPoint("TOPLEFT", 20, y)
    local off = CreateButton(parent, "关闭日志", 82, function()
        monitor:SetLogEnabled(false)
        self:Render()
    end)
    off:SetPoint("LEFT", on, "RIGHT", 8, 0)
    local clear = CreateButton(parent, "清空", 70, function()
        monitor:ClearLog()
        self:Render()
    end)
    clear:SetPoint("LEFT", off, "RIGHT", 8, 0)
    local copy = CreateButton(parent, "复制", 70, function()
        self:CopyLogs()
    end)
    copy:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    local pause = CreateButton(parent, self.logPaused and "继续" or "暂停", 76, function()
        self.logPaused = not self.logPaused
        self:Render()
    end)
    pause:SetPoint("LEFT", copy, "RIGHT", 8, 0)
    y = y - 42

    if self.logPaused then
        CreateLine(parent, y, "日志显示已暂停，后台仍可继续记录。", "color.state.warning", 660)
        y = y - 24
    end

    local rows = self:GetFilteredLogs(monitor)
    local count = 0
    for index = #rows, 1, -1 do
        local row = rows[index]
        count = count + 1
        if count > 14 then break end
        local details = row.details or {}
        local line = string_format("#%s %.2f %s %s %s",
            tostring(row.serial or "-"),
            tonumber(row.time) or 0,
            tostring(row.eventType or "-"),
            tostring(row.monitorId or "-"),
            tostring(details.reason or details.triggerId or details.method or details.message or "")
        )
        CreateLine(parent, y, line, row.eventType == "error" and "color.state.error" or "color.text.secondary", 660)
        y = y - 22
    end
    if count == 0 then
        CreateLine(parent, y, "没有匹配日志。", "color.text.secondary", 660)
    end
end

function Lab:GetFilteredLogs(monitor)
    if self.logPaused and self.pausedLogRows then
        return self.pausedLogRows
    end
    local filter = {}
    local monitorId = Trim(self.logFilterMonitorId or "")
    local selected = GetSelectedId()
    if monitorId == "" and selected then monitorId = selected end
    if monitorId ~= "" then filter.monitorId = monitorId end
    if self.logFilterEventType and self.logFilterEventType ~= "" then
        filter.eventType = self.logFilterEventType
    end
    local rows = monitor:GetLog(filter)
    if self.logPaused then
        self.pausedLogRows = rows
    else
        self.pausedLogRows = nil
    end
    return rows
end

function Lab:CopyLogs()
    local monitor = Monitor()
    if not (monitor and monitor.GetLog) then return end
    local rows = self:GetFilteredLogs(monitor)
    local lines = {}
    for _, row in ipairs(rows) do
        local details = row.details or {}
        lines[#lines + 1] = string_format("#%s %.2f %s %s %s %s",
            tostring(row.serial or "-"),
            tonumber(row.time) or 0,
            tostring(row.eventType or "-"),
            tostring(row.monitorId or "-"),
            tostring(details.triggerId or details.method or details.reason or ""),
            tostring(details.message or "")
        )
    end
    local text = table_concat(lines, "\n")
    if YUI.Settings and YUI.Settings.ShowCopyPopup then
        YUI.Settings:ShowCopyPopup("监控日志", text)
    else
        Print(text)
    end
end

function Lab:CreateNewMonitor()
    if InCombat() then
        self:SetStatus("战斗中不能新建监控。", "warning")
        self:Render()
        return nil
    end
    self:CloseMonitorMenu()
    self:CloseMonitorPopup()
    self:ResetDraft()
    local draft = GetCurrentDraft()
    draft.id = MakeUniqueDevRawId()
    draft.name = MakeUniqueMonitorName("新建监控")
    local instance = self:SaveEditedMonitor(true, true)
    if instance then
        self:LoadInstanceToEditor(instance.id)
        self:SetStatus("已新建监控：" .. tostring(draft.name), "success")
        self:Render()
    end
    return instance
end

function Lab:RenderActions(parent)
    local create = CreateButton(parent, "新建监控", 92, function()
        self:CreateNewMonitor()
    end)
    create:SetPoint("LEFT", 0, 0)

    local refresh = CreateButton(parent, "刷新预览", 92, function()
        self:UpdatePreview()
        self:SetStatus("预览已刷新。", "success")
        self:Render()
    end)
    refresh:SetPoint("LEFT", create, "RIGHT", 8, 0)

    local close = CreateButton(parent, "关闭并恢复", 104, function()
        if self.frame then self.frame:Hide() end
    end)
    close:SetPoint("LEFT", refresh, "RIGHT", 8, 0)

    local draft = GetCurrentDraft()
    local status = string_format("当前：%s", tostring(draft.name or draft.id or "未选择"))
    local label = CreateText(parent, status, "font.size.sm", "color.text.secondary")
    label:SetPoint("LEFT", close, "RIGHT", 16, 0)
    label:SetSize(500, 22)
end

function Lab:HandleSlash(args)
    args = Trim(args or "")
    if args == "" or args == "open" then
        return self:Open()
    end
    if args == "close" then
        return self:Close()
    end
    if args == "log on" then
        local monitor = Monitor()
        if monitor and monitor.SetLogEnabled then monitor:SetLogEnabled(true) end
        Print("监控日志已开启。")
        return true
    end
    if args == "log off" then
        local monitor = Monitor()
        if monitor and monitor.SetLogEnabled then monitor:SetLogEnabled(false) end
        Print("监控日志已关闭。")
        return true
    end
    if args == "log clear" then
        local monitor = Monitor()
        if monitor and monitor.ClearLog then monitor:ClearLog() end
        Print("监控日志已清空。")
        return true
    end
    self:PrintHelp()
    return true
end

function Lab:PrintHelp()
    Print("/yui dev monitor - 打开 YUI.Monitor 控制台")
    Print("/yui dev monitor log on|off|clear - 控制 Monitor 日志")
end

Lab:ResetDraft()

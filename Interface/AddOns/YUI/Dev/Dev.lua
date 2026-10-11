local YUI = _G.YUI
YUI.Dev = YUI.Dev or {}
local Dev = YUI.Dev
local GUI2 = YUI.GUI2
local previousSlashHandler = YUI.HandleSlashCommand
local WoWIsAddOnLoaded = _G.IsAddOnLoaded
local WoWLoadAddOn = _G.LoadAddOn

local function Trim(text)
    if strtrim then
        return strtrim(text or "")
    end
    return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function Print(...)
    if YUI.Print then
        YUI:Print(...)
    else
        print(...)
    end
end

local function IsAddOnLoaded(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName)
    end
    if WoWIsAddOnLoaded then
        return WoWIsAddOnLoaded(addonName)
    end
    return false
end

local function LoadAddon(addonName)
    if C_AddOns and C_AddOns.LoadAddOn then
        return C_AddOns.LoadAddOn(addonName)
    end
    if WoWLoadAddOn then
        return WoWLoadAddOn(addonName)
    end
end

local function RunSlash(command)
    if YUI.WOW_API and YUI.WOW_API.RunSlashCmd then
        YUI.WOW_API.RunSlashCmd(command)
    end
end

local YAB_PROBE_EVENTS = {
    "ACTIONBAR_UPDATE_COOLDOWN",
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_UPDATE_USABLE",
    "SPELL_UPDATE_CHARGES",
    "SPELL_UPDATE_ICON",
    "PLAYER_TARGET_CHANGED",
    "CVAR_UPDATE",
}

local YAB_SPECIAL_PREVIEW_ORDER = {
    "zoneAbility",
    "extraAction",
    "vehicleExit",
}

local YAB_SPECIAL_PREVIEW_SAMPLES = {
    zoneAbility = {
        { texture = "Interface\\Icons\\Ability_Druid_ForceofNature", label = "Z1", count = "2" },
        { texture = "Interface\\Icons\\Spell_Nature_Lightning", label = "Z2", count = "5" },
    },
    extraAction = {
        { texture = "Interface\\Icons\\INV_Misc_QuestionMark", label = "E", count = "3" },
    },
    vehicleExit = {
        { texture = "Interface\\Icons\\Ability_Mount_RidingHorse", label = "V" },
    },
}

local function ClearYABProbeTable(tbl)
    if not tbl then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function IsInCombat()
    if YUI.API and YUI.API.Security and type(YUI.API.Security.InCombatLockdown) == "function" then
        return YUI.API.Security.InCombatLockdown() == true
    end
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true or false
end

local function HideYABSpecialGroupPreview(state)
    for _, frames in pairs(state and state.frames or {}) do
        for _, frame in ipairs(frames) do
            if frame and frame.Hide then frame:Hide() end
        end
    end
    return true
end

local function GetYABSpecialPreviewTexture(kind, sample)
    if kind == "vehicleExit" and YUI.Assets and YUI.Assets.Product then
        return YUI.Assets:Product("yactionbar", "icons\\vehicle-exit-modern.tga") or sample.texture
    end
    return sample.texture
end

local function EnsureYABSpecialPreviewButton(state, kind, index)
    local frames = state.frames[kind]
    if not frames then
        frames = {}
        state.frames[kind] = frames
    end
    local button = frames[index]
    if button then return button end
    if type(CreateFrame) ~= "function" then return nil end

    button = CreateFrame("Frame", "YUI_Dev_YABSpecialPreview_" .. kind .. "_" .. index, UIParent)
    button:EnableMouse(false)
    if button.SetClipsChildren then button:SetClipsChildren(true) end

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(1, 0.82, 0, 1)
    button.border = border

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local shade = button:CreateTexture(nil, "OVERLAY")
    shade:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    shade:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    shade:SetHeight(14)
    shade:SetColorTexture(0, 0, 0, 0.65)

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
    label:SetTextColor(1, 0.82, 0, 1)
    button.label = label

    local count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -3)
    count:SetTextColor(1, 1, 1, 1)
    button.count = count

    frames[index] = button
    return button
end

local function RefreshYABSpecialGroupPreview(manager, state, direction, spacing)
    if not (manager and state and state.active == true) then return false end
    direction = direction or "up"
    spacing = tonumber(spacing) or 4
    local config = manager.specialGroupConfig or {}
    local size = tonumber(config.size) or 52
    if size < 16 then size = 16 elseif size > 128 then size = 128 end
    local vertical = direction == "up" or direction == "down"
    local point = direction == "up" and "BOTTOM"
        or direction == "down" and "TOP"
        or direction == "left" and "RIGHT"
        or "LEFT"

    for _, kind in ipairs(YAB_SPECIAL_PREVIEW_ORDER) do
        local mover = manager.GetSpecialMemberMover and manager:GetSpecialMemberMover(kind) or nil
        local samples = YAB_SPECIAL_PREVIEW_SAMPLES[kind]
        local count = #samples
        local width = vertical and size or ((size * count) + (spacing * (count - 1)))
        local height = vertical and ((size * count) + (spacing * (count - 1))) or size
        local record = manager.bars and manager.bars[kind]
        local proxy = manager.specialMoverProxies and manager.specialMoverProxies[kind]
        if record then
            record.layoutWidth = width
            record.layoutHeight = height
        end
        if proxy then
            proxy.layoutWidth = width
            proxy.layoutHeight = height
        end
        if mover then
            mover:SetSize(width, height)
            mover:Show()
            local stepX = direction == "right" and (size + spacing)
                or direction == "left" and -(size + spacing)
                or 0
            local stepY = direction == "up" and (size + spacing)
                or direction == "down" and -(size + spacing)
                or 0
            for index, sample in ipairs(samples) do
                local button = EnsureYABSpecialPreviewButton(state, kind, index)
                if button then
                    button:SetParent(mover)
                    if button.SetFrameLevel and mover.GetFrameLevel then
                        button:SetFrameLevel((mover:GetFrameLevel() or 0) + 20)
                    end
                    button:SetSize(size, size)
                    button:ClearAllPoints()
                    button:SetPoint(point, mover, point, stepX * (index - 1), stepY * (index - 1))
                    button.icon:SetTexture(GetYABSpecialPreviewTexture(kind, sample))
                    button.label:SetText(sample.label)
                    button.count:SetText(sample.count or "")
                    button:Show()
                end
            end
        end
    end

    state.direction = direction
    state.spacing = spacing
    state.size = size
    return true
end

local function GetTimeNow()
    if type(_G.GetTimePreciseSec) == "function" then
        return _G.GetTimePreciseSec()
    end
    if type(_G.GetTime) == "function" then
        return _G.GetTime()
    end
    return 0
end

local function FormatProbeRate(value)
    return string.format("%.2f", tonumber(value) or 0)
end

local function SnapshotYABProbeSecond(probe)
    if type(probe) ~= "table" then return end
    local counts = probe.counts or {}
    local previous = probe.lastSecondCounts or {}
    local deltas = probe.lastSecondDelta or {}
    probe.lastSecondCounts = previous
    probe.lastSecondDelta = deltas
    for _, event in ipairs(YAB_PROBE_EVENTS) do
        local count = counts[event] or 0
        deltas[event] = count - (previous[event] or 0)
        previous[event] = count
    end
    probe.lastSecondAt = GetTimeNow()
end

local function GetSpellDescriptionSafe(spellId)
    if C_Spell and C_Spell.GetSpellDescription then
        local description = C_Spell.GetSpellDescription(spellId)
        if description and description ~= "" then
            return description
        end
    end
    if _G.GetSpellDescription then
        local description = _G.GetSpellDescription(spellId)
        if description and description ~= "" then
            return description
        end
    end
    return nil
end

local function GetSpellBaseCooldownSafe(spellId)
    if C_Spell and C_Spell.GetSpellBaseCooldown then
        local cooldown = C_Spell.GetSpellBaseCooldown(spellId)
        if cooldown then
            return cooldown
        end
    end
    if _G.GetSpellBaseCooldown then
        return _G.GetSpellBaseCooldown(spellId)
    end
    return nil
end

local function GetSpellToolInfo(spellId)
    local SpellAPI = YUI.API and YUI.API.Spell or YUI.WOW_API
    local info = SpellAPI and SpellAPI.GetInfo and SpellAPI.GetInfo(spellId) or nil
    local name = info and info.name or (SpellAPI and SpellAPI.GetName and SpellAPI.GetName(spellId))
    local icon = (info and (info.iconID or info.originalIconID)) or (SpellAPI and SpellAPI.GetTexture and SpellAPI.GetTexture(spellId))
    local castTime = info and info.castTime or 0
    local minRange = info and info.minRange or 0
    local maxRange = info and info.maxRange or 0
    local cooldown = GetSpellBaseCooldownSafe(spellId)

    return name, icon, castTime, minRange, maxRange, cooldown, GetSpellDescriptionSafe(spellId)
end

local function GetItemToolInfo(itemId)
    local ItemAPI = YUI.API and YUI.API.Item or YUI.WOW_API
    local info = ItemAPI and ItemAPI.GetInfo and ItemAPI.GetInfo(itemId) or nil
    local name = info and info.name or (ItemAPI and ItemAPI.GetNameByID and ItemAPI.GetNameByID(itemId))
    local icon = (info and info.texture) or (ItemAPI and ItemAPI.GetIcon and ItemAPI.GetIcon(itemId))
    local level = ItemAPI and ItemAPI.GetLevel and ItemAPI.GetLevel(itemId) or (info and info.level) or 0
    local count = ItemAPI and ItemAPI.GetCount and ItemAPI.GetCount(itemId, true) or 0
    local cooldownInfo = ItemAPI and ItemAPI.GetCooldown and ItemAPI.GetCooldown(itemId) or nil
    local quality = info and info.quality or nil
    local r, g, b = 1, 1, 1
    if ItemAPI and ItemAPI.GetQualityColor then
        r, g, b = ItemAPI.GetQualityColor(quality)
    end

    return {
        id = itemId,
        name = name,
        icon = icon,
        level = level or 0,
        count = count or 0,
        cooldown = cooldownInfo and cooldownInfo.duration or 0,
        quality = quality,
        color = { r = r or 1, g = g or 1, b = b or 1 },
        type = info and info.type or nil,
        subType = info and info.subType or nil,
        equipLoc = info and info.equipLoc or nil,
        stackCount = info and info.stackCount or nil,
        description = info and info.description or nil,
        link = info and info.link or nil,
    }
end

-- 1. 定义窗口核心变量（避免全局污染，用局部表封装）
local YUI_DevWin = {}
YUI_DevWin.frame = nil
YUI_DevWin.inputBox = nil
YUI_DevWin.typeDropdown = nil
YUI_DevWin.resultIcon = nil
YUI_DevWin.resultName = nil
YUI_DevWin.resultMeta = nil
YUI_DevWin.descText = nil

-- 2. 创建自定义窗口的核心函数
function YUI_DevWin:Create()
    -- 若窗口已存在则直接显示，避免重复创建
    if self.frame then
        self:ResetPosition()
        self.frame:Show()
        return
    end

    GUI2 = YUI.GUI2
    if not GUI2 then
        return
    end

    -- 创建 GUI2 工具窗口
    self.frame = GUI2:CreatePanel(UIParent, {
        name = "YUI_DevToolFrame",
        width = 520,
        height = 430,
        surface = "color.surface.window",
        border = "color.border.strong",
        shadow = true,
    })
    local f = self.frame

    -- 基础属性设置
    self:ResetPosition()
    f:SetMovable(true)           -- 允许拖动
    f:SetClampedToScreen(true)   -- 限制窗口在屏幕内
    f:SetFrameStrata("DIALOG")   -- 窗口层级（避免被遮挡）

    -- 标题栏（可选，增强易用性）
    local titleBar = GUI2:CreateFrame(f, { width = 480, height = 36 })
    titleBar:SetPoint("TOPLEFT", 18, -14)
    titleBar:SetPoint("TOPRIGHT", -44, -14)
    titleBar:SetMovable(true)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    titleBar:SetFrameLevel(f:GetFrameLevel() + 1)

    -- 标题文字
    local titleText = GUI2:CreateText(titleBar, "", "font.size.lg", "color.text.heading", "LEFT")
    titleText:SetPoint("LEFT", 0, 0)
    titleText:SetText("YUI 开发工具")

    -- 关闭按钮
    local closeBtn = GUI2:CreateCloseButton(f, function() f:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", -16, -16)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 2)

    local divider = GUI2:CreateTexture(f, { layer = "ARTWORK" })
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetPoint("TOPLEFT", 18, -52)
    divider:SetPoint("TOPRIGHT", -18, -52)
    divider:SetHeight(1)
    GUI2:SetTexturePaintKey(divider, "color.border.default")

    local typeLabel = GUI2:CreateText(f, "类型", "font.size.md", "color.text.secondary", "LEFT")
    typeLabel:SetPoint("TOPLEFT", 24, -76)
    typeLabel:SetWidth(36)
    typeLabel:SetJustifyH("LEFT")

    self.typeDropdown = GUI2:CreateDropdown(f, {
        width = 96,
        height = 28,
        value = "spell",
        options = {
            { text = "技能", value = "spell" },
            { text = "物品", value = "item" },
        },
        onChange = function()
            self:RefreshResult()
        end,
    })
    local dropdown = self.typeDropdown
    dropdown:SetPoint("LEFT", typeLabel, "RIGHT", 8, 0)

    local idLabel = GUI2:CreateText(f, "ID", "font.size.md", "color.text.secondary", "LEFT")
    idLabel:SetPoint("LEFT", dropdown, "RIGHT", 18, 0)
    idLabel:SetWidth(22)
    idLabel:SetJustifyH("LEFT")

    -- 3. 输入框（用于输入技能ID）
    self.inputBox = GUI2:CreateEditBox(f, {
        width = 180,
        height = 28,
        autoFocus = false,
    })
    local input = self.inputBox
    input:SetPoint("LEFT", idLabel, "RIGHT", 8, 0)
    input:SetNumeric(true)  -- 仅允许输入数字（ID是纯数字）
    input:SetMaxLetters(10) -- 限制输入长度（技能ID最大不超过9位）
    -- 输入框回调：输入/回车时刷新描述
    input:SetScript("OnTextChanged", function() self:RefreshResult() end)
    input:SetScript("OnEnterPressed", function() input:ClearFocus() end) -- 回车失焦

    -- 4. 描述文本区域（显示技能描述）
    local resultPanel = GUI2:CreatePanel(f, {
        width = 472,
        height = 244,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    resultPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -118)
    resultPanel:SetPoint("RIGHT", f, "RIGHT", -24, 0)

    self.resultIcon = GUI2:CreateIcon(resultPanel, {
        size = 40,
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
    })
    self.resultIcon:SetPoint("TOPLEFT", 14, -14)

    self.resultName = GUI2:CreateText(resultPanel, "等待查询", 18, "color.text.heading", "LEFT")
    self.resultName:SetPoint("TOPLEFT", self.resultIcon, "TOPRIGHT", 12, 0)
    self.resultName:SetPoint("RIGHT", resultPanel, "RIGHT", -14, 0)
    self.resultName:SetHeight(22)
    self.resultName:SetJustifyH("LEFT")
    self.resultName:SetWordWrap(false)

    self.resultMeta = GUI2:CreateText(resultPanel, "", "font.size.md", "color.text.secondary", "LEFT")
    self.resultMeta:SetPoint("TOPLEFT", self.resultName, "BOTTOMLEFT", 0, -5)
    self.resultMeta:SetPoint("RIGHT", resultPanel, "RIGHT", -14, 0)
    self.resultMeta:SetHeight(18)
    self.resultMeta:SetJustifyH("LEFT")
    self.resultMeta:SetWordWrap(false)

    self.descText = GUI2:CreateText(resultPanel, "", "font.size.md", "color.text.primary", "LEFT")
    local desc = self.descText
    desc:SetPoint("TOPLEFT", resultPanel, "TOPLEFT", 14, -72)
    desc:SetPoint("BOTTOMRIGHT", resultPanel, "BOTTOMRIGHT", -14, 14)
    desc:SetWordWrap(true) -- 自动换行
    desc:SetJustifyH("LEFT") -- 左对齐
    desc:SetJustifyV("TOP")
    self:ShowMessage("请输入 ID，自动显示查询结果。", "color.state.warning")
end

function YUI_DevWin:ResetPosition()
    if not self.frame then
        return
    end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
end

function YUI_DevWin:SetResult(icon, name, meta, detail, color)
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    if self.resultIcon then
        self.resultIcon:SetTexture(icon)
    end
    if self.resultName then
        self.resultName:SetText(name or "")
        if color then
            self.resultName:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
            self.resultName.gui2ColorKey = nil
        else
            GUI2:SetTextColorKey(self.resultName, "color.text.heading")
        end
    end
    if self.resultMeta then
        self.resultMeta:SetText(meta or "")
        GUI2:SetTextColorKey(self.resultMeta, "color.text.secondary")
    end
    if self.descText then
        self.descText:SetText(detail or "")
        GUI2:SetTextColorKey(self.descText, "color.text.primary")
    end
end

function YUI_DevWin:ShowMessage(message, colorKey)
    self:SetResult("Interface\\Icons\\INV_Misc_QuestionMark", "等待查询", "", message, nil)
    if self.descText then
        GUI2:SetTextColorKey(self.descText, colorKey or "color.text.secondary")
    end
end

function YUI_DevWin:GetQueryType()
    if self.typeDropdown and self.typeDropdown.GetValue then
        return self.typeDropdown:GetValue() or "spell"
    end
    return "spell"
end

function YUI_DevWin:RefreshSpellResult(queryId)
    local spellName, icon, castTime, minRange, maxRange, cooldown, spellDesc = GetSpellToolInfo(queryId)

    if not spellName then
        self:ShowMessage(string.format("技能ID %d 不存在或未解锁", queryId), "color.state.error")
        return
    end

    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    castTime = castTime or 0
    minRange = minRange or 0
    maxRange = maxRange or 0
    cooldown = cooldown or 0
    spellDesc = spellDesc or "当前客户端未提供技能描述 API。"

    local meta = string.format("%s  %s  %s", castTime > 0 and (castTime / 1000 .. "秒") or "顺发", (minRange .. "-" .. maxRange .. "码"), (cooldown / 1000) .. "s")
    local detail = "技能描述：\n" .. spellDesc
    self:SetResult(icon, spellName, meta, detail)
end

function YUI_DevWin:RefreshItemResult(queryId)
    local item = GetItemToolInfo(queryId)
    if not item.name then
        self:ShowMessage(string.format("物品ID %d 不存在或客户端尚未缓存", queryId), "color.state.error")
        return
    end

    local meta = string.format("等级 %s  数量 %s  冷却 %ss", tostring(item.level or 0), tostring(item.count or 0), tostring((item.cooldown or 0)))
    local details = {}
    details[#details + 1] = "物品信息："
    if item.type or item.subType then
        details[#details + 1] = "类型：" .. tostring(item.type or "未知") .. (item.subType and (" / " .. item.subType) or "")
    end
    if item.equipLoc and item.equipLoc ~= "" then
        details[#details + 1] = "装备位置：" .. item.equipLoc
    end
    if item.stackCount and item.stackCount > 1 then
        details[#details + 1] = "堆叠上限：" .. tostring(item.stackCount)
    end
    if item.description and item.description ~= "" then
        details[#details + 1] = "描述：" .. item.description
    end
    if item.link then
        details[#details + 1] = "链接：" .. item.link
    end

    self:SetResult(item.icon, item.name, meta, table.concat(details, "\n"), item.color)
end

-- 核心逻辑：根据输入框的ID刷新查询结果
function YUI_DevWin:RefreshResult()
    local input = self.inputBox
    local queryId = tonumber(input:GetText()) -- 转数字（输入框是字符串）

    -- 空输入处理
    if not queryId or queryId <= 0 then
        self:ShowMessage("请输入有效的ID（正整数）", "color.state.warning")
        return
    end

    local queryType = self:GetQueryType()
    if queryType == "item" then
        self:RefreshItemResult(queryId)
    else
        self:RefreshSpellResult(queryId)
    end
end

-- 初始化：插件加载时自动创建（可选，注释掉则仅通过指令调用）
-- CustomWindow:Create()

function Dev:OpenWindow()
    YUI_DevWin:Create()
end

function Dev:CreateButtons()
    if _G["YUI_DevButtons"] then
        _G["YUI_DevButtons"]:Show()
        return _G["YUI_DevButtons"]
    end

    local S = YUI.Settings
    if not S or not S.CreateButton then
        return nil
    end

    local f = CreateFrame("Frame", "YUI_DevButtons", UIParent)
    f:SetSize(80, 126)
    f:SetPoint("LEFT", 10, 0)

    local lastButton
    local buttonCount = 0
    local function AddButton(label, onClick)
        local button = S:CreateButton(f, label, 80, 24)
        if lastButton then
            button:SetPoint("TOP", lastButton, "BOTTOM", 0, -10)
        else
            button:SetPoint("TOP", 0, 0)
        end
        button:SetScript("OnClick", onClick)
        lastButton = button
        buttonCount = buttonCount + 1
        f:SetHeight(buttonCount * 24 + math.max(buttonCount - 1, 0) * 10)
        return button
    end

    AddButton("/rl", ReloadUI)

    AddButton("/yui", function()
         if S.Toggle then
             S:Toggle() -- Close/Toggle window | 关闭/切换窗口
         end
    end)

    AddButton("/yui2", function()
        if YUI.GUI2 and YUI.GUI2.Lab and YUI.GUI2.Lab.Toggle then
            YUI.GUI2.Lab:Toggle()
        else
            RunSlash("/yui2")
        end
    end)

    AddButton("/yuianim", function()
        if YUI.GUI2 and YUI.GUI2.AnimationLab and YUI.GUI2.AnimationLab.Toggle then
            YUI.GUI2.AnimationLab:Toggle()
        else
            RunSlash("/yuianim")
        end
    end)

    AddButton("/yuitrace", function()
        if YUI.Trace and YUI.Trace.Open then
            YUI.Trace.viewMode = "timeline"
            YUI.Trace:Open()
        else
            RunSlash("/yuitrace")
        end
    end)

    AddButton("监控", function()
        if YUI.Dev and YUI.Dev.MonitorDev and YUI.Dev.MonitorDev.Toggle then
            YUI.Dev.MonitorDev:Toggle()
        else
            RunSlash("/yui dev monitor")
        end
    end)

    AddButton("/cdm", function()
        HideUIPanel(GameMenuFrame)
        if not IsAddOnLoaded("Blizzard_CooldownViewer") then
            LoadAddon("Blizzard_CooldownViewer")
        end
        if CooldownViewerSettings then
            CooldownViewerSettings:Show()
        else
            print("|cFFFF0000[YUI] 冷却管理器设置面板未找到|r")
        end
    end)

    if IsAddOnLoaded("ArcUI") then
        AddButton("/arcui", function()
            RunSlash("/arcui")
        end)
    end

    -- Make draggable
    -- 可拖动
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    return f
end

function Dev:HideButtons()
    if _G["YUI_DevButtons"] then
        _G["YUI_DevButtons"]:Hide()
        return true
    end
    return false
end

function Dev:GetYABProbe()
    local probe = self.yabProbe
    if type(probe) ~= "table" then
        probe = {
            enabled = false,
            counts = {},
            lastSecondCounts = {},
            lastSecondDelta = {},
        }
        self.yabProbe = probe
    end
    return probe
end

function Dev:ResetYABProbeStats(silent)
    local probe = self:GetYABProbe()
    ClearYABProbeTable(probe.counts)
    ClearYABProbeTable(probe.lastSecondCounts)
    ClearYABProbeTable(probe.lastSecondDelta)
    probe.total = 0
    probe.startedAt = GetTimeNow()
    probe.lastSecondAt = probe.startedAt
    if silent ~= true then
        Print("YActionBar raw event probe reset.")
    end
end

function Dev:StartYABProbe()
    if type(CreateFrame) ~= "function" then
        Print("YActionBar raw event probe unavailable: CreateFrame missing.")
        return false
    end

    local probe = self:GetYABProbe()
    if not probe.frame then
        probe.frame = CreateFrame("Frame", "YUI_Dev_YActionBarRawEventProbe")
    end

    self:ResetYABProbeStats(true)
    probe.enabled = true
    probe.frame:SetScript("OnEvent", function(_, event)
        local state = Dev.yabProbe
        if type(state) ~= "table" or state.enabled ~= true then return end
        local counts = state.counts
        counts[event] = (counts[event] or 0) + 1
        state.total = (state.total or 0) + 1
    end)
    probe.frame:UnregisterAllEvents()
    for _, event in ipairs(YAB_PROBE_EVENTS) do
        probe.frame:RegisterEvent(event)
    end

    if probe.ticker and probe.ticker.Cancel then
        probe.ticker:Cancel()
    end
    probe.ticker = nil
    if C_Timer and C_Timer.NewTicker then
        probe.ticker = C_Timer.NewTicker(1, function()
            SnapshotYABProbeSecond(Dev.yabProbe)
        end)
    end

    Print("YActionBar raw event probe on.")
    return true
end

function Dev:StopYABProbe(silent)
    local probe = self.yabProbe
    if type(probe) ~= "table" then return true end
    probe.enabled = false
    if probe.ticker and probe.ticker.Cancel then
        probe.ticker:Cancel()
    end
    probe.ticker = nil
    if probe.frame then
        probe.frame:UnregisterAllEvents()
        probe.frame:SetScript("OnEvent", nil)
    end
    if silent ~= true then
        Print("YActionBar raw event probe off.")
    end
    return true
end

function Dev:PrintYABProbeStats()
    local probe = self:GetYABProbe()
    local now = GetTimeNow()
    local elapsed = math.max(now - (probe.startedAt or now), 0.001)
    Print(string.format(
        "YActionBar raw event probe: enabled=%s elapsed=%.1fs total=%d",
        tostring(probe.enabled == true),
        elapsed,
        probe.total or 0
    ))
    for _, event in ipairs(YAB_PROBE_EVENTS) do
        local count = probe.counts[event] or 0
        Print(string.format(
            "YActionBar raw event probe[%s]: count=%d rate=%s/s last1s=%d",
            event,
            count,
            FormatProbeRate(count / elapsed),
            probe.lastSecondDelta[event] or 0
        ))
    end
end

function Dev:HandleYABProbeSlash(args)
    args = Trim(args)
    local command = args:match("^(%S+)") or "stats"
    command = command:lower()

    if command == "on" or command == "start" then
        self:StartYABProbe()
        return true
    elseif command == "off" or command == "stop" then
        self:StopYABProbe()
        return true
    elseif command == "reset" or command == "clear" then
        self:ResetYABProbeStats(false)
        return true
    elseif command == "stats" or command == "status" then
        self:PrintYABProbeStats()
        return true
    end

    Print("用法：/yui dev yabprobe on|off|reset|stats")
    return true
end

function Dev:GetYABSpecialGroupPreview()
    local state = self.yabSpecialGroupPreview
    if type(state) ~= "table" then
        state = {
            active = false,
            frames = {},
            refresh = RefreshYABSpecialGroupPreview,
            hide = HideYABSpecialGroupPreview,
        }
        self.yabSpecialGroupPreview = state
    end
    return state
end

function Dev:SetYABSpecialGroupPreview(enabled, silent)
    enabled = enabled == true
    local yab = YUI.YActionBar
    local manager = yab and yab.BarManager
    local state = self:GetYABSpecialGroupPreview()

    if enabled and IsInCombat() then
        if silent ~= true then Print("特殊动作条组模拟不能在战斗中开启。") end
        return false, "combat"
    end
    if enabled and not (manager and manager.runtimeActive == true) then
        if silent ~= true then Print("特殊动作条组模拟不可用：请先启用 YActionBar。") end
        return false, "inactive"
    end

    state.active = enabled
    state.manager = manager
    if manager then
        manager.specialGroupDevPreview = state
    end

    if enabled then
        if manager.PrepareSpecialGroupingMoverFrames then
            manager:PrepareSpecialGroupingMoverFrames(yab:GetDB())
        end
        RefreshYABSpecialGroupPreview(
            manager,
            state,
            manager:GetSpecialGroupGrowthDirection(),
            manager.specialGroupConfig and manager.specialGroupConfig.spacing
        )
    else
        HideYABSpecialGroupPreview(state)
    end

    local applied = true
    local reason
    if manager and manager.runtimeActive == true then
        if manager.RefreshSpecialGroupingRuntime then
            applied, reason = manager:RefreshSpecialGroupingRuntime(
                yab:GetDB(),
                enabled and "dev-special-group-preview-on" or "dev-special-group-preview-off",
                true
            )
        elseif manager.ApplySpecialActionGrouping then
            applied, reason = manager:ApplySpecialActionGrouping("dev-special-group-preview")
        end
    end

    if enabled and applied == false then
        state.active = false
        HideYABSpecialGroupPreview(state)
        if silent ~= true then
            Print("特殊动作条组模拟开启失败：", reason or "unknown")
        end
        return false, reason
    end

    if silent ~= true then
        if enabled then
            Print("特殊动作条组模拟：开（区域技能 ×2、额外动作、离开载具）。")
            Print("再次输入 /yui dev yabgroup 可关闭。")
        elseif reason == "combat deferred" then
            Print("特殊动作条组模拟：关；真实布局将在脱战后恢复。")
        else
            Print("特殊动作条组模拟：关。")
        end
    end
    return true, reason
end

function Dev:ToggleYABSpecialGroupPreview()
    local state = self:GetYABSpecialGroupPreview()
    return self:SetYABSpecialGroupPreview(state.active ~= true)
end

function Dev:PrintYABSpecialGroupPreviewStatus()
    local state = self:GetYABSpecialGroupPreview()
    Print(string.format(
        "特殊动作条组模拟：%s direction=%s spacing=%s size=%s error=%s",
        state.active == true and "开" or "关",
        tostring(state.direction or "n/a"),
        tostring(state.spacing or "n/a"),
        tostring(state.size or "n/a"),
        tostring(state.lastError or "none")
    ))
end

function Dev:HandleYABSpecialGroupPreviewSlash(args)
    args = Trim(args)
    local command = args:match("^(%S+)") or "toggle"
    command = command:lower()
    if command == "toggle" then
        return self:ToggleYABSpecialGroupPreview()
    elseif command == "on" or command == "start" then
        return self:SetYABSpecialGroupPreview(true)
    elseif command == "off" or command == "stop" then
        return self:SetYABSpecialGroupPreview(false)
    elseif command == "status" then
        self:PrintYABSpecialGroupPreviewStatus()
        return true
    end
    Print("用法：/yui dev yabgroup [on|off|toggle|status]")
    return true
end

function Dev:SetEnabled(enabled, silent)
    enabled = enabled == true
    if YUI.SetPersistedDevMode then
        YUI:SetPersistedDevMode(enabled)
    else
        YUI.IsDev = enabled
        if YUI.global then
            YUI.global.devMode = enabled
        end
    end

    if enabled then
        self:CreateButtons()
    else
        self:StopYABProbe(true)
        self:SetYABSpecialGroupPreview(false, true)
        self:HideButtons()
        if self.MonitorDev and type(self.MonitorDev.Close) == "function" then
            self.MonitorDev:Close(true)
        end
        local feature = YUI.MythicPlusTools and YUI.MythicPlusTools.PVEEnhancement
        if feature and type(feature.ClearDevStatsData) == "function" then
            feature:ClearDevStatsData(true)
        end
    end

    if not silent then
        Print("开发模式：", enabled and "开" or "关")
    end
    return enabled
end

function Dev:Toggle()
    return self:SetEnabled(not YUI.IsDev)
end

function Dev:PrintStatus()
    local button = _G["YUI_DevButtons"]
    local buttonStatus = button and (button:IsShown() and "显示" or "隐藏") or "未创建"

    Print("开发模式：", YUI.IsDev and "开" or "关")
    Print("持久化：", (YUI.GetPersistedDevMode and YUI:GetPersistedDevMode() or (YUI.global and YUI.global.devMode)) and "开" or "关")
    Print("开发按钮：", buttonStatus)
end

function Dev:PrintHelp()
    Print("开发命令：")
    Print("/yui dev on")
    Print("/yui dev off")
    Print("/yui dev toggle")
    Print("/yui dev status")
    Print("/yui dev tool")
    Print("/yui dev monitor")
    Print("/yui dev monitor log on|off|clear")
    Print("/yui dev clean")
    Print("/yui dev cpu on [label]")
    Print("/yui dev cpu off")
    Print("/yui dev cpu status")
    Print("/yui dev cpu run [label]")
    Print("/yui dev yabprobe on|off|reset|stats")
    Print("/yui dev yabgroup [on|off|toggle|status]")
    Print("/yui dev pvestats stress [count] [seed]")
    Print("/yui dev pvestats random [seed]")
    Print("/yui dev pvestats clear")
    Print("/yui dev pvestats status")
end

function Dev:HandleSlash(args)
    args = Trim(args)
    if args == "" or args == "help" then
        self:PrintHelp()
        return true
    end

    local command = args:match("^(%S+)") or ""
    command = command:lower()

    if command == "on" or command == "enable" then
        self:SetEnabled(true)
        return true
    elseif command == "off" or command == "disable" then
        self:SetEnabled(false)
        return true
    elseif command == "toggle" then
        self:Toggle()
        return true
    elseif command == "status" then
        self:PrintStatus()
        return true
    elseif command == "tool" then
        self:OpenWindow()
        return true
    elseif command == "monitor" then
        local lab = self.MonitorDev
        if lab and type(lab.HandleSlash) == "function" then
            local rest = args:match("^%S+%s*(.*)$") or ""
            return lab:HandleSlash(rest)
        end
        Print("监控开发实验室不可用。")
        return true
    elseif command == "clean" then
        self:CleanSavedCharacterData()
        return true
    elseif command == "cpu" or command == "profile" then
        local profiler = self.CPUProfiler
        if profiler and type(profiler.HandleSlash) == "function" then
            local rest = args:match("^%S+%s*(.*)$") or ""
            return profiler:HandleSlash(rest)
        end
        Print("CPU 性能分析开发命令不可用。")
        return true
    elseif command == "yabprobe" or command == "yab-probe" then
        local rest = args:match("^%S+%s*(.*)$") or ""
        return self:HandleYABProbeSlash(rest)
    elseif command == "yabgroup" or command == "yab-group" or command == "yabspecial" then
        local rest = args:match("^%S+%s*(.*)$") or ""
        return self:HandleYABSpecialGroupPreviewSlash(rest)
    elseif command == "pvestats" or command == "pve-stats" then
        local feature = YUI.MythicPlusTools and YUI.MythicPlusTools.PVEEnhancement
        if feature and type(feature.HandleDevCommand) == "function" then
            local rest = args:match("^%S+%s*(.*)$") or ""
            return feature:HandleDevCommand(rest)
        end
        Print("PVE 统计开发命令不可用。")
        return true
    end

    self:PrintHelp()
    return true
end

function YUI:HandleDevSlashCommand(msg)
    local text = Trim(msg)
    local command, args = text:match("^(%S+)%s*(.*)$")

    if command and command:lower() == "dev" then
        return Dev:HandleSlash(args)
    end

    return false
end

function YUI:HandleSlashCommand(msg)
    if self.HandleDevSlashCommand and self:HandleDevSlashCommand(msg) then
        return true
    end

    if previousSlashHandler then
        return previousSlashHandler(self, msg)
    end

    return false
end

-- Initialize Dev Buttons on AddOn Load
-- 插件加载时初始化开发者按钮
YUI.Event:Once("PLAYER_LOGIN", function()
    if YUI.IsDev then
        Dev:SetEnabled(true, true)
    end
end)

local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local Locale = YUI.Locale
local L = Locale:Get("YBar")
local LC = Locale:Get("Core")
local CelestialSeries = S.CelestialSeries
local MODULE_PAGE_LAYOUT = S.ModulePageLayout
    or { insetX = 20, titleTop = 20 }
local LSM = LibStub("LibSharedMedia-3.0")
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.EnsureDB then
        return YUI.YBar:EnsureDB()
    end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    return profile.YBar
end

-- 模块图标映射
local L_Icons = {
    ["General"] = 134063,
    ["ModulePosition"] = 135769,
    ["MicroMenu"] = 133742,
    ["Stats"] = 135884,
    ["Professions"] = 136243, 
    ["Talents"] = 237538,
    ["Clock"] = 134376,
    ["System"] = 132320,
    ["Teleports"] = 346292,
    ["Currency"] = 133784,
    ["CurrencyTracker"] = 133784,
    ["SeasonCrests"] = 135884,
    ["DataBroker"] = 134063,
    ["EquipmentSets"] = 135026,
    ["Shard"] = 135759,
    ["DurabilityMount"] = 136241,
    ["MeetingStone"] = 134419,
    ["RaidMarkers"] = 134420,
    ["BugSack"] = "Interface\\AddOns\\BugSack\\Media\\icon",
    ["None"] = 134400,
}

local MODULE_LABEL_KEYS = {
    ["MicroMenu"] = "ybar.module.micro_menu",
    ["Stats"] = "ybar.module.stats",
    ["Professions"] = "ybar.module.professions",
    ["Talents"] = "ybar.module.talents",
    ["Clock"] = "ybar.module.clock",
    ["System"] = "ybar.module.system",
    ["Teleports"] = "ybar.module.teleports",
    ["Currency"] = (YUI.IsForever or YUI.IsRetail) and "ybar.module.gold_bags" or "ybar.module.currency",
    ["CurrencyTracker"] = "ybar.module.currency_tracker",
    ["SeasonCrests"] = "ybar.module.season_crests",
    ["DurabilityMount"] = "ybar.module.durability_mount",
    ["MeetingStone"] = "ybar.module.meeting_stone",
    ["RaidMarkers"] = "ybar.module.raid_markers",
    ["BugSack"] = "ybar.module.bugsack",
    ["Shard"] = "ybar.module.shard",
    ["EquipmentSets"] = "ybar.module.equipment",
    ["DataBroker"] = "ybar.module.broker",
}

local function GetModuleDisplayName(name)
    local module = YUI.YBar and YUI.YBar:GetModule(name)
    local icon = L_Icons[name] or L_Icons.None
    if module and module.GetSettingsIcon then icon = module:GetSettingsIcon() end
    if module and module.displayName then
        return "|T" .. icon .. ":14:14|t " .. module.displayName
    end
    local labelKey = MODULE_LABEL_KEYS[name]
    local label = name == "None" and LC["common.none"] or (labelKey and L[labelKey])
    if not label or label == "" then
        label = name
    end
    if name == "None" then
        label = "|cff808080" .. label .. "|r"
    end
    return "|T" .. icon .. ":14:14:0:0:64:64:4:60:4:60|t " .. label
end

local function GetModulePlainName(name)
    local labelKey = MODULE_LABEL_KEYS[name]
    local label = name == "None" and LC["common.none"] or (labelKey and L[labelKey])
    if not label or label == "" then
        label = name
    end
    label = tostring(label)
    label = label:gsub("|T.-|t%s*", "")
    label = label:gsub("|c%x%x%x%x%x%x%x%x", "")
    label = label:gsub("|r", "")
    return label
end

-- 模块排序权重 (越小越靠前)
local L_Orders = {
    ["Clock"] = 1,
    ["System"] = 2,
    ["MicroMenu"] = 3,
    ["Stats"] = 4,
    ["Talents"] = 5,
    ["Teleports"] = 6,
    ["DurabilityMount"] = 7,
    ["Professions"] = 8,
    ["Currency"] = 9,
    ["CurrencyTracker"] = 9.1,
    ["SeasonCrests"] = 9.2,
    ["MeetingStone"] = 10,
    ["RaidMarkers"] = 11,
    ["BugSack"] = 12,
    ["None"] = 999,
}

local defaults = {
    -- BAR_BG_TEXTURE = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3G1|r",
    BAR_BG_TEXTURE = "None",
    BAR_BG_COLOR = {1, 1, 1, 1},
}

local function GetYBarSettingsTitle()
    if YUI.GetProductShortTitle then
        local title = YUI:GetProductShortTitle("ybar")
        if type(title) == "string" and title ~= "" and title ~= "ybar" then
            return title
        end
    end

    return "Orbit InfoBar"
end

local YBAR_SETTINGS_MODULE_NAME = GetYBarSettingsTitle()
local YBAR_SETTINGS_ICON = CelestialSeries
    and CelestialSeries:GetIcon("ybar", 128)
    or ((YUI.IsForever or YUI.IsRetail) and 4777831 or 237289)
local YBAR_MOVE_ICON_PIXEL_POLICY = { snapToPixelGrid = false, texelSnappingBias = 0 }
local YBAR_MOVE_STEPPER_WIDTH = 42
local YBAR_MOVE_STEPPER_HEIGHT = 20
local YBAR_MOVE_BUTTON_SIZE = 20
local YBAR_MOVE_ICON_SIZE = 16

local function SetTextToken(text, colorKey)
    if text then GUI2:SetTextColorKey(text, colorKey or "color.text.primary") end
end

local function SetTextureToken(texture, paintKey, alpha)
    if not texture then return end
    GUI2:SetTexturePaintKey(texture, paintKey or "color.border.subtle")
    if alpha then texture:SetAlpha(alpha) end
end

local function SetButtonTextToken(button, colorKey)
    if not button then return end
    button.gui2CustomTextColor = nil
    button.gui2TextColorKey = colorKey or "color.text.primary"
    button.gui2HoverTextColorKey = "color.text.accent"
    if button.RefreshTheme then button:RefreshTheme() end
    if button.text then SetTextToken(button.text, button.gui2TextColorKey) end
end

local function CreateMoveStepper(parent, canMoveUp, canMoveDown, onMoveUp, onMoveDown)
    local stepper = GUI2:CreateFrame(parent, {
        template = "BackdropTemplate",
        width = YBAR_MOVE_STEPPER_WIDTH,
        height = YBAR_MOVE_STEPPER_HEIGHT,
        surface = "color.control.bg",
        border = "color.border.subtle",
        radiusKey = "layout.radius.icon",
    })
    stepper.gui2Surface = "color.control.bg"
    stepper.RefreshTheme = function(frame)
        GUI2:RefreshPrimitive(frame)
        SetTextureToken(frame.divider, "color.border.subtle", 0.85)
    end

    local divider = GUI2:CreateTexture(stepper, { layer = "ARTWORK" })
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetSize(1, YBAR_MOVE_STEPPER_HEIGHT - 6)
    divider:SetPoint("CENTER", 0, 0)
    stepper.divider = divider

    local upBtn = GUI2:CreateBareMicroIconButton(stepper, {
        component = "YBarMoveStepperButton",
        size = YBAR_MOVE_BUTTON_SIZE,
        microIconSize = YBAR_MOVE_ICON_SIZE,
        microIconMaxSize = YBAR_MOVE_ICON_SIZE,
        padding = 2,
        iconName = "move-up",
        tooltip = L["ybar.settings.move_up"],
        iconPixelPolicy = YBAR_MOVE_ICON_PIXEL_POLICY,
        normalColorKey = "color.text.secondary",
        hoverColorKey = "color.text.primary",
        disabledAlpha = 0.32,
        onClick = function()
            if canMoveUp and onMoveUp then onMoveUp() end
        end,
    })
    upBtn:SetPoint("LEFT", stepper, "LEFT", 0, 0)
    upBtn:SetBareMicroIconDisabled(not canMoveUp)

    local downBtn = GUI2:CreateBareMicroIconButton(stepper, {
        component = "YBarMoveStepperButton",
        size = YBAR_MOVE_BUTTON_SIZE,
        microIconSize = YBAR_MOVE_ICON_SIZE,
        microIconMaxSize = YBAR_MOVE_ICON_SIZE,
        padding = 2,
        iconName = "move-down",
        tooltip = L["ybar.settings.move_down"],
        iconPixelPolicy = YBAR_MOVE_ICON_PIXEL_POLICY,
        normalColorKey = "color.text.secondary",
        hoverColorKey = "color.text.primary",
        disabledAlpha = 0.32,
        onClick = function()
            if canMoveDown and onMoveDown then onMoveDown() end
        end,
    })
    downBtn:SetPoint("RIGHT", stepper, "RIGHT", 0, 0)
    downBtn:SetBareMicroIconDisabled(not canMoveDown)

    GUI2:RegisterThemeObject(stepper)
    stepper:RefreshTheme()
    return stepper
end

local function SetNavSelected(button, selected)
    if not button then return end
    button.gui2Selected = selected and true or false
    if selected then
        if button.LockHighlight then button:LockHighlight() end
        if button.selBg then button.selBg:Show() end
        if button.sel then button.sel:Show() end
    else
        if button.UnlockHighlight then button:UnlockHighlight() end
        if button.selBg then button.selBg:Hide() end
        if button.sel then button.sel:Hide() end
    end
    if button.RefreshTheme then button:RefreshTheme() end
    SetTextToken(button.text, selected and "color.text.accent" or "color.text.primary")
end

-- 获取所有可用模块名称（包括 None）
local function GetAllModules(includeSettings)
    local modules = {}
    if YUI.YBar and YUI.YBar.RegisteredModules then
        for k, module in pairs(YUI.YBar.RegisteredModules) do
            if not module.settingsOnly or includeSettings then table.insert(modules, k) end
        end
    end
    
    -- 自定义排序逻辑
    table.sort(modules, function(a, b)
        local orderA = L_Orders[a] or 100
        local orderB = L_Orders[b] or 100
        
        if orderA ~= orderB then
            return orderA < orderB
        end
        
        -- 其他按字母顺序排列
        return a < b
    end)
    
    table.insert(modules, 1, "None")
    return modules
end

-- 替换指定列表中的项目
local function ReplaceItem(listName, idx, newName)
    if not GetYBarDB() or not GetYBarDB().modules then return end
    if YUI.YBar and YUI.YBar.BrokerManager then YUI.YBar.BrokerManager:PreferEntry(newName) end
    local list = GetYBarDB().modules[listName]
    
    -- 如果新名字是 "None"，直接设置
    if newName == "None" then
        list[idx] = "None"
        if YUI.YBar then YUI.YBar:UpdateLayout() end
        return
    end

    -- 检查新名称是否已存在于任何列表中（互斥性检查）
    -- 如果存在，则将那个位置设为 "None"
    if newName ~= "None" then
        for _, lName in ipairs({"top", "bottom"}) do
            local l = GetYBarDB().modules[lName]
            if l then
                for i, v in ipairs(l) do
                    if v == newName then
                        -- 找到了，将其设为 None
                        l[i] = "None"
                    end
                end
            end
        end
    end
    
    -- 设置当前位置
    list[idx] = newName
    if YUI.YBar then YUI.YBar:UpdateLayout() end
end

-- 设为中间
    local function SetAsCenter(listName, idx)
        if not GetYBarDB() or not GetYBarDB().center then return end
        
        -- 更新中间锚点位置
        -- 如果 idx 为 nil 或 0，表示清除居中
        if not idx or idx == 0 then
            GetYBarDB().center[listName] = nil
        else
            GetYBarDB().center[listName] = idx
        end
        
        if YUI.YBar then YUI.YBar:UpdateLayout() end
    end

-- 创建单个可拖动/配置的项目行
local function CreateDraggableItem(parent, text, index, listName, onUpdate, isLast)
    local frame = GUI2:CreateFrame(parent) -- 移除 BackdropTemplate
    frame:SetHeight(28) -- 缩小行高
    
    -- 添加渐变分隔线 (底部)，最后一行不添加
    if not isLast then
        local divider = GUI2:CreateTexture(frame, { layer = "ARTWORK" })
        divider:SetHeight(1)
        divider:SetPoint("BOTTOMLEFT", 10, -2) -- 微调位置
        divider:SetPoint("BOTTOMRIGHT", -10, -2)
        divider:SetTexture("Interface\\Buttons\\WHITE8x8")
        -- 创建渐变：两头透明，中间明显
        -- 这是一个简单的模拟，使用 SetGradientAlpha 可能会更好，但这里用纯色模拟
        -- 为了效果，我们可以用三个 texture 拼接或者直接用简单的灰色
        SetTextureToken(divider, "color.border.subtle", 0.65)
    end 
    
    -- Check if this is the center item
    local currentCenterIdx = GetYBarDB().center and GetYBarDB().center[listName]
    local isCenter = (index == currentCenterIdx)
    
    -- 1. 模块选择 (Dropdown)
    local allModules = GetAllModules()
    local modOptions = {}
    
    -- 预先获取已放置的模块
    local placedModules = {}
    if GetYBarDB() and GetYBarDB().modules then
        if GetYBarDB().modules.top then
            for _, m in ipairs(GetYBarDB().modules.top) do placedModules[m] = "top" end
        end
        if GetYBarDB().modules.bottom then
            for _, m in ipairs(GetYBarDB().modules.bottom) do placedModules[m] = "bottom" end
        end
    end

    for _, name in ipairs(allModules) do
        local dName = GetModuleDisplayName(name)
        local coloredName = dName
        
        -- 根据放置位置着色
        if placedModules[name] == "top" then
            coloredName = "|cFFFF0000" .. dName .. "|r" -- 红色
        elseif placedModules[name] == "bottom" then
            coloredName = "|cFF00BFFF" .. dName .. "|r" -- 蓝色
        end
        
        table.insert(modOptions, {
            text = coloredName,
            selectionText = dName, -- 选中后显示白色文本
            value = name,
            func = function()
                ReplaceItem(listName, index, name)
                if onUpdate then onUpdate() end
            end
        })
    end
    
    local modBtn = S:CreateDropdown(frame, {
        width = 165,
        default = text,
        options = modOptions,
        get = function() 
            return text 
        end,
    })
    modBtn:SetPoint("LEFT", 5, 0)
    modBtn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(GetModulePlainName(text), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    modBtn:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then
            YUI.HideGameTooltip()
        end
    end)

    -- 移动逻辑
    local function MoveItem(direction)
        if not GetYBarDB() or not GetYBarDB().modules then return end
        local list = GetYBarDB().modules[listName]
        if not list then return end
        
        local newIndex = index + direction
        if newIndex < 1 or newIndex > #list then return end
        
        -- 交换
        local temp = list[index]
        list[index] = list[newIndex]
        list[newIndex] = temp
        
        -- 如果有居中设置，需要同步更新索引
        if GetYBarDB().center and GetYBarDB().center[listName] then
             if GetYBarDB().center[listName] == index then
                 GetYBarDB().center[listName] = newIndex
             elseif GetYBarDB().center[listName] == newIndex then
                 GetYBarDB().center[listName] = index
             end
        end
        
        if YUI.YBar then YUI.YBar:UpdateLayout() end
        if onUpdate then onUpdate() end
    end

    local list = GetYBarDB() and GetYBarDB().modules and GetYBarDB().modules[listName]
    local moveStepper = CreateMoveStepper(
        frame,
        index > 1,
        list and index < #list,
        function() MoveItem(-1) end,
        function() MoveItem(1) end
    )
    moveStepper:SetPoint("LEFT", modBtn, "RIGHT", 5, 0)

    if isCenter then
        -- 2. 设为中间 (Switch) - 居中状态下也可以切换为关闭
        local centerSwitch = GUI2:CreateSwitch(frame, {
            width = 40,
            thumbWidth = 14,
            leftText = L["ybar.settings.center_short"],
            rightText = L["ybar.settings.center_short"],
            leftValue = false,
            rightValue = true,
            leftColorKey = "color.control.track",
            rightColorKey = "color.control.active",
            leftTextColorKey = "color.text.secondary",
            rightTextColorKey = "color.text.primary",
            default = true,
            get = function() return true end,
            set = function(val)
                -- 当用户点击切换时，Switch 会尝试切换到另一个状态
                -- 这里的 val 是目标状态
                -- 如果当前是 true (居中)，用户点击后期望变成 false (不居中)
                if val == false then
                    SetAsCenter(listName, nil)
                    if onUpdate then onUpdate() end
                end
            end
        })
        centerSwitch:SetPoint("LEFT", moveStepper, "RIGHT", 7, 0)

        -- 如果是中间锚点，显示提示文本
        local centerText = GUI2:CreateText(frame, L["ybar.settings.center_hint"], GUI2.Fonts.size_normal)
        centerText:SetPoint("LEFT", centerSwitch, "RIGHT", 10, 0)
        SetTextToken(centerText, "color.text.accent")
        
        -- 居中时隐藏对齐方式和边距设置，因为它们不生效
    else
        -- 2. 设为中间 (Switch)
        local centerSwitch = GUI2:CreateSwitch(frame, {
            width = 40,
            thumbWidth = 14,
            leftText = L["ybar.settings.edge_short"],
            rightText = L["ybar.settings.center_short"],
            leftValue = false,
            rightValue = true,
            leftColorKey = "color.control.track",
            rightColorKey = "color.control.active",
            leftTextColorKey = "color.text.secondary",
            rightTextColorKey = "color.text.primary",
            default = false,
            get = function() return false end,
            set = function(val)
                if val then
                    SetAsCenter(listName, index)
                    if onUpdate then onUpdate() end
                end
            end
        })
        centerSwitch:SetPoint("LEFT", moveStepper, "RIGHT", 7, 0)
        
        -- 3. 对齐方式 (Switch) - 只有非 None 且有配置时显示
        if text ~= "None" then
            local alignSwitch = GUI2:CreateSwitch(frame, {
                width = 70, -- 还原宽度
                leftText = LC["common.align_left"],
                rightText = LC["common.align_right"],
                leftValue = "LEFT",
                rightValue = "RIGHT",
                variant = "choice",
                default = "LEFT",
                get = function()
                    if GetYBarDB().items[text] and GetYBarDB().items[text].align then
                        return GetYBarDB().items[text].align
                    end
                    return "LEFT"
                end,
                set = function(val)
                    if not GetYBarDB().items[text] then GetYBarDB().items[text] = {} end
                    GetYBarDB().items[text].align = val
                    if YUI.YBar then YUI.YBar:UpdateLayout() end
                end
            })
            alignSwitch:SetPoint("LEFT", centerSwitch, "RIGHT", 5, 0)
            
            -- 4. 边距 (紧凑输入框)
            local function GetMarginValue()
                local db = GetYBarDB()
                if db and db.items and db.items[text] and db.items[text].margin ~= nil then
                    return db.items[text].margin
                end
                return 2
            end

            local function NormalizeMargin(value)
                value = tonumber(value)
                if not value then return nil end
                value = math.max(-500, math.min(500, value))
                if value >= 0 then
                    return math.floor(value + 0.5)
                end
                return math.ceil(value - 0.5)
            end

            local function CommitMarginInput(editbox)
                local value = NormalizeMargin(editbox:GetText())
                if value == nil then
                    editbox:SetText(tostring(GetMarginValue()))
                    return
                end

                local oldValue = GetMarginValue()
                local db = GetYBarDB()
                if not db then
                    editbox:SetText(tostring(oldValue))
                    return
                end
                if not db.items then db.items = {} end
                if not db.items[text] then db.items[text] = {} end
                db.items[text].margin = value
                editbox:SetText(tostring(value))

                if value ~= oldValue and YUI.YBar then
                    YUI.YBar:UpdateLayout()
                end
            end

            local marginLabel = GUI2:CreateText(frame, LC["common.margin"], GUI2.Fonts.size_normal)
            marginLabel:SetPoint("LEFT", alignSwitch, "RIGHT", 20, 0)
            marginLabel:SetJustifyH("LEFT")
            marginLabel:SetWordWrap(false)
            SetTextToken(marginLabel, "color.text.primary")

            local marginInput = S:CreateEditBox(frame, {
                width = 48,
                height = 22,
                text = tostring(GetMarginValue()),
            })
            marginInput:SetJustifyH("CENTER")
            marginInput:SetPoint("LEFT", marginLabel, "RIGHT", 6, 0)
            marginInput:SetScript("OnEnterPressed", function(editbox)
                CommitMarginInput(editbox)
                editbox:ClearFocus()
            end)
            marginInput:SetScript("OnEscapePressed", function(editbox)
                editbox:SetText(tostring(GetMarginValue()))
                editbox:ClearFocus()
            end)
            marginInput:HookScript("OnEditFocusLost", CommitMarginInput)
        end
    end
    
    return frame
end

-- 创建可排序列表
local function CreateSortableList(parent, listName, onUpdate)
    local container = GUI2:CreateFrame(parent)
    container:SetSize(parent:GetWidth(), 300) 
    
    local content = GUI2:CreateFrame(container)
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    
    local function Refresh()
        -- 清除子元素
        if content.children then
            for _, child in ipairs(content.children) do
                child:Hide()
            end
        end
        content.children = {}
        
        if not GetYBarDB() or not GetYBarDB().modules then return end
        local list = GetYBarDB().modules[listName]
        if not list then return end
        local yOffset = 0
        
        local totalItems = #list
        for i, name in ipairs(list) do
            local item = CreateDraggableItem(content, name, i, listName, function()
                Refresh()
                if onUpdate then onUpdate() end
            end, i == totalItems)
            item:SetPoint("TOPLEFT", 0, yOffset)
            item:SetPoint("TOPRIGHT", 0, yOffset)
            item:Show()
            table.insert(content.children, item)
            
            yOffset = yOffset - 32 -- 进一步缩小间距 (28 + 4)
        end
        
        container:SetHeight(math.abs(yOffset) + 10)
    end
    
    container.Refresh = Refresh
    Refresh()
    
    return container
end

-- 渲染通用设置
local function RenderGeneralSettings(parent)
    local title = GUI2:CreateText(parent, L["ybar.settings.general"], GUI2.Fonts.size_header)
    SetTextToken(title, "color.text.heading")
    title:SetPoint("TOPLEFT", 10, -10)

    local scroll = GUI2:CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 0, -40)
    scroll:SetPoint("BOTTOMRIGHT", -15, 0)
    
    local content = GUI2:CreateFrame(scroll)
    scroll:SetScrollChild(content)
    content:SetWidth(parent:GetWidth() - 20)

    local backgroundLabelWidth = 80
    local backgroundControlGap = GUI2:GetMetric("layout.form.gap", 10)
    local backgroundControlX = backgroundLabelWidth + backgroundControlGap
    local backgroundControlWidth = 130
    local backgroundRowWidth = 220
    
    local options = {
        {
            type = "divider",
            label = L["ybar.settings.bar_background"],
            width = 400,
            alignLeft = true,
        },
        {
            type = "row",
            children = {
                {
                    type = "slider",
                    inline = true,
                    inputWidth = 56,
                    labelWidth = backgroundControlX,
                    width = 220,
                    min = 10,
                    max = 60,
                    step = 1,
                    label = L["ybar.settings.bottom_bar_height"],
                    default = 21,
                    get = function() return GetYBarDB().bottomHeight end,
                    set = function(val) 
                        GetYBarDB().bottomHeight = val
                        if YUI.YBar then YUI.YBar:UpdateAppearance() end
                    end
                },
                {
                    type = "slider",
                    inline = true,
                    inputWidth = 56,
                    labelWidth = backgroundControlX,
                    width = 220,
                    min = 10,
                    max = 60,
                    step = 1,
                    label = L["ybar.settings.top_bar_height"],
                    default = 21,
                    get = function() return GetYBarDB().topHeight end,
                    set = function(val) 
                        GetYBarDB().topHeight = val
                        if YUI.YBar then YUI.YBar:UpdateAppearance() end
                    end
                },
            }
        },
        {
            type = "texture",
            rowWidth = backgroundRowWidth,
            labelWidth = backgroundLabelWidth,
            controlWidth = backgroundControlWidth,
            menuWidth = 260,
            valueWidth = 0,
            label = LC["common.background_texture"],
            default = defaults.BAR_BG_TEXTURE,
            get = function() return GetYBarDB().texture or defaults.BAR_BG_TEXTURE end,
            set = function(val)
                GetYBarDB().texture = val
                if YUI.YBar then YUI.YBar:UpdateAppearance() end
            end
        },
        {
             type = "row",
             children = {
                 {
                    type = "color",
                    label = LC["common.background_color"],
                    width = 220,
                    hasAlpha = true,
                    default = defaults.BAR_BG_COLOR,
                    get = function() return GetYBarDB().bgColor or defaults.BAR_BG_COLOR end,
                    set = function(val)
                        GetYBarDB().bgColor = val
                        if YUI.YBar then YUI.YBar:UpdateAppearance() end
                    end
                 },
                 {
                    type = "checkbox",
                    label = LC["common.use_class_color"],
                    width = 220,
                    default = false,
                    get = function() return GetYBarDB().classColor end,
                    set = function(val)
                        GetYBarDB().classColor = val
                        if YUI.YBar then YUI.YBar:UpdateAppearance() end
                    end
                 }
             }
        },
        {
            type = "divider",
            label = L["ybar.settings.global_font_style"],
            width = 400,
            alignLeft = true,
        },
        {
             type = "row",
             children = {
                 {
                    type = "checkbox",
                    label = LC["common.font_outline"],
                    width = 220,
                    default = false,
                    get = function() return GetYBarDB().fontOutline end,
                    set = function(val)
                        GetYBarDB().fontOutline = val
                        if YUI.YBar then YUI.YBar:UpdateLayout() end
                    end
                 },
                 {
                    type = "checkbox",
                    label = LC["common.font_shadow"],
                    width = 220,
                    default = true,
                    get = function() return GetYBarDB().fontShadow end,
                    set = function(val)
                        GetYBarDB().fontShadow = val
                        if YUI.YBar then YUI.YBar:UpdateLayout() end
                    end
                 }
             }
        }
    }

    -- Add Display Mode settings
    table.insert(options, {
        type = "divider",
        label = L["ybar.settings.module_display_mode"],
        width = 400,
        alignLeft = true,
    })
    
    table.insert(options, {
        type = "text",
        label = L["ybar.settings.module_display_mode_desc"],
        colorKey = "color.text.secondary",
        -- wrap = true, -- RenderConfig may not support wrap directly depending on implementation, but text usually wraps if width constrained
    })
    
    table.insert(options, { type = "space", height = 10 })

    local displayModeOptions = {
        { text = "|cFFFFFFFF" .. L["ybar.settings.display.always"] .. "|r", value = "ALWAYS" },
        { text = "|cFF00FF96" .. L["ybar.settings.display.mouseover"] .. "|r", value = "MOUSEOVER" },
        { text = "|cFF1EFF00" .. L["ybar.settings.display.group1"] .. "|r", value = "GROUP1" },
        { text = "|cFF0070DD" .. L["ybar.settings.display.group2"] .. "|r", value = "GROUP2" },
        { text = "|cFFA335EE" .. L["ybar.settings.display.group3"] .. "|r", value = "GROUP3" },
        { text = "|cFFFF8000" .. L["ybar.settings.display.group4"] .. "|r", value = "GROUP4" },
        { text = "|cFFE6CC80" .. L["ybar.settings.display.group5"] .. "|r", value = "GROUP5" },
        { text = YUI.F:GetGradientText(L["ybar.settings.display.group6"], {r=1, g=1, b=0}, {r=1, g=0.27, b=0}), value = "GROUP6" },
    }

    local modules = GetAllModules()
    local validModules = {}
    for _, modName in ipairs(modules) do
        if modName ~= "None" then
            table.insert(validModules, modName)
        end
    end

    for i = 1, #validModules, 2 do
        local children = {}
        for j = 0, 1 do
            local modName = validModules[i+j]
            if modName then
                local displayName = GetModuleDisplayName(modName)
                table.insert(children, {
                    type = "dropdown",
                    label = displayName,
                    width = 220,
                    options = displayModeOptions,
                    default = "ALWAYS",
                    get = function() 
                        if GetYBarDB().displayModes and GetYBarDB().displayModes[modName] then
                            return GetYBarDB().displayModes[modName]
                        end
                        return "ALWAYS"
                    end,
                    set = function(val)
                        if not GetYBarDB().displayModes then GetYBarDB().displayModes = {} end
                        GetYBarDB().displayModes[modName] = val
                        if YUI.YBar and YUI.YBar.UpdateDisplayModes then 
                            YUI.YBar:UpdateDisplayModes() 
                        end
                    end
                })
            end
        end
        table.insert(options, {
            type = "row",
            children = children
        })
    end
    
    S:RenderConfig(content, options)
end

-- 渲染模块位置设置
local function RenderModulePositionSettings(parent)
    local scroll = GUI2:CreateScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", 0, 0) -- 向上移动，减少留白
    scroll:SetPoint("BOTTOMRIGHT", -15, 0)
    
    local content = GUI2:CreateFrame(scroll)
    scroll:SetScrollChild(content)
    content:SetWidth(parent:GetWidth() - 20)
    content:SetHeight(510) 
    
    local yOffset = 0
    
    local tabFrame = GUI2:CreateFrame(content)
    tabFrame:SetPoint("TOPLEFT", 10, yOffset)
    tabFrame:SetPoint("RIGHT", -10, 0)
    tabFrame:SetHeight(510) -- Dynamic
    
    local currentTab = "bottom" -- 默认选中底部
    local listContainer = GUI2:CreateFrame(tabFrame) -- 移除 BackdropTemplate
    listContainer:SetPoint("TOPLEFT", 0, -30)
    listContainer:SetPoint("BOTTOMRIGHT", 0, 0)
    
    local tab1, tab2
    
    local function SwitchTab(tab)
        currentTab = tab
        
        if tab == "bottom" then
            SetNavSelected(tab1, true)
            SetNavSelected(tab2, false)
        else
            SetNavSelected(tab2, true)
            SetNavSelected(tab1, false)
        end
        
        -- 清空容器
        for _, child in ipairs({listContainer:GetChildren()}) do child:Hide() end
        
        -- 创建列表
        local listName = (tab == "top") and "top" or "bottom"
        local list = CreateSortableList(listContainer, listName)
        list:SetPoint("TOPLEFT", 5, -5)
        list:SetPoint("TOPRIGHT", -5, -5)
        
        -- 更新高度
        tabFrame:SetHeight(list:GetHeight() + 40)
        content:SetHeight(math.abs(yOffset) + tabFrame:GetHeight() + 20)
    end
    
    -- 调整 Tab 顺序：底部信息条在前，顶部信息条在后
    tab1 = GUI2:CreateNavButton(tabFrame, L["ybar.settings.bottom_bar"], nil, 120, 24)
    tab1:SetPoint("TOP", tabFrame, "TOP", -65, 0) -- 居中偏左
    tab1.text:SetFont(GUI2.Fonts.normal, GUI2.Fonts.size_normal)
    tab1.text:ClearAllPoints()
    tab1.text:SetPoint("CENTER", 0, 0) -- 文字居中
    tab1:SetScript("OnClick", function() SwitchTab("bottom") end)
    
    tab2 = GUI2:CreateNavButton(tabFrame, L["ybar.settings.top_bar"], nil, 120, 24)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 10, 0) -- 紧接在 tab1 右侧
    tab2.text:SetFont(GUI2.Fonts.normal, GUI2.Fonts.size_normal)
    tab2.text:ClearAllPoints()
    tab2.text:SetPoint("CENTER", 0, 0) -- 文字居中
    tab2:SetScript("OnClick", function() SwitchTab("top") end)
    
    SwitchTab("bottom")

    -- 尝试隐藏滚动条
    -- 根据当前布局计算，如果内容高度不超过 510，可以隐藏
    -- 目前行高 28，间距 4，11 行，大约 352 像素
    -- 加上 Tab 按钮高度和顶部偏移，应该足够
    -- if scroll.ScrollBar then
    --     scroll.ScrollBar:Hide()
    --     scroll:EnableMouseWheel(false) -- 如果不需要滚动，也可以禁用鼠标滚轮
    -- end
    -- -- 调整 scroll frame 大小以填满，不再留出滚动条空间
    -- scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    -- content:SetWidth(parent:GetWidth())
end

-- 渲染子模块设置
local function RenderModuleSettings(parent, moduleName)
    local displayName = GetModuleDisplayName(moduleName)
    if moduleName == "DataBroker" then displayName = displayName .. " (DataBroker)" end
    local title = GUI2:CreateText(parent, format(L["ybar.settings.module_settings_title"], displayName), GUI2.Fonts.size_header)
    SetTextToken(title, "color.text.heading")
    title:SetPoint("TOPLEFT", 10, -10)
    
    -- 尝试从模块获取配置
    local module = YUI.YBar and YUI.YBar:GetModule(moduleName)
    if module and module.GetOptions then
        local options = module:GetOptions()
        if options then
            -- 创建滚动框架
            local scroll = GUI2:CreateScrollFrame(parent)
            scroll:SetPoint("TOPLEFT", 0, -40)
            scroll:SetPoint("BOTTOMRIGHT", -15, 0) -- 留出滚动条空间
            if module.OnSettingsEnter then
                module:OnSettingsEnter()
                scroll:HookScript("OnShow", function() module:OnSettingsEnter() end)
                scroll:HookScript("OnHide", function() module:OnSettingsLeave() end)
            end

            if YUI.YBar then
                YUI.YBar.CurrentSettingsModule = moduleName
                YUI.YBar.CurrentSettingsScroll = scroll
            end
            
            local configContainer = GUI2:CreateFrame(scroll)
            scroll:SetScrollChild(configContainer)
            
            -- 设置宽度，减去滚动条宽度
            configContainer:SetWidth(parent:GetWidth() - 25)
            configContainer:SetHeight(1) -- 初始高度，S:RenderConfig 会自动增加

            local function RefreshConfigScroll(container)
                local contentHeight = math.max(container:GetHeight() or 1, 1)
                local viewportHeight = math.max(parent:GetHeight() - 50, 1)
                local needsScroll = contentHeight > viewportHeight

                scroll:ClearAllPoints()
                scroll:SetPoint("TOPLEFT", 0, -40)
                if needsScroll then
                    scroll:SetPoint("BOTTOMRIGHT", -15, 0)
                    container:SetWidth(parent:GetWidth() - 25)
                    if scroll.ScrollBar then
                        scroll.ScrollBar:Show()
                    end
                    scroll:EnableMouseWheel(true)
                else
                    scroll:SetPoint("BOTTOMRIGHT", -5, 0)
                    container:SetWidth(parent:GetWidth() - 5)
                    if scroll.ScrollBar then
                        scroll.ScrollBar:Hide()
                    end
                    scroll:EnableMouseWheel(false)
                    if scroll.SetVerticalScroll then
                        scroll:SetVerticalScroll(0)
                    end
                end
            end

            configContainer.yuiConfigScrollFrame = scroll
            configContainer.yuiConfigAfterRender = RefreshConfigScroll

            -- 渲染配置到滚动子框架中
            S:RenderConfig(configContainer, options)
            if YUI.YBar then
                YUI.YBar.RefreshFeatureSettings = function(owner)
                    if owner.CurrentSettingsScroll ~= scroll or not scroll:IsShown() then return end
                    if configContainer.ybarRendering then return end
                    configContainer.ybarRendering = true
                    local offset = scroll:GetVerticalScroll()
                    S:ClearConfig(configContainer)
                    S:RenderConfig(configContainer, module:GetOptions())
                    configContainer.ybarRendering = nil
                    scroll:SetVerticalScroll(math.min(offset, scroll:GetVerticalScrollRange()))
                end
            end

            if YUI.YBar and YUI.YBar.PendingSettingsScroll then
                local pendingScroll = YUI.YBar.PendingSettingsScroll[moduleName]
                if pendingScroll and scroll.SetVerticalScroll then
                    YUI.YBar.PendingSettingsScroll[moduleName] = nil
                    local function RestoreScroll()
                        if YUI.YBar and YUI.YBar.CurrentSettingsScroll ~= scroll then
                            return
                        end
                        local maxScroll = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or pendingScroll
                        scroll:SetVerticalScroll(math.min(pendingScroll, maxScroll or pendingScroll))
                    end
                    RestoreScroll()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, RestoreScroll)
                    end
                end
            end
            
            return
        end
    end

    local desc = GUI2:CreateText(parent, L["ybar.settings.no_module_options"], GUI2.Fonts.size_normal)
    desc:SetPoint("TOPLEFT", 10, -40)
    SetTextToken(desc, "color.text.secondary")
end

-- Passive product showcase. One cancellable animation owns both rows.
local function RenderOrbitIntroduction(parent)
    if parent.orbitIntroduction then parent.orbitIntroduction:Hide() end
    local page=GUI2:CreateFrame(parent,{height=430})
    parent.orbitIntroduction=page
    page:SetPoint("TOPLEFT",20,-70);page:SetPoint("TOPRIGHT",-20,-70)
    page.rows={};page.phase=0
    local title=GUI2:CreateText(page,L["overview.tagline"],24,"color.text.primary")
    title:SetPoint("TOP",0,-12);title:SetHeight(36)
    local bar=GUI2:CreatePanel(page,{height=34,surface="color.surface.popup",border="color.border.subtle"})
    bar:SetPoint("TOPLEFT",12,-80);bar:SetPoint("TOPRIGHT",-12,-80);bar:EnableMouse(false)
    local samples={
        L["system.label.fps"].."|cff33ff33144|r  "..L["system.label.latency"].."|cff33ff3318|r  "..L["system.label.tolerance"].."|cffffd100250|r",
        "",
        "7,465|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:2:0|t (|cffffffff36|r)",
        "Lv. 80 (66% |cff00aaff+20%|r)",
    }
    bar.labels={}
    for i,text in ipairs(samples)do
        local label=GUI2:CreateText(bar,text,12,"color.text.primary")
        label:SetPoint("LEFT",bar,"LEFT",0,0);label:SetHeight(24);label:SetWordWrap(false)
        bar.labels[i]=label
    end
    bar.labels[2]:Hide()
    local crestStrip=GUI2:CreateFrame(bar,{height=20})
    crestStrip:EnableMouse(false)
    -- CurrencyTypes 3442-3446: fixed retail icon assets; never read character holdings.
    local crestSamples={
        {7734054,344,"|cffffffff"},{7734062,290,"|cff1eff00"},
        {7734056,22,"|cff0070dd"},{7734058,53,"|cffa335ee"},{7734060,240,"|cffff8000"},
    }
    local crestWidth=0
    for _,sample in ipairs(crestSamples)do
        local slot=YUI.YBar:CreateIconSlot(crestStrip,{size=16,icon=sample[1],padding=0})
        slot:SetPoint("LEFT",crestStrip,"LEFT",crestWidth,0);slot:EnableMouse(false)
        local label=GUI2:CreateText(crestStrip,sample[3]..sample[2].."|r",12,"color.text.primary")
        label:SetPoint("LEFT",slot,"RIGHT",4,0);label:SetWordWrap(false)
        crestWidth=crestWidth+16+4+label:GetStringWidth()+6
    end
    crestWidth=crestWidth-6;crestStrip:SetWidth(crestWidth)
    crestStrip.GetStringWidth=function()return crestWidth end
    bar.labels[2]=crestStrip
    local xpLine=YUI.YBar:CreateMiniProgressLine(bar,{height=2})
    xpLine:SetPoint("TOPLEFT",bar.labels[4],"BOTTOMLEFT",0,1)
    xpLine:SetValues(0.66,0.20);xpLine:EnableMouse(false)
    local viewport=GUI2:CreateFrame(page,{height=142,mouse=true})
    viewport:SetPoint("TOPLEFT",0,-146);viewport:SetPoint("TOPRIGHT",0,-146)
    viewport:SetClipsChildren(true)
    local kinds={"System","SeasonCrests","Currency","Stats","Clock","CurrencyTracker","Talents","MicroMenu",
        "Professions","Teleports","RaidMarkers","Shard","MeetingStone","DurabilityMount","EquipmentSets","BugSack"}
    for rowIndex=1,2 do
        local row=GUI2:CreateFrame(viewport,{height=64})
        row.cards={};page.rows[rowIndex]=row
        for copy=0,1 do
            for i=1,8 do
                local kind=kinds[(rowIndex-1)*8+i]
                local card=GUI2:CreatePanel(row,{height=64,surface="color.surface.popup",border="color.border.subtle"})
                card:EnableMouse(false)
                local icon=GUI2:CreateIcon(card,{icon=L_Icons[kind],size=28,crop=true})
                icon:SetPoint("LEFT",10,0)
                local label=GUI2:CreateText(card,L[MODULE_LABEL_KEYS[kind]],14,"color.text.primary")
                label:SetPoint("LEFT",icon,"RIGHT",8,0);label:SetPoint("RIGHT",-8,0)
                label:SetHeight(40);label:SetWordWrap(true)
                row.cards[#row.cards+1]=card
            end
        end
    end
    local button=GUI2.Form:CreateButton(page,{text=L["overview.design"],width=260,height=36,
        onClick=function()page:StopMotion();YUI:OpenYBarModuleSettings()end})
    button:SetPoint("TOP",0,-350)
    if GUI2.Form.SetButtonRelief then GUI2.Form:SetButtonRelief(button,"hairline")end
    local function paint()
        button:SetBackdropColor(GUI2:GetColor("color.border.accent"))
        GUI2:SetBorderColor(button,"color.border.accent")
    end
    button:HookScript("OnEnter",paint);button:HookScript("OnLeave",paint);paint()
    function page:StopMotion()
        local handle=self.motion;self.motion=nil
        if handle then handle:Cancel()end
        if YUI.Animation then YUI.Animation:StopOwner(self)end
    end
    function page:CanScroll()
        local profile=YUI.YBar and YUI.YBar:GetProfile()
        return self:IsVisible() and self.period and self.period>0 and not self.away
            and not InCombatLockdown() and not viewport:IsMouseOver()
            and (not GUI2.GetMotionStrength or GUI2:GetMotionStrength()~="off")
            and self.profile and self.profile.enable~=false
            and profile and self.profile==profile.YBar
    end
    function page:PlaceRows(value)
        self.phase=value
        -- Preserve fractional motion; integer snapping creates visible slow-speed steps.
        local offset=value*self.period
        if offset==self.lastOffset then return end
        self.lastOffset=offset
        self.rows[1]:SetPoint("TOPLEFT",viewport,"TOPLEFT",-offset,0)
        self.rows[2]:SetPoint("TOPLEFT",viewport,"TOPLEFT",offset-self.period,-78)
    end
    page.updateMotion=function(value)
        if not page:CanScroll()then page:StopMotion();return end
        page:PlaceRows(value)
    end
    page.finishMotion=function(_,_,finished)
        page.motion=nil
        if finished then page.phase=0;page:StartMotion()end
    end
    function page:StartMotion()
        if self.motion or not YUI.Animation or not self:CanScroll()then return end
        self.motion=YUI.Animation:Tween({target=self,owner=self,key="orbit-showcase",from=self.phase,to=1,
            duration=(1-self.phase)*self.period/14,easing="linear",onUpdate=self.updateMotion,onFinished=self.finishMotion})
    end
    function page:Layout()
        self:StopMotion()
        local width=self:GetWidth()
        if width<120 then self.period=nil;return end
        title:SetWordWrap(false);title:SetWidth(width)
        local cell=math.max(130,math.min(190,(width-24)/4.2))
        self.period=8*(cell+10)
        for _,row in ipairs(self.rows)do
            row:SetWidth(self.period*2)
            for i,card in ipairs(row.cards)do
                card:SetWidth(cell);card:SetPoint("TOPLEFT",(i-1)*(cell+10),0)
            end
        end
        local available=math.max(1,width-40)
        local total=0
        for _,label in ipairs(bar.labels)do total=total+label:GetStringWidth()+16 end
        local scale=math.min(1,available/math.max(1,total))
        local x=8
        for _,label in ipairs(bar.labels)do
            label:SetScale(scale);label:ClearAllPoints();label:SetPoint("LEFT",bar,"LEFT",x/scale,0)
            x=x+(label:GetStringWidth()+16)*scale
        end
        xpLine:SetBarWidth(bar.labels[4]:GetStringWidth()*scale)
        self.lastOffset=nil;self:PlaceRows(self.phase);self:StartMotion()
    end
    viewport:SetScript("OnEnter",function()page:StopMotion()end)
    viewport:SetScript("OnLeave",function()page:StartMotion()end)
    page:SetScript("OnSizeChanged",function()page:Layout()end)
    page:SetScript("OnShow",function()
        local profile=YUI.YBar and YUI.YBar:GetProfile()
        page.profile=profile and profile.YBar;page.away=false
        YUI.Event:OffOwner(page)
        YUI.Event:On("PLAYER_REGEN_DISABLED",function()page:StopMotion()end,page)
        YUI.Event:On("PLAYER_REGEN_ENABLED",function()page:StartMotion()end,page)
        YUI.Event:On("PLAYER_LEAVING_WORLD",function()page.away=true;page:StopMotion()end,page)
        YUI.Event:On("PLAYER_ENTERING_WORLD",function()page.away=false;page:StartMotion()end,page)
        YUI.Event:On("PLAYER_LOGOUT",function()page.away=true;page:StopMotion()end,page)
        YUI.Event:On("YUI_MODULE_DISABLED",function()page:StopMotion()end,page)
        page:Layout()
    end)
    page:SetScript("OnHide",function()page:StopMotion();YUI.Event:OffOwner(page)end)
    -- A new child can already be visible before its OnShow handler is installed.
    page:Hide();page:Show()
    parent:SetHeight(510)
end

-- 主渲染函数
local function Render(parent)
    -- 清空父容器
    
    -- Initialize settings buttons table
    if YUI.YBar then
        YUI.YBar.SettingsButtons = {}
    end
    
    local mainTitle = GUI2:CreateText(
        parent,
        CelestialSeries
            and CelestialSeries:GetTitle(
                "ybar",
                L["product.brand_suffix"] or "Info Bar"
            )
            or YBAR_SETTINGS_MODULE_NAME,
        GUI2.Fonts.size_title
    )
    mainTitle:SetPoint(
        "TOPLEFT",
        MODULE_PAGE_LAYOUT.insetX,
        -MODULE_PAGE_LAYOUT.titleTop
    )
    mainTitle:SetFont(GUI2.Fonts.header, GUI2.Fonts.size_title, "OUTLINE")
    SetTextToken(mainTitle, "color.text.heading")

    if S.CreateProductHeaderMinimapButton then
        local minimapButton = S:CreateProductHeaderMinimapButton(parent, "ybar", { size = 24 })
        if minimapButton then
            minimapButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -18)
        end
    end

    if (YUI.IsForever or YUI.IsRetail) and YUI.YBar and YUI.YBar.LayoutDesigner then
        RenderOrbitIntroduction(parent)
        return
    end

    -- 1. 创建左右分栏
    local leftPanel = GUI2:CreateFrame(parent, { template = "BackdropTemplate" })
    leftPanel:SetPoint("TOPLEFT", 10, -60) -- 下移以避开标题
    leftPanel:SetPoint("BOTTOMLEFT", 10, 10)
    leftPanel:SetWidth(140)
    GUI2:CreateBackdrop(leftPanel)
    
    local rightPanel = GUI2:CreateFrame(parent, { template = "BackdropTemplate" })
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", 0, 10)
    GUI2:CreateBackdrop(rightPanel)
    
    -- 2. 左侧菜单
    -- 去掉 UIPanelScrollFrameTemplate 和 SkinScrollBar
    local scrollFrame = GUI2:CreateScrollFrame(leftPanel, { template = false, child = false })
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5) -- 调整右边距，不留滚动条位置
    
    local scrollChild = GUI2:CreateFrame(scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(130, 800) -- 增加高度以避免滚动条
    
    -- 支持鼠标滚轮滚动
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local new = current - (delta * 20)
        if new < 0 then new = 0 end
        local max = self:GetVerticalScrollRange()
        if new > max then new = max end
        self:SetVerticalScroll(new)
    end)
    
    local currentButton = nil
    
    local function LoadRightContent(key, name)
        -- 清空 rightPanel 的子元素
        for _, child in ipairs({rightPanel:GetChildren()}) do
            if child ~= rightPanel.backdrop and child ~= rightPanel.shadow then
                child:Hide()
            end
        end
        
        -- 创建内容容器
        local container = GUI2:CreateFrame(rightPanel)
        container:SetPoint("TOPLEFT", 10, -10)
        container:SetPoint("BOTTOMRIGHT", -10, 10)
        
        -- 右侧标题在各个 Render 函数内部处理，这里不再统一创建
        
        local content = GUI2:CreateFrame(container)
        content:SetPoint("TOPLEFT", 0, 0) -- 调整顶部间距
        content:SetPoint("BOTTOMRIGHT", 0, 0)
        
        if key == "General" then
             RenderGeneralSettings(content)
        elseif key == "ModulePosition" then
             RenderModulePositionSettings(content)
        else
             RenderModuleSettings(content, key)
        end
    end
    
    local yOffset = 0
    local function AddMenuButton(key, name)
        local icon = L_Icons[key] or 134400
        local btn = GUI2:CreateNavButton(scrollChild, name, icon, 130, 30) -- 宽度适配
        btn:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - 32
        
        -- 启用图标
        if btn.icon then 
            btn.icon:Show() 
            btn.icon:SetSize(16, 16)
            btn.icon:SetPoint("LEFT", 10, 0)
        end
        
        if btn.iconBg then 
            -- 如果有背景，也可以显示，这里假设 CreateNavButton 的 iconBg 适配好了
            -- 或者隐藏它只显示图标
            btn.iconBg:Hide() 
        end

        if btn.text then 
            btn.text:ClearAllPoints()
            btn.text:SetPoint("LEFT", 32, 0) -- 调整文字位置
            btn.text:SetPoint("RIGHT", -8, 0)
            btn.text:SetJustifyH("LEFT")
            btn.text:SetWordWrap(false)
            -- 字体大小与整个设置面的导航文本保持一致 (S.Core 中通常是 size_normal)
            btn.text:SetFont(GUI2.Fonts.normal, GUI2.Fonts.size_normal)
        end
        
        btn:SetScript("OnClick", function(self)
             if currentButton then
                 SetNavSelected(currentButton, false)
                 currentButton.isSelected = false
             end
             
             SetNavSelected(self, true)
             self.isSelected = true
             currentButton = self
             
             LoadRightContent(key, name)
        end)
        
        -- 默认选中第一个
        if key == "General" and not currentButton then
            btn:GetScript("OnClick")(btn)
        end
        
        if YUI.YBar and YUI.YBar.SettingsButtons then
            YUI.YBar.SettingsButtons[key] = btn
        end
        
        return btn
    end
    
    -- 填充菜单
    AddMenuButton("General", L["ybar.settings.general"])
    AddMenuButton("ModulePosition", L["ybar.settings.module_position"])
    
    -- 分隔线
    yOffset = yOffset - 5
    local div = GUI2:CreateTexture(scrollChild, { layer = "ARTWORK" })
    div:SetHeight(1)
    SetTextureToken(div, "color.border.subtle")
    div:SetPoint("TOPLEFT", 5, yOffset)
    div:SetPoint("TOPRIGHT", -5, yOffset)
    yOffset = yOffset - 10
    
    -- 子模块
    local modules = GetAllModules(true)
    for _, modName in ipairs(modules) do
        if modName ~= "None" and not modName:find("Broker:", 1, true) then
            local displayName = GetModuleDisplayName(modName)
            -- 去掉可能存在的图标字符串 |T...|t，避免重复显示图标
            local cleanName = displayName:gsub("|T.-|t%s*", "")
            AddMenuButton(modName, cleanName)
        end
    end
    
    scrollChild:SetHeight(math.abs(yOffset) + 20)
    
    -- 强制设置整个 YBar 容器的高度，使其填满可用空间
    parent:SetHeight(510) 
end


S:RegisterModule(YBAR_SETTINGS_MODULE_NAME, YBAR_SETTINGS_ICON, Render, {
    id = "ybar.settings",
    product = "ybar",
    scope = "ybar",
    titleKey = YUI.CoreMode == "suite" and "ybar.title" or nil,
    titleNamespace = YUI.CoreMode == "suite" and "YBar" or nil,
    navTitleKey = "settings.nav.info_bar",
    navIconCrop = false,
    navIconSize = CelestialSeries and CelestialSeries.NAV_ICON_SIZE or 26,
    navToggle = YUI.CoreMode == "suite" and { moduleId = "ybar" } or nil,
})

function YUI:OpenYBarModuleSettings(moduleName)
    local bridge=(YUI.IsForever or YUI.IsRetail) and self.YBar and self.YBar.LayoutDesigner
    if bridge then
        local ok,reason
        if moduleName then ok,reason=bridge:OpenModuleSettings(moduleName)
        else ok,reason=bridge:OpenDesigner()end
        if not ok then self:Print(L["designer.save_failed"].." · "..tostring(reason)) end
        return
    end
    local ybarModule = S:OpenProduct("ybar", "ybar.settings")
    
    if ybarModule then
        S:SelectModule(ybarModule)
        
        -- 3. Select the specific sub-module
        -- Give a small delay for Render to complete if it was just created
        C_Timer.After(0.1, function()
            if YUI.YBar and YUI.YBar.SettingsButtons then
                local btn = YUI.YBar.SettingsButtons[moduleName]
                if btn and btn:IsEnabled() then
                    btn:Click()
                end
            end
        end)
    end
end

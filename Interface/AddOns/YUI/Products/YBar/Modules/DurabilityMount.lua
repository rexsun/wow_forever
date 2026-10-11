local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("DurabilityMount") end
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
local YBar = YUI.YBar
local GUI2 = YUI.GUI2
local LegacyAPI = YUI.WOW_API
local ItemAPI = YUI.API and YUI.API.Item or LegacyAPI
local SpellAPI = YUI.API and YUI.API.Spell or LegacyAPI
local SecurityAPI = YUI.API and YUI.API.Security or LegacyAPI
local Module = YBar.Module:New("DurabilityMount")
local L = YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")
local AutoRepair = YUI.AutoRepair

-- 缓存全局变量
local pairs, ipairs = pairs, ipairs
local format = string.format
local floor = math.floor
local GetRepairAllCost = GetRepairAllCost
local GetMoneyString = GetMoneyString
local GetAverageItemLevel = GetAverageItemLevel
local BreakUpLargeNumbers = BreakUpLargeNumbers
local C_TooltipInfo = C_TooltipInfo
local C_MountJournal = C_MountJournal

-- 常量
local SLOTS = {
    1,  -- Head
    3,  -- Shoulder
    5,  -- Chest
    6,  -- Waist
    7,  -- Legs
    8,  -- Feet
    9,  -- Wrist
    10, -- Hands
    16, -- MainHand
    17, -- OffHand
    18, -- Ranged
}

local MOUNT_LIST = {
    { id = 2237 }, -- 灰熊丘陵魁熊
    { id = 460 }, -- 雄壮远足牦牛
    { id = 284, id2 = 280 }, -- 旅行者的苔原猛犸象
    { id = 1039 , isGold = true }, -- 雄壮商队雷龙
    { id = 2265 , isGold = true }, -- 鎏金雷龙
    { id = 2647 , isGold = true }, -- 烬灭灾变者
    { id = 2947 , isGold = true }, -- 金色烬灭灾变者
    { id = 2943 , isGold = true }, -- 苍雷踏云
    { id = 2982, isGold = true }, -- 营炉者的流浪大篷车
    { id = 2981, isGold = true }, -- 霜壳行者·碧蓝林海的巨壳伙伴
}

-- 默认值
local DEFAULT_SIZE = 14
local DEFAULT_ICON_SIZE = DEFAULT_SIZE + 2
local DEFAULT_FONT = STANDARD_TEXT_FONT
local DEFAULT_MOUNT_LEFT = 460
local DEFAULT_MOUNT_RIGHT = 2265
local DEFAULT_MOUNT_MIDDLE = 2981
local DEFAULT_DISPLAY_MODE = "lowest"
local AUTO_REPAIR_MODE_GUILD = "guild"
local AUTO_REPAIR_MODE_PERSONAL = "personal"

-- 时光服覆盖
if YUI.IsWrath then
    DEFAULT_MOUNT_LEFT = 284
    DEFAULT_MOUNT_RIGHT = 2647
end

local DISPLAY_MODE_KEYS = {
    lowest = "durability.display.lowest",
    average = "durability.display.average",
    average_lowest = "durability.display.average_lowest",
}

local function GetDisplayModeText(mode)
    return L[DISPLAY_MODE_KEYS[mode] or DISPLAY_MODE_KEYS.lowest]
end

local function GetAutoRepairModeText(mode)
    return AutoRepair:GetModeText(mode)
end

local function EnsureModuleDB(self)
    local ybarDB = GetYBarDB()
    if type(ybarDB) ~= "table" then
        return nil
    end

    if type(ybarDB.DurabilityMount) ~= "table" then
        ybarDB.DurabilityMount = {}
    end

    local db = ybarDB.DurabilityMount
    if db.font == nil then db.font = DEFAULT_FONT end
    if db.size == nil then db.size = DEFAULT_SIZE end
    if db.showIcon == nil then db.showIcon = true end
    if db.displayMode == nil then db.displayMode = DEFAULT_DISPLAY_MODE end
    if db.mountLeft == nil then db.mountLeft = DEFAULT_MOUNT_LEFT end
    if db.mountRight == nil then db.mountRight = DEFAULT_MOUNT_RIGHT end
    if db.mountMiddle == nil then db.mountMiddle = DEFAULT_MOUNT_MIDDLE end

    self.db = db
    return db
end

local function IsAutoRepairFeatureAvailable()
    return AutoRepair and AutoRepair:IsAvailable()
end

local function IsDurabilityFrameReady(frame)
    return frame and not frame.ybarErrorPlaceholder and not frame.errorText and
        frame.text and (frame.iconSlot or frame.icon)
end

-- 辅助函数：耐久度颜色
local function GetDurabilityColor(percent)
    if percent < 30 then
        return 1, 0.2, 0.2
    elseif percent < 60 then
        return 1, 0.8, 0.2
    end
    return 1, 1, 1
end

-- 辅助函数：格式化带颜色的百分比
local function FormatColoredPercent(percent)
    local r, g, b = GetDurabilityColor(percent)
    return format("|cff%02x%02x%02x%d%%|r", r * 255, g * 255, b * 255, floor(percent))
end

-- 辅助函数：格式化金币
local function FormatMoney(amount)
    local gold = floor(amount / 10000)
    local silver = floor(math.fmod(amount / 100, 100))
    local copper = floor(math.fmod(amount, 100))
    
    local str = ""
    if gold > 0 then
        str = format("%s|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:2:0|t", BreakUpLargeNumbers(gold))
    end
    if gold < 100 and silver > 0 then
        str = str .. " " .. format("%d|TInterface\\MoneyFrame\\UI-SilverIcon:11:11:2:0|t", silver)
    end
    if gold == 0 and silver == 0 then
        str = str .. " " .. format("%d|TInterface\\MoneyFrame\\UI-CopperIcon:11:11:2:0|t", copper)
    end
    return str
end

-- 辅助函数：获取物品等级
local function GetItemLevel(link)
    if not link then return 0 end
    return ItemAPI.GetLevel(link)
end

-- 辅助函数：获取已装备物品修理费用
local function GetEquippedRepairCost()
    local totalCost = 0
    local scanTooltip = YUI.ScanTooltip
    if not scanTooltip then
        -- GameTooltip scanner must use the native tooltip template.
        scanTooltip = CreateFrame("GameTooltip", "YUI_ScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        YUI.ScanTooltip = scanTooltip
    end

    for _, slot in ipairs(SLOTS) do
        local hasItem = ItemAPI.GetInventoryItemLink("player", slot)
        if hasItem then
            local repairCost = 0
            if YUI.IsRetail and C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
                 local data = C_TooltipInfo.GetInventoryItem("player", slot)
                 if data then
                     repairCost = data.repairCost or 0
                 end
            else
                 scanTooltip:ClearLines()
                 local _, _, repairCostVal = scanTooltip:SetInventoryItem("player", slot)
                 repairCost = tonumber(repairCostVal) or 0
            end
            totalCost = totalCost + repairCost
        end
    end
    return totalCost
end

-- 辅助函数：检查法术/坐骑是否已知
local function IsMountKnown(spellID)
    return SpellAPI.IsKnown(spellID)
end

-- 辅助函数：获取坐骑信息
local function GetMountInfo(mountID)
    local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
    return name, icon
end

local function GetMountMacroText(mountID)
    local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
    if spellID then
        local name = SpellAPI.GetName(spellID)
        if name then
            return "/cast " .. name
        end
        return "/cast " .. mountID
    end
    return nil
end

function Module:OnInitialize()
    -- 初始化数据库
    if not EnsureModuleDB(self) then return end
    
    self.avgDurability = 0
end

local function DurabilityMountOnEvent(event)
    if Module._hasError or not IsDurabilityFrameReady(Module.frame) then
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if Module.needsUpdate then
            Module.needsUpdate = false
            Module:UpdateBarItem(Module.frame)
        end
        return
    end

    if event == "YUI_AUTO_REPAIR_CHANGED" and GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner and (owner == Module.secure or owner == Module.frame) then
            Module:OnEnter(owner)
        end
    end
    Module:UpdateBarItem(Module.frame)
end

function Module:AttachRuntime()
    if self._hasError or not self.secure or not IsDurabilityFrameReady(self.frame) then return end

    YUI.Event:OffOwner(self)
    YUI.Event:On("UPDATE_INVENTORY_DURABILITY", DurabilityMountOnEvent, self)
    YUI.Event:On("PLAYER_EQUIPMENT_CHANGED", DurabilityMountOnEvent, self)
    YUI.Event:On("YUI_WORLD_READY", DurabilityMountOnEvent, self)
    YUI.Event:On("MERCHANT_SHOW", DurabilityMountOnEvent, self)
    YUI.Event:On("YUI_AUTO_REPAIR_CHANGED", DurabilityMountOnEvent, self)
    YUI.Event:On("PLAYER_REGEN_ENABLED", DurabilityMountOnEvent, self)

    self:UpdateBarItem(self.frame, self.parent)
end

function Module:DetachRuntime()
    YUI.Event:OffOwner(self)

    self.needsUpdate = false

    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner and (owner == self.secure or owner == self.frame) then
            YUI.HideGameTooltip()
        end
    end

    if self.frame then
        self.frame:Hide()
    end
end

local function GetAutoRepairModeColor(mode)
    if mode == AUTO_REPAIR_MODE_GUILD then
        return 0.2, 1, 0.2
    elseif mode == AUTO_REPAIR_MODE_PERSONAL then
        return 1, 1, 1
    end
    return 1, 0.2, 0.2
end

function Module:ToggleAutoRepair(anchor)
    if not IsAutoRepairFeatureAvailable() then return end
    if not EnsureModuleDB(self) then return end

    AutoRepair:ToggleMode()

    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner and (owner == anchor or owner == self.secure or owner == self.frame) then
            self:OnEnter(owner)
        end
    end
end

function Module:CreateBarItem(parent)
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        showIcon = false,
        hoverIcon = false,
        text = false,
        value = false,
    })
    
    -- 安全按钮
    local secure = YBar:CreateActionHost(frame, {
        onEnter = function(host, owner)
            if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(owner) end
            Module:OnEnter(host)
            YBar:SetThemedTextAccent(owner.text)
        end,
        onLeave = function(_, owner)
            if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(owner) end
            YUI.HideGameTooltip()
            YBar:RestoreThemedTextColor(owner.text, "color.ybar.text")
        end,
    })
    
    frame.iconSlot, frame.icon = YBar:CreateIconSlot(frame, {
        size = DEFAULT_ICON_SIZE,
        icon = "Interface\\Icons\\Trade_BlackSmithing",
        shape = "square",
        padding = 0,
    })
    if frame.iconSlot then
        frame.iconSlot:SetPoint("LEFT", frame, "LEFT", 0, 0)
    else
        frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    end

    frame.statusText, frame.text = YBar:CreateStatusText(frame, {
        variant = "single",
        value = "",
        width = 40,
        height = 20,
        justifyH = "LEFT",
        colorKey = "color.ybar.text",
    })
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", 4, 0)
    YBar:RegisterBarItemHoverText(frame, frame.text)

    self.secure = secure
    self.frame = frame
    
    -- 事件脚本
    -- Events are attached by the lifecycle runtime.
    
    -- 初始更新
    self:UpdateBarItem(frame, parent)

    if YBar and YBar.IsSubModuleEnabled and YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end
    
    return frame
end

function Module:UpdateBarItem(frame, parent, totalCurrent, totalMax, lowest)
    if parent then self.parent = parent end
    if not frame then frame = self.frame end
    if self._hasError or not IsDurabilityFrameReady(frame) then return end
    
    if not EnsureModuleDB(self) then return end

    local db = self.db
    local font = YBar:ResolveFontPath(db.font, DEFAULT_FONT)
    local size = db.size or DEFAULT_SIZE
    
    if frame.iconSlot then
        frame.iconSlot:SetSize(size + 2, size + 2)
    else
        frame.icon:SetSize(size + 2, size + 2)
    end
    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")
    
    frame.text:SetFont(font, size, fontFlag)
    
    if globalDB.fontShadow then
        frame.text:SetShadowColor(0, 0, 0, 1)
        frame.text:SetShadowOffset(1, -1)
    else
        frame.text:SetShadowOffset(0, 0)
    end
    
    -- 计算耐久度
    -- 悬停时复用提示框已经读取的耐久，不再扫描一遍装备。
    if totalMax == nil then
        totalCurrent, totalMax, lowest = 0, 0, 100
        for _, slot in ipairs(SLOTS) do
            local current, max = ItemAPI.GetInventoryItemDurability(slot)
            if current and max and max > 0 then
                totalCurrent = totalCurrent + current
                totalMax = totalMax + max
                local perc = (current / max) * 100
                if perc < lowest then lowest = perc end
            end
        end
    end
    self.totalCurrent, self.totalMax, self.lowestDurability = totalCurrent, totalMax, lowest
    
    local avg
    if totalMax > 0 then
        avg = (totalCurrent / totalMax) * 100
    end
    self.avgDurability = avg

    local displayMode = db.displayMode or DEFAULT_DISPLAY_MODE
    local displayPercent = avg
    local textStr

    if totalMax == 0 then
        textStr = "--"
    elseif displayMode == "lowest" then
        displayPercent = lowest
        textStr = FormatColoredPercent(lowest)
    elseif displayMode == "average_lowest" then
        textStr = FormatColoredPercent(avg) .. " " .. FormatColoredPercent(lowest)
        displayPercent = avg
    else
        textStr = FormatColoredPercent(avg)
    end

    -- 根据当前显示模式着色
    local r, g, b = 1, 1, 1
    if displayPercent and displayMode ~= "average_lowest" then
        r, g, b = GetDurabilityColor(displayPercent)
    end
    
    frame.text:SetText(textStr)
    frame.text:SetTextColor(r, g, b)
    
    -- 图标可见性
    if db.showIcon then
        if frame.iconSlot then
            frame.iconSlot:Show()
        else
            frame.icon:Show()
        end
        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", 4, 0)
    else
        if frame.iconSlot then
            frame.iconSlot:Hide()
        else
            frame.icon:Hide()
        end
        frame.text:ClearAllPoints()
        frame.text:SetPoint("LEFT", frame, "LEFT", 2, 0)
    end
    
    -- 更新安全按钮属性（仅非战斗状态）
    if not SecurityAPI.InCombatLockdown() then
        local mountLeft = db.mountLeft or DEFAULT_MOUNT_LEFT
        local mountMiddle = db.mountMiddle or DEFAULT_MOUNT_MIDDLE
        local mountRight = db.mountRight or DEFAULT_MOUNT_RIGHT
        local actions = {
            altLeft = {
                kind = "custom",
                onClick = function()
                    YUI:OpenYBarModuleSettings("DurabilityMount")
                end,
            },
        }

        if IsAutoRepairFeatureAvailable() then
            actions.shiftLeft = {
                kind = "custom",
                onClick = function(host)
                    Module:ToggleAutoRepair(host)
                end,
            }
        end
        
        -- 使用宏类型以支持灵活施法
        local leftMacro = GetMountMacroText(mountLeft)
        if leftMacro then
            actions.left = { kind = "macro", macrotext = leftMacro }
        else
            actions.left = { kind = "noop" }
        end
        
        local middleMacro = GetMountMacroText(mountMiddle)
        if middleMacro then
            actions.middle = { kind = "macro", macrotext = middleMacro }
        else
            actions.middle = { kind = "noop" }
        end

        local rightMacro = GetMountMacroText(mountRight)
        if rightMacro then
            actions.right = { kind = "macro", macrotext = rightMacro }
        else
            actions.right = { kind = "noop" }
        end

        if self.secure and self.secure.SetActions then
            local ok = self.secure:SetActions(actions)
            if not ok then
                self.needsUpdate = true
            end
        end
    else
        self.needsUpdate = true
    end
    
    -- 计算宽度
    local width = 0
    if db.showIcon then
        width = width + (size + 2) + 4
    end
    local textWidth = frame.text:GetStringWidth() or 0
    width = width + textWidth + 2
    
    local oldWidth = self.width
    self.width = width
    
    if not SecurityAPI.InCombatLockdown() then
        frame:SetWidth(width)
    else
        self.needsUpdate = true
    end
    
    if not parent and oldWidth and math.abs(width - oldWidth) > 1 then
        if YBar and YBar.UpdateLayout then
            YBar:UpdateLayout()
        end
    end
end

function Module:Update()
    if self._hasError or not IsDurabilityFrameReady(self.frame) then return end
    self:UpdateBarItem()
end

function Module:GetWidth()
    if self._hasError or not IsDurabilityFrameReady(self.frame) then return 50 end
    return self.width or 50
end

function Module:OnEnter(frame)
    if self._hasError or not IsDurabilityFrameReady(self.frame) then return end
    local tooltipAnchor = "ANCHOR_TOP"
    local bar = self.parent
    if bar and bar:GetBottom() > GetScreenHeight() / 2 then
        tooltipAnchor = "ANCHOR_BOTTOM"
    end
    
    GameTooltip:SetOwner(frame, tooltipAnchor)
    GameTooltip:ClearLines()
    
    GameTooltip:AddLine(L["durability.tooltip.title"])
    GameTooltip:AddLine(" ")
    
    -- 装备列表
    local totalCurrent, totalMax, lowest = 0, 0, 100
    for _, slot in ipairs(SLOTS) do
        local current, max = ItemAPI.GetInventoryItemDurability(slot)
        if current and max and max > 0 then
            local perc = (current / max) * 100
            totalCurrent = totalCurrent + current
            totalMax = totalMax + max
            if perc < lowest then lowest = perc end
            local link = ItemAPI.GetInventoryItemLink("player", slot)
            local texture = ItemAPI.GetInventoryItemTexture("player", slot)
            
            if link then
                local name = ItemAPI.GetName(link)
                local ilvl = GetItemLevel(link)
                local quality = ItemAPI.GetInventoryItemQuality("player", slot)
                local r, g, b = 1, 1, 1
                if quality then
                    r, g, b = ItemAPI.GetQualityColor(quality)
                end
                
                -- 格式：图标 名称 等级 ... 耐久度
                local iconStr = format("|T%s:14:14:0:0:64:64:4:60:4:60|t", texture)
                local leftText = format("%s |cff%02x%02x%02x%s|r |cffAAAAAA(%d)|r", iconStr, r*255, g*255, b*255, name or "Unknown", ilvl)
                
                -- 耐久度百分比着色
                local dr, dg, db = 0, 1, 0
                if perc < 30 then
                    dr, dg, db = 1, 0.2, 0.2
                elseif perc < 60 then
                    dr, dg, db = 1, 0.8, 0.2
                end
                
                local rightText = format("|cff%02x%02x%02x%d%%|r", dr*255, dg*255, db*255, floor(perc))
                
                GameTooltip:AddDoubleLine(leftText, rightText)
            end
        end
    end

    -- 两处显示使用同一次读数；数值未变化时不重设字体、坐骑动作或布局。
    if totalCurrent ~= self.totalCurrent or totalMax ~= self.totalMax or lowest ~= self.lowestDurability then
        self:UpdateBarItem(self.frame, nil, totalCurrent, totalMax, lowest)
    end
    
    GameTooltip:AddLine(" ")
    
    -- 修理费用
    local cost = GetEquippedRepairCost()
    
    if cost > 0 then
        GameTooltip:AddDoubleLine(L["durability.tooltip.repair_cost"], FormatMoney(cost), 1, 1, 1, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine(L["durability.tooltip.repair_cost"], L["durability.tooltip.no_repair"], 1, 1, 1, 0.5, 0.5, 0.5)
    end

    if IsAutoRepairFeatureAvailable() then
        local mode = AutoRepair:GetMode()
        local sr, sg, sb = GetAutoRepairModeColor(mode)
        GameTooltip:AddDoubleLine(L["durability.tooltip.auto_repair"], GetAutoRepairModeText(mode), 1, 1, 1, sr, sg, sb)
    end
    
    GameTooltip:AddLine(" ")
    
    -- 坐骑信息
    local mountLeft = self.db.mountLeft or DEFAULT_MOUNT_LEFT
    local nameLeft, iconLeft = GetMountInfo(mountLeft)
    if not nameLeft then nameLeft = L["durability.fallback.mount_left"] end
    local iconStrLeft = ""
    if iconLeft then
        iconStrLeft = format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", iconLeft)
    end
    
    local mountMiddle = self.db.mountMiddle or DEFAULT_MOUNT_MIDDLE
    local nameMiddle, iconMiddle = GetMountInfo(mountMiddle)
    if not nameMiddle then nameMiddle = L["durability.fallback.mount_middle"] end
    local iconStrMiddle = ""
    if iconMiddle then
        iconStrMiddle = format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", iconMiddle)
    end

    local mountRight = self.db.mountRight or DEFAULT_MOUNT_RIGHT
    local nameRight, iconRight = GetMountInfo(mountRight)
    if not nameRight then nameRight = L["durability.fallback.mount_right"] end
    local iconStrRight = ""
    if iconRight then
        iconStrRight = format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", iconRight)
    end

    GameTooltip:AddLine(format("|cffFFFFFF%s:|r %s %s%s", LC["common.left_click"], L["durability.action.summon"], iconStrLeft, nameLeft))
    GameTooltip:AddLine(format("|cffFFFFFF%s:|r %s %s%s", L["durability.input.middle_click"], L["durability.action.summon"], iconStrMiddle, nameMiddle))
    GameTooltip:AddLine(format("|cffFFFFFF%s:|r %s %s%s", LC["common.right_click"], L["durability.action.summon"], iconStrRight, nameRight))
    if IsAutoRepairFeatureAvailable() then
        GameTooltip:AddLine(format("|cffFFFFFF%s:|r %s", LC["common.shift_left_click"], L["durability.action.toggle_auto_repair"]))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
    
    GameTooltip:Show()
end

function Module:GetOptions()
    local S = YUI.Settings
    local LSM = LibStub("LibSharedMedia-3.0")
    
    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFont = nil
    for name, path in pairs(fontList) do
        table.insert(fontOptions, { text = name, value = path })
        if name == "默认" then defaultFont = path end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    -- 构建坐骑选项列表
    local mountOptions = {}
    for _, mount in ipairs(MOUNT_LIST) do
        local mountID = mount.id
        local name, _, icon, _, isUsable = C_MountJournal.GetMountInfoByID(mountID)

        if not isUsable and mount.id2 then
            name, _, _, _, isUsable = C_MountJournal.GetMountInfoByID(mount.id2)
        end

        if name ~= nil then
            local texture = icon
            local color = isUsable and "|cffffffff" or "|cff808080"

            if mount.isGold and isUsable then
                name = YUI.F:GetGradientText(name, {r=1, g=1, b=0}, {r=1, g=0.27, b=0})
            end

            if texture then
                texture = format("|T%s:16:16:0:0:64:64:4:60:4:60|t ", texture)
            else
                texture = ""
            end

            table.insert(mountOptions, {
                text = format("%s%s%s|r", texture, color, name),
                value = mountID
            })
        end        
    end

    local options = {
        {
            type = "dropdown",
            label = LC["common.font"],
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function() return self.db.font or defaultFont end,
            set = function(val)
                self.db.font = val
                self:Update()
            end
        },
        {
            type = "slider",
            label = LC["common.size"],
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return self.db.size or DEFAULT_SIZE end,
            set = function(val)
                self.db.size = val
                self:Update()
            end
        },
        {
            type = "checkbox",
            label = LC["common.show_icon"],
            default = true,
            get = function() return self.db.showIcon end,
            set = function(val) 
                self.db.showIcon = val
                self:Update()
            end
        },
        {
            type = "dropdown",
            label = LC["common.display_mode"],
            width = 220,
            default = DEFAULT_DISPLAY_MODE,
            options = {
                { text = GetDisplayModeText("lowest"), value = "lowest" },
                { text = GetDisplayModeText("average"), value = "average" },
                { text = GetDisplayModeText("average_lowest"), value = "average_lowest" },
            },
            get = function() return self.db.displayMode or DEFAULT_DISPLAY_MODE end,
            set = function(val)
                self.db.displayMode = val
                self:Update()
            end
        },
        {
            type = "dropdown",
            label = L["durability.option.left_mount"],
            width = 220,
            default = DEFAULT_MOUNT_LEFT,
            options = mountOptions,
            get = function() return self.db.mountLeft end,
            set = function(val)
                self.db.mountLeft = val
                self:Update()
            end
        },
        {
            type = "dropdown",
            label = L["durability.option.middle_mount"],
            width = 220,
            default = DEFAULT_MOUNT_MIDDLE,
            options = mountOptions,
            get = function() return self.db.mountMiddle end,
            set = function(val)
                self.db.mountMiddle = val
                self:Update()
            end
        },
        {
            type = "dropdown",
            label = L["durability.option.right_mount"],
            width = 220,
            default = DEFAULT_MOUNT_RIGHT,
            options = mountOptions,
            get = function() return self.db.mountRight end,
            set = function(val)
                self.db.mountRight = val
                self:Update()
            end
        },
    }
    local repairOptions = AutoRepair:GetOptions(600)
    for i = 1, #repairOptions do options[#options + 1] = repairOptions[i] end
    return options
end

YBar:RegisterModule(Module, {
    id = "ybar.durabilitymount",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api", "core.locale"},
    defaultEnabled = true,
})

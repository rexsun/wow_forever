local ADDON_NAME, YUI = ...
local LC = YUI.Locale:Get("Core")
local Components = YUI.Components

-- 如果 ElvUI 未加载，则不注册此功能
if not _G.ElvUI then return end

local defaults = {
    disablePetFrame = true,
    tooltip_itemLevel = false,
    hideSellPrice = false,
    roleIcon = true,
}

local function EnsureDB()
    if Components and Components.EnsureConfig then
        local store = Components.GetStore and Components:GetStore()
        local legacyRoleIcon = store and store.RoleIcon
        local db = Components:EnsureConfig("ElvUIAdapter_Config", defaults) or defaults
        if YUI.IsRetail and db._roleIconMigrated ~= true then
            if legacyRoleIcon ~= nil then
                db.roleIcon = legacyRoleIcon == true
            end
            db._roleIconMigrated = true
        end
        return db
    end
    return defaults
end

local function GetDB()
    return EnsureDB()
end

local function IsFeatureEnabled()
    return Components and Components.IsEnabled and Components:IsEnabled("ElvUIAdapter")
end

local roleE, roleUF
local roleIconHooked = false
local roleIconEnabled = false
local ROLE_ATLAS = {
    TANK = "UI-LFG-RoleIcon-Tank-Micro-Raid",
    HEALER = "UI-LFG-RoleIcon-Healer-Micro-Raid",
    DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-Raid",
}

local function EnsureRoleIconContext()
    if not YUI.IsRetail or not _G.ElvUI then
        return nil
    end

    if not roleE then
        roleE = unpack(_G.ElvUI)
    end
    if roleE and not roleUF and roleE.GetModule then
        roleUF = roleE:GetModule("UnitFrames")
    end
    return roleUF
end

local function UpdateRoleIconHook(frame)
    if not roleIconEnabled or not roleUF or not frame then return end

    local lfdrole = frame.GroupRoleIndicator
    if lfdrole and lfdrole:IsShown() then
        local role = roleUF:GetRoleIcon(frame)
        if role and ROLE_ATLAS[role] then
            lfdrole:SetAtlas(ROLE_ATLAS[role])
            lfdrole:SetTexCoord(0, 1, 0, 1)
        end
    end
end

local function RefreshRoleIcons()
    if not roleE or not roleUF or not roleE.oUF or not roleE.oUF.objects then
        return
    end

    for key, value in pairs(roleE.oUF.objects) do
        local frame = value
        if type(key) == "table" then
            frame = key
        end

        if type(frame) == "table" and frame.GroupRoleIndicator then
            local lfdrole = frame.GroupRoleIndicator
            if lfdrole.Override then
                lfdrole.Override = roleUF.UpdateRoleIcon
            end
            roleUF.UpdateRoleIcon(frame)
        end
    end
end

local function UpdateRoleIconState()
    if not YUI.IsRetail then return end

    local db = GetDB()
    roleIconEnabled = IsFeatureEnabled() and db.roleIcon == true

    local uf = EnsureRoleIconContext()
    if not uf then return end

    if not roleIconHooked then
        hooksecurefunc(uf, "UpdateRoleIcon", UpdateRoleIconHook)
        roleIconHooked = true
    end
    RefreshRoleIcons()
end

local function CheckAndDisablePetFrame()
    -- 仅限正式服
    if not YUI.IsRetail then return end
    
    -- 再次检查功能是否开启
    if not IsFeatureEnabled() then return end

    local db = GetDB()
    if not db.disablePetFrame then return end

    if InCombatLockdown() then return end
    
    -- 仅当 PetFrame 存在且可见时才处理
    C_Timer.After(0.1, function()
        if PetFrame and PetFrame:IsShown() then
            PetFrame:Hide()
            PetFrame:UnregisterAllEvents()
            
            -- 可选：将其父对象设置为隐藏帧，防止再次被显示
            if YUI.HiddenFrame then
                PetFrame:SetParent(YUI.HiddenFrame)
            end
            
            YUI:Debug("Components | ElvUI适配 | 已禁用原生宠物框体")
        end
    end)
end

-- 注册 EventRegistry 回调 (如果支持)
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Exit", CheckAndDisablePetFrame)
else
    -- 回退方案：监听 EditModeManagerFrame 的 OnHide
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", CheckAndDisablePetFrame)
    end
end

-- ==========================================
-- 自定义 ElvUI 标签注册
-- ==========================================
local function RegisterCustomTags()
    local E = _G.ElvUI[1]

    -- 获取当前版本最高等级 (兼容各版本)
    local function GetMaxLevel()
        if GetMaxPlayerLevel then
            return GetMaxPlayerLevel()
        elseif MAX_PLAYER_LEVEL_TABLE and GetExpansionLevel then
            return MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()] or 80
        end
        return 80
    end

    -- [yui:level] 等级标签
    E:AddTag("yui:level", "UNIT_LEVEL PLAYER_LEVEL_UP", function(unit)
        local level = UnitLevel(unit)
        local maxLevel = GetMaxLevel()

        -- 满级不显示
        if level >= maxLevel then return nil end

        -- 处理未知或首领等级
        if level == -1 or not level or level == "" then level = "??" end

        return " · " .. tostring(level)
    end)

    -- [yui:level:difficulty] 难度颜色等级标签
    E:AddTag("yui:level:difficulty", "UNIT_LEVEL PLAYER_LEVEL_UP", function(unit)
        local level = UnitLevel(unit)

        -- 处理未知或首领等级
        if level == -1 or not level or level == "" then 
            return " · |A:DungeonSkull:16:16|a"
        end

        local color = GetCreatureDifficultyColor(level)
        local hex = E:RGBToHex(color.r, color.g, color.b)

        return string.format(" · %s%s|r", hex, level)
    end)

    -- [yui:level:difficulty:r] 难度颜色等级标签 (反向)
    E:AddTag("yui:level:difficulty:r", "UNIT_LEVEL PLAYER_LEVEL_UP", function(unit)
        local level = UnitLevel(unit)

        -- 处理未知或首领等级
        if level == -1 or not level or level == "" then 
            return "|A:DungeonSkull:16:16|a · "
        end

        local color = GetCreatureDifficultyColor(level)
        local hex = E:RGBToHex(color.r, color.g, color.b)

        return string.format("%s%s|r · ", hex, level)
    end)

    local function GetFormattedHealthPercent(min, max)
        local healthPercent = (min / max) * 100
        if healthPercent == 0 or healthPercent >= 100 then return "", healthPercent end

        local intPercent
        if healthPercent > 99 then
            intPercent = 99
        elseif healthPercent < 1 then
            intPercent = 1
        else
            intPercent = math.floor(healthPercent + 0.5)
        end

        return tostring(intPercent), healthPercent
    end

    -- [yui:health:percent] 血量百分比标签 (根据阈值变色)
    local function HealthPercentTag(unit)
        local min, max = UnitHealth(unit), UnitHealthMax(unit)
        if not min or not max or max == 0 then return "" end

        local healthStr, healthPercent = GetFormattedHealthPercent(min, max)
        if healthStr == "" then return "" end

        -- 颜色阈值逻辑 (黄/红警告)
        if healthPercent <= 30 then
            -- 红色 (#C41F3B，近似DK职业色)
            return string.format("|cffC41F3B%s|r", healthStr)
        elseif healthPercent <= 70 then
            -- 黄色 (#FFF569，近似盗贼职业色)
            return string.format("|cffFFF569%s|r", healthStr)
        else
            return healthStr
        end
    end

    E:AddTag("yui:health:percent", "UNIT_HEALTH PLAYER_TARGET_CHANGED UNIT_FACTION UNIT_MAXHEALTH", HealthPercentTag)

    -- [yui:health:percent:nosign] 血量百分比标签 (无变色)
    local function HealthPercentNoSignTag(unit)
        local min, max = UnitHealth(unit), UnitHealthMax(unit)
        if not min or not max or max == 0 then return "" end

        local healthStr = GetFormattedHealthPercent(min, max)
        return healthStr
    end
    E:AddTag("yui:health:percent:nosign", "UNIT_HEALTH PLAYER_TARGET_CHANGED UNIT_FACTION UNIT_MAXHEALTH", HealthPercentNoSignTag)

    -- [yui:raidmarker] 团队目标标记标签
    E:AddTag("yui:raidmarker", "RAID_TARGET_UPDATE", function(unit)
        local index = _G.GetRaidTargetIndex(unit)
        if index then
            return "|TINTERFACE\\TARGETINGFRAME\\UI-RaidTargetingIcon_"..index..".blp:0:0:0:0|t"
        end
        return ""
    end)
end

-- 立即注册自定义标签（避开 ElvUI 在 PLAYER_LOGIN 时的刷新 Bug）
RegisterCustomTags()

local function UpdateItemLevelTooltipHooks()
    if not YUI.IsWrath then return end

    local tooltipList = {
        _G.GameTooltip,
        _G.ItemRefTooltip,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
    }

    local tooltipSet = {}
    for _, tt in ipairs(tooltipList) do
        if tt then tooltipSet[tt] = true end
    end

    local function ClearState(tt)
        if not tt then return end
        tt._yuiTooltipDataItemLink = nil
        tt._yuiTooltipDataItemID = nil
        tt._yuiItemLevelRetryCount = nil
    end
    local function HookTooltip(tt)
        if not tt or tt._yuiItemLevelHooked then return end
        tt._yuiItemLevelHooked = true
        tt:HookScript("OnHide", ClearState)
        if tt.HookScript then
            tt:HookScript("OnTooltipCleared", ClearState)
        end
    end

    for _, tt in ipairs(tooltipList) do
        HookTooltip(tt)
    end

    local function GetEnabledDB()
        local db = GetDB()
        if not (IsFeatureEnabled() and db.tooltip_itemLevel) then
            return nil
        end
        return db
    end

    local hasTooltipDataProcessor = _G.TooltipDataProcessor
        and _G.Enum
        and _G.Enum.TooltipDataType
        and _G.Enum.TooltipDataType.Item
        and _G.Enum.TooltipDataLineType
        and _G.TooltipDataProcessor.AddTooltipPreCall
        and _G.TooltipDataProcessor.AddLinePreCall

    if hasTooltipDataProcessor and not _G.TooltipDataProcessor._yuiElvUIAdapterTooltipHooked then
        _G.TooltipDataProcessor._yuiElvUIAdapterTooltipHooked = true

        _G.TooltipDataProcessor:AddTooltipPreCall(_G.Enum.TooltipDataType.Item, function(tt, tooltipData)
            if not tooltipSet[tt] then return end
            local db = GetEnabledDB()
            if not db then return ClearState(tt) end
            ClearState(tt)
            if type(tooltipData) == "table" then
                tt._yuiTooltipDataItemLink = tooltipData.hyperlink or tooltipData.link or tooltipData.itemLink
                tt._yuiTooltipDataItemID = tooltipData.id
            end
        end)

        _G.TooltipDataProcessor:AddLinePreCall(_G.Enum.TooltipDataLineType.SellPrice, function(tt, lineData)
            if not tooltipSet[tt] then return end
            local db = GetEnabledDB()
            if not db then return end

            if db.hideSellPrice then
                return true
            end

            local price = lineData and lineData.price
            if type(price) ~= "number" or price <= 0 then
                return true
            end

            local moneyString
            if _G.GetMoneyString and _G.MoneyStringConstants then
                moneyString = _G.GetMoneyString(price, _G.MoneyStringConstants.SeparateThousands, _G.MoneyStringConstants.DontCheckGoldThreshold)
            end
            if not moneyString or moneyString == "" then
                return true
            end

            local label = (_G.SELL_PRICE or "卖价") .. ": "
            local r, g, b = 1, 1, 1
            if _G.HIGHLIGHT_FONT_COLOR and _G.HIGHLIGHT_FONT_COLOR.GetRGB then
                r, g, b = _G.HIGHLIGHT_FONT_COLOR:GetRGB()
            end
            tt:AddLine(label .. moneyString, r, g, b, true)
            return true
        end)

        _G.TooltipDataProcessor:AddLinePreCall(_G.Enum.TooltipDataLineType.ItemName, function(tt, lineData)
            if not tooltipSet[tt] then return end
            local db = GetEnabledDB()
            if not db then return end

            local itemLink = tt._yuiTooltipDataItemLink
            if (not itemLink or itemLink == "") and tt.GetItem then
                itemLink = select(2, tt:GetItem())
            end
            if (not itemLink or itemLink == "") then
                itemLink = tt._yuiTooltipDataItemID
            end
            if not itemLink then return end

            local itemLevel = select(4, GetItemInfo(itemLink))
            if not itemLevel then
                local tries = (tt._yuiItemLevelRetryCount or 0)
                if tries >= 2 then
                    tt._yuiItemLevelRetryCount = nil
                    return
                end
                tt._yuiItemLevelRetryCount = tries + 1
                C_Timer.After(0.08, function()
                    if not (tt and tt:IsShown()) then return end
                    if tt.RebuildFromTooltipInfo then
                        tt:RebuildFromTooltipInfo()
                    end
                end)
                return
            end

            local equipLoc = select(9, GetItemInfo(itemLink))
            if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
                return
            end

            lineData.rightText = string.format("|cffffd100%s|r", tostring(itemLevel))
        end)
    end

    if not hasTooltipDataProcessor and not YUI.Components._yuiElvUIAdapterTooltipAwait then
        YUI.Components._yuiElvUIAdapterTooltipAwait = true

        local waiterOwner = {}
        YUI.Event:On("ADDON_LOADED", function(_, addonName)
            if addonName ~= "Blizzard_GameTooltip" and addonName ~= "Blizzard_SharedXMLGame" then return end
            UpdateItemLevelTooltipHooks()
            if _G.TooltipDataProcessor and _G.TooltipDataProcessor._yuiElvUIAdapterTooltipHooked then
                YUI.Components._yuiElvUIAdapterTooltipAwait = nil
                YUI.Event:OffOwner(waiterOwner)
            end
        end, waiterOwner)

        C_Timer.After(1, function()
            if _G.TooltipDataProcessor and _G.TooltipDataProcessor.AddLinePreCall then
                UpdateItemLevelTooltipHooks()
                if _G.TooltipDataProcessor and _G.TooltipDataProcessor._yuiElvUIAdapterTooltipHooked then
                    YUI.Components._yuiElvUIAdapterTooltipAwait = nil
                    YUI.Event:OffOwner(waiterOwner)
                end
            end
        end)
    end

    local function OnTooltipSetItem(tt)
        if not tooltipSet[tt] then return end
        local db = GetEnabledDB()
        if not db then return ClearState(tt) end
        if not tt or not tt.GetItem then return end

        local _, itemLink = tt:GetItem()
        if not itemLink then return ClearState(tt) end

        local itemLevel = select(4, GetItemInfo(itemLink))
        if not itemLevel then return end

        local equipLoc = select(9, GetItemInfo(itemLink))
        if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
            return
        end

        local name = tt:GetName()
        if not name then return end

        local function NormalizeText(text)
            if not text or text == "" then return "" end
            text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
            text = text:gsub("|r", "")
            text = text:gsub("|T.-|t", "")
            text = text:gsub("|A.-|a", "")
            text = text:gsub("%s+", " ")
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            return text
        end

        local function FindItemNameLineIndex()
            local numLines = tt:NumLines() or 0
            if numLines <= 0 then return 1 end

            local itemName = GetItemInfo(itemLink)
            if itemName and itemName ~= "" then
                local normalizedItemName = NormalizeText(itemName)
                for i = 1, math.min(8, numLines) do
                    local left = _G[name .. "TextLeft" .. i]
                    local text = left and left:GetText()
                    if text and NormalizeText(text) == normalizedItemName then
                        return i
                    end
                end
            end

            local left1 = _G[name .. "TextLeft1"]
            local t1 = left1 and NormalizeText(left1:GetText())
            if t1 == "当前装备" or t1 == "Currently Equipped" or t1 == "Currently Equipped:" then
                if numLines >= 2 then
                    return 2
                end
            end

            return 1
        end

        local index = FindItemNameLineIndex()
        local right = _G[name .. "TextRight" .. index]
        if not right then return end
        right:SetText(string.format("|cffffd100%s|r", tostring(itemLevel)))
        right:Show()
        tt:Show()
    end

    for _, tt in ipairs(tooltipList) do
        if tt and not tt._yuiItemLevelFallbackHooked then
            tt._yuiItemLevelFallbackHooked = true
            tt:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        end
    end
end

local function OnEnable(enable)
    EnsureDB()
    if enable then
        CheckAndDisablePetFrame()
    end

    UpdateItemLevelTooltipHooks()
    UpdateRoleIconState()
end

local desc = ""

if YUI.IsRetail then
    desc = LC["elv_adapter.text.001"]
elseif YUI.IsWrath then
    desc = LC["elv_adapter.text.002"]
end

local feature = {
    name = LC["elv_adapter.text.003"],
    description = desc,
    default = true,
    callback = OnEnable,
}

feature.GetOptions = function(self)
    local db = EnsureDB()

    local function Refresh()
        if self.RefreshCurrentModule then
            self:RefreshCurrentModule()
        end
    end

    local options = {}

    if YUI.IsRetail then
        table.insert(options, {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = LC["elv_adapter.text.004"],
                    tooltip = LC["elv_adapter.text.005"],
                    get = function() return db.disablePetFrame end,
                    set = function(v)
                        db.disablePetFrame = v
                        if v then
                            CheckAndDisablePetFrame()
                        end
                        Refresh()
                    end
                },
                {
                    type = "checkbox",
                    label = LC["elv_adapter.text.006"],
                    tooltip = LC["elv_adapter.text.007"],
                    get = function() return db.roleIcon end,
                    set = function(v)
                        db.roleIcon = v == true
                        UpdateRoleIconState()
                        Refresh()
                    end
                },
            }
        })
        table.insert(options, {
            type = "text",
            label = LC["elv_adapter.text.008"],
            color = YUI.Settings.Colors.text,
        })
    elseif YUI.IsWrath then
        table.insert(options, {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = LC["elv_adapter.text.009"],
                    tooltip = LC["elv_adapter.text.010"],
                    get = function() return db.tooltip_itemLevel end,
                    set = function(v)
                        db.tooltip_itemLevel = v
                        UpdateItemLevelTooltipHooks()
                        Refresh()
                    end
                },
                {
                    type = "checkbox",
                    label = LC["elv_adapter.text.011"],
                    tooltip = LC["elv_adapter.text.012"],
                    get = function() return db.hideSellPrice end,
                    set = function(v)
                        db.hideSellPrice = v
                        Refresh()
                    end
                }
            }
        })
        table.insert(options, {
            type = "text",
            label = LC["elv_adapter.text.013"],
            color = YUI.Settings.Colors.text,
        })
    end

    return options
end

Components:RegisterFeature("ElvUIAdapter", feature)

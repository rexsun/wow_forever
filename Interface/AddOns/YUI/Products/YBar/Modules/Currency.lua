local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("Currency") end
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

local function GetGlobalDB()
    if YUI.DB and YUI.DB.GetGlobal then
        local global = YUI.DB:GetGlobal("ybar")
        if type(global) == "table" then
            return global
        end
    end
    return type(YUI.global) == "table" and YUI.global or nil
end

local function EnsureGoldDB()
    local global = GetGlobalDB()
    if type(global) ~= "table" then
        return nil
    end
    if type(global.Gold) ~= "table" then
        global.Gold = {}
    end
    return global.Gold
end

local YBar = YUI.YBar
local GUI2 = YUI.GUI2
local LegacyAPI = YUI.WOW_API
local SpellAPI = YUI.API and YUI.API.Spell or LegacyAPI
local UnitAPI = YUI.API and YUI.API.Unit or LegacyAPI
local ItemAPI = YUI.API and YUI.API.Item or LegacyAPI
local CombatAPI = YUI.API and YUI.API.Combat or LegacyAPI
local SecurityAPI = YUI.API and YUI.API.Security or LegacyAPI
local Module = YBar.Module:New("Currency")
local L = YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")

-- 缓存全局变量
    local GetMoney = GetMoney
    local GetMoneyString = GetMoneyString
    local BreakUpLargeNumbers = BreakUpLargeNumbers
    local C_CurrencyInfo = C_CurrencyInfo
    local C_WowTokenPublic = C_WowTokenPublic
    local IsLoggedIn = IsLoggedIn
    local GetRealmName = GetRealmName
    local UnitName = UnitName
    local UnitClass = UnitClass
    local UnitFactionGroup = UnitFactionGroup
    local ToggleCharacter = ToggleCharacter
    local GameTooltip = GameTooltip
    local C_Container = C_Container
    local GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local NUM_BAG_SLOTS = NUM_BAG_SLOTS
    local NUM_REAGENT_BAG_SLOTS = NUM_REAGENT_BAG_SLOTS or 0
    local C_CVar = C_CVar
    local CastSpellByName = CastSpellByName
    local GetCoinTextureString = GetCoinTextureString or function(amount) return GetMoneyString(amount) end -- 兼容性处理
    local format = string.format
    local ipairs = ipairs
    local pairs = pairs
    local table_insert = table.insert
    local table_sort = table.sort
    local floor = math.floor
    local mod = math.fmod or math.mod

    -- 默认值
    local DEFAULT_SIZE = 14
    local DEFAULT_ICON_SIZE = DEFAULT_SIZE + 2
    local DEFAULT_FONT = STANDARD_TEXT_FONT

local function FormatMoney(amount)
    local gold = floor(amount / 10000)
    local silver = floor(mod(amount / 100, 100))
    local copper = floor(mod(amount, 100))

    local str = ""
    if gold > 0 then
        str = format("%s|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:2:0|t", BreakUpLargeNumbers(gold))
    end

    -- 如果总价值>100金币, 则不显示银币和铜币
    if gold >= 100 then
        return str
    end

    -- 如果总价值>1银币则显示银币
    if gold > 0 or silver > 0 then
        if str ~= "" then str = str .. " " end
        str = str .. format("%d|TInterface\\MoneyFrame\\UI-SilverIcon:11:11:2:0|t", silver)
    end

    -- 如果总价值<1银则显示铜币 (gold == 0 and silver == 0)
    if gold == 0 and silver == 0 then
        if str ~= "" then str = str .. " " end
        str = str .. format("%d|TInterface\\MoneyFrame\\UI-CopperIcon:11:11:2:0|t", copper)
    end

    return str
end

local function IsCurrencyFrameReady(frame)
    return not Module._hasError and frame and not frame.ybarErrorPlaceholder and
        not frame.errorText and frame.text and (frame.iconSlot or frame.icon) and
        Module.secure
end



function Module:OnInitialize()
    -- 初始化配置
    local ybarDB = GetYBarDB()
    if type(ybarDB) ~= "table" then
        return
    end
    ybarDB.Currency = ybarDB.Currency or {
        font = DEFAULT_FONT,
        size = DEFAULT_SIZE,
        showIcon = true,
        showText = true,
        currencyID = 0, -- 0 = Gold
        showSmall = false, -- 是否显示银币铜币
        showBagSpace = false, -- 是否显示背包剩余空间
        tooltipCurrencies = { -- Tooltip 中显示的货币列表
            2032, -- 标示纹章 (示例)
            -- 可以在这里添加更多默认货币ID
        }
    }
    self.db = ybarDB.Currency

    -- 初始化金币数据库 (使用全局 DB)
    local goldDB = EnsureGoldDB()
    if not goldDB then
        return
    end
    local realm = GetRealmName()
    goldDB[realm] = goldDB[realm] or {}
    goldDB[realm].money = goldDB[realm].money or {}
    goldDB[realm].class = goldDB[realm].class or {}
    goldDB[realm].faction = goldDB[realm].faction or {}

    -- 会话统计
    self.myMoney = GetMoney()
    self.profit = 0
    self.spent = 0

    -- 注册事件
    -- 需要在 CreateBarItem 中注册事件监听
end

function Module:UpdateGoldDB()
    if not IsLoggedIn() then return end
    local realm = GetRealmName()
    local name = UnitName("player")
    local money = GetMoney()

    -- 使用全局 DB
    local goldDB = EnsureGoldDB()
    if not goldDB then return end
    goldDB[realm] = goldDB[realm] or {}
    goldDB[realm].money = goldDB[realm].money or {}
    goldDB[realm].class = goldDB[realm].class or {}
    goldDB[realm].faction = goldDB[realm].faction or {}

    goldDB[realm].money[name] = money
    goldDB[realm].class[name] = select(2, UnitClass("player"))
    goldDB[realm].faction[name] = UnitFactionGroup("player")
end

function Module:LeftClick()
    _G.ToggleAllBags()
end

function Module:RightClick()
    if YUI.IsForever then
        return YUI.API.Frame.ToggleCharacter("TokenFrame")
    end
    ToggleCharacter("TokenFrame")
end

function Module:ShiftRightClick()
    self:ShowMenu()
end

local function CurrencyOnEvent(event)
    local frame = Module.frame

    if Module._hasError then return end

    if event == "PLAYER_MONEY" then
        local newMoney = GetMoney()
        local change = newMoney - (Module.myMoney or newMoney)
        if change > 0 then
            Module.profit = (Module.profit or 0) + change
        elseif change < 0 then
            Module.spent = (Module.spent or 0) - change
        end
        Module.myMoney = newMoney
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Module.needsUpdate then
            Module.needsUpdate = false
            if not IsCurrencyFrameReady(frame) then return end
            Module:UpdateBarItem(frame, Module.parent)
        end
        return
    end

    Module:UpdateGoldDB()
    if not IsCurrencyFrameReady(frame) then return end
    Module:UpdateBarItem(frame, Module.parent)
end

function Module:AttachRuntime()
    if (YUI.IsForever or YUI.IsRetail) and self.db ~= GetYBarDB().Currency then self:OnDBReload() end
    if not IsCurrencyFrameReady(self.frame) then return end

    YUI.Event:OffOwner(self)
    YUI.Event:On("PLAYER_MONEY", CurrencyOnEvent, self)
    if (YUI.IsForever or YUI.IsRetail) then YUI.Event:On("BAG_UPDATE_DELAYED", CurrencyOnEvent, self) end
    if not (YUI.IsForever or YUI.IsRetail) then YUI.Event:On("CURRENCY_DISPLAY_UPDATE", CurrencyOnEvent, self) end
    YUI.Event:On("YUI_WORLD_READY", CurrencyOnEvent, self)
    YUI.Event:On("PLAYER_REGEN_ENABLED", CurrencyOnEvent, self)

    self:UpdateGoldDB()
    self:UpdateBarItem(self.frame, self.parent)
end

function Module:OnDBReload()
    if not (YUI.IsForever or YUI.IsRetail) then return end
    local profit, spent, money = self.profit, self.spent, self.myMoney
    self:OnInitialize()
    self.profit, self.spent, self.myMoney = profit or 0, spent or 0, money or GetMoney()
    self.currencySearch = nil
    self:UpdateBarItem()
end

function Module:DetachRuntime()
    YUI.Event:OffOwner(self)

    self.needsUpdate = false

    if YBar and YBar.PopIconMenu then
        YBar.PopIconMenu:Hide()
    end

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

function Module:RefreshActionHost()
    if self._hasError then return end
    if not self.secure or not self.secure.actionHost then return end

    local actions = {
        left = {
            kind = "custom",
            onClick = function()
                Module:LeftClick()
            end,
        },
        right = {
            kind = "custom",
            onClick = function()
                Module:RightClick()
            end,
        },
        altLeft = {
            kind = "custom",
            onClick = function()
                YUI:OpenYBarModuleSettings("Currency")
            end,
        },
        altRight = { kind = "noop" },
        shiftRight = {
            kind = "custom",
            onClick = function()
                Module:ShiftRightClick()
            end,
        },
    }

    if YUI.IsRetail then
        local spellName = SpellAPI.GetName and SpellAPI.GetName(460905)
        if spellName then
            actions.shiftLeft = {
                kind = "spell",
                spell = spellName,
            }
        else
            actions.shiftLeft = { kind = "noop" }
        end
    end

    self.secure.actionHost:SetActions(actions)
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

    local secure = GUI2:CreateFrame(frame)
    secure:SetAllPoints()
    YBar:CreateActionHost(secure, {
        onEnter = function(_, owner)
            if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(frame) end
            Module:OnEnter(owner)
            YBar:SetThemedTextAccent(owner.text)
        end,
        onLeave = function(_, owner)
            if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(frame) end
            YUI.HideGameTooltip()
            YBar:RestoreThemedTextColor(owner.text, "color.ybar.text")
        end,
    })

    frame.iconSlot, frame.icon = YBar:CreateIconSlot(secure, {
        size = DEFAULT_ICON_SIZE,
        shape = "square",
        padding = 0,
    })
    if frame.iconSlot then
        frame.iconSlot:SetPoint("LEFT", secure, "LEFT", 0, 0)
    else
        frame.icon:SetPoint("LEFT", secure, "LEFT", 0, 0)
    end

    frame.statusText, frame.text = YBar:CreateStatusText(secure, {
        variant = "single",
        value = "",
        width = 50,
        height = 20,
        justifyH = "LEFT",
        colorKey = "color.ybar.text",
    })
    local text = frame.text
    text:ClearAllPoints()
    text:SetPoint("LEFT", frame.iconSlot or frame.icon, "RIGHT", 4, 0)
    frame.text = text
    secure.text = text
    YBar:RegisterBarItemHoverText(frame, text)

    self.frame = frame
    self.secure = secure
    self:RefreshActionHost()

    -- 初始更新
    self:UpdateGoldDB()
    self:UpdateBarItem(frame, parent)

    if YBar and YBar.IsSubModuleEnabled and YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end

    return frame
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end
    if not frame then frame = self.frame end
    if not IsCurrencyFrameReady(frame) then return end

    local db = self.db
    local font = YBar:ResolveFontPath(db.font, DEFAULT_FONT) -- 借用 Clock 的字体设置保持一致
    local size = db.size or DEFAULT_SIZE

    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")

    frame.text:SetFont(font, size, fontFlag)

    if globalDB.fontShadow then
        frame.text:SetShadowColor(0, 0, 0, 1)
        frame.text:SetShadowOffset(1, -1)
    else
        frame.text:SetShadowOffset(0, 0)
    end

    local currencyID = (YUI.IsForever or YUI.IsRetail) and 0 or (db.currencyID or 0)
    local amount = 0
    local iconTexture = ""
    local textStr = ""

    if currencyID == 0 then
        -- 金币
        amount = GetMoney()
        iconTexture = "Interface\\Icons\\INV_Misc_Coin_02" -- 金币图标
        -- 或者使用 C_CurrencyInfo.GetCoinIcon(amount) ? 不，直接用金币图标即可

        -- 格式化金币显示
        textStr = FormatMoney(amount)
    else
        -- 其他货币
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info then
            amount = info.quantity
            iconTexture = info.iconFileID
            textStr = BreakUpLargeNumbers(amount)
        else
            textStr = "?"
            iconTexture = 134400 -- Question mark
        end
    end

    if db.showIcon then
        frame.icon:SetTexture(iconTexture)
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
        frame.text:SetPoint("LEFT", self.secure, "LEFT", 2, 0)
    end


    if db.showText then
        if db.showBagSpace then
            local free = 0
            for i = 0, NUM_BAG_SLOTS do
                local slots = GetContainerNumFreeSlots(i)
                if slots then free = free + slots end
            end
            textStr = format("%s (|cffffffff%d|r)", textStr, free)
        end
        if frame.text:GetText() ~= textStr then frame.text:SetText(textStr) end
        frame.text:Show()
    else
        frame.text:Hide()
    end

    -- 更新宽度
    local width = 0
    if db.showIcon then
        width = width + DEFAULT_ICON_SIZE + 4
    end
    if db.showText then
        local textWidth = frame.text:GetStringWidth() or 0
        if textWidth == 0 and textStr ~= "" then
             -- 估算宽度作为后备方案
             textWidth = string.len(textStr) * (db.size or DEFAULT_SIZE) * 0.6
        end
        width = width + textWidth + 2 -- Add padding
    end

    local widthChanged = self.width ~= width
    self.width = width
    if widthChanged then YBar:UpdateLayout() end

    if not SecurityAPI.InCombatLockdown() then
        frame:SetWidth(width)
    else
        self.needsUpdate = true
    end
end

function Module:GetWidth()
    return self.width or 50
end

function Module:OnEnter(frame)
    local tooltipAnchor = "ANCHOR_TOP"
    local bar = self.parent

    if bar and bar:GetBottom() > GetScreenHeight() / 2 then
        tooltipAnchor = "ANCHOR_BOTTOM"
    end

    GameTooltip:SetOwner(frame, tooltipAnchor)
    GameTooltip:ClearLines()

    local db = self.db
    local currencyID = (YUI.IsForever or YUI.IsRetail) and 0 or (db.currencyID or 0)

    if currencyID == 0 then
        -- 显示金币详情
        GameTooltip:AddLine(L["currency.tooltip.title"])
        GameTooltip:AddLine(" ")

        -- 会话统计
        local profit = self.profit or 0
        local spent = self.spent or 0
        local net = profit - spent

        if profit > 0 or spent > 0 then
            GameTooltip:AddLine(L["currency.tooltip.session"])
            GameTooltip:AddDoubleLine(L["currency.tooltip.earned"], FormatMoney(profit), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["currency.tooltip.spent"], FormatMoney(spent), 1, 1, 1, 1, 1, 1)
            if net > 0 then
                GameTooltip:AddDoubleLine(L["currency.tooltip.net_profit"], FormatMoney(net), 0, 1, 0, 1, 1, 1)
            elseif net < 0 then
                GameTooltip:AddDoubleLine(L["currency.tooltip.net_loss"], FormatMoney(-net), 1, 0, 0, 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
        end

        -- 本服角色列表
        local realm = GetRealmName()
        local myName = UnitName("player")

        local totalGold = 0
        local totalAlliance = 0
        local totalHorde = 0
        local goldList = {}
        -- 使用全局 DB
        local goldDB = EnsureGoldDB()
        if goldDB and goldDB[realm] and goldDB[realm].money then
            for name, money in pairs(goldDB[realm].money) do
                table_insert(goldList, {name = name, money = money})
                totalGold = totalGold + money

                local faction = goldDB[realm].faction[name]
                if faction == "Alliance" then
                    totalAlliance = totalAlliance + money
                elseif faction == "Horde" then
                    totalHorde = totalHorde + money
                end
            end
        end

        -- 排序：金额从大到小
        table_sort(goldList, function(a, b) return a.money > b.money end)

        GameTooltip:AddLine(L["currency.tooltip.characters"])
        for _, info in ipairs(goldList) do
            local moneyStr = FormatMoney(info.money)
            local classFileName = goldDB[realm].class[info.name]
            local faction = goldDB[realm].faction[info.name]

            local color = UnitAPI.GetClassColor and UnitAPI.GetClassColor(classFileName)
            local nameStr = info.name
            if color then
                local hex = color:GenerateHexColor()
                nameStr = format("|c%s%s|r", hex, info.name)
            end

            -- 阵营图标
            if faction == "Alliance" then
                nameStr = "|TInterface\\FriendsFrame\\PlusManz-Alliance:14|t " .. nameStr
            elseif faction == "Horde" then
                nameStr = "|TInterface\\FriendsFrame\\PlusManz-Horde:14|t " .. nameStr
            end

            if info.name == myName then
                nameStr = nameStr .. " |TInterface\\COMMON\\Indicator-Green:14|t"
            end

            GameTooltip:AddDoubleLine(nameStr, moneyStr, 1, 1, 1, 1, 1, 1)
        end

        GameTooltip:AddLine(" ")

        -- 阵营总计
        if totalAlliance > 0 and totalHorde > 0 then
            GameTooltip:AddDoubleLine(L["currency.tooltip.alliance"], FormatMoney(totalAlliance), 0, 0.7, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["currency.tooltip.horde"], FormatMoney(totalHorde), 1, 0.2, 0.2, 1, 1, 1)
            GameTooltip:AddLine(" ")
        end

        GameTooltip:AddDoubleLine(L["currency.tooltip.character_total"], FormatMoney(totalGold), 1, 1, 1, 1, 1, 1)

    -- 战团银行 (Retail Only)
    if YUI.IsRetail and C_Bank and C_Bank.FetchDepositedMoney then
         local warbankMoney = C_Bank.FetchDepositedMoney(2) -- 2 = Account
         if warbankMoney then
            GameTooltip:AddDoubleLine(L["currency.tooltip.warband_bank"], FormatMoney(warbankMoney), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddLine(" ")
             GameTooltip:AddDoubleLine(string.format("|c%s%s:|r", YBar.Colors_Hex.HEADER_TEXT_COLOR, LC["common.total"]), FormatMoney(warbankMoney + totalGold), 1, 1, 1, 1, 1, 1)
         end
    end

    if YUI.IsRetail or YUI.IsWrath then
        -- 时光徽章 (Retail Only)
        if C_WowTokenPublic then
            local price = C_WowTokenPublic.GetCurrentMarketPrice()
            if price then
                local texture = (ItemAPI.GetIcon and ItemAPI.GetIcon(122284)) or 134400
                local icon = format("|T%s:14:14:0:0:64:64:4:60:7:57:255:255:255|t ", texture)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(icon .. L["currency.tooltip.wow_token"], FormatMoney(price), 0, 0.8, 1, 1, 1, 1)
            end
        end
    end

        -- 战团银行冷却
        if not YUI.IsForever and not SecurityAPI.InCombatLockdown() then
            local spellId = 460905
            local spellName = SpellAPI.GetName and SpellAPI.GetName(spellId)
            if spellName then
                local texture = SpellAPI.GetTexture and SpellAPI.GetTexture(spellId) or (LegacyAPI.GetSpellIcon and LegacyAPI.GetSpellIcon(spellId)) or 134400
                local icon = format("|T%s:14:14:0:0:64:64:4:60:7:57:255:255:255|t ", texture)
                local cdInfo = SpellAPI.GetCooldown and SpellAPI.GetCooldown(spellId)
                if cdInfo then
                    local startTime = cdInfo.startTime
                    local duration = cdInfo.duration
                    if startTime and duration then
                        local success, remaining = pcall(function()
                            if duration > 0 then
                                return startTime + duration - CombatAPI.GetTime()
                            end
                            return 0
                        end)

                        if success and remaining and remaining > 0 then
                            local min = math.floor(remaining / 60)
                            local sec = math.floor(remaining % 60)
                            GameTooltip:AddDoubleLine(icon .. L["currency.tooltip.mobile_warbank"], format("%02d:%02d", min, sec), 1, 1, 1, 1, 0, 0)
                        else
                            GameTooltip:AddDoubleLine(icon .. L["currency.tooltip.mobile_warbank"], LC["common.ready"], 1, 1, 1, 0, 1, 0)
                        end
                    else
                        GameTooltip:AddDoubleLine(icon .. L["currency.tooltip.mobile_warbank"], LC["common.ready"], 1, 1, 1, 0, 1, 0)
                    end
                end
            end
        end

    else
        -- 其他货币
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info then
            GameTooltip:AddLine(info.name)
            GameTooltip:AddLine(info.description, 1, 1, 1, true)

            if info.maxQuantity > 0 then
                GameTooltip:AddDoubleLine(LC["common.max"] .. ":", BreakUpLargeNumbers(info.maxQuantity), 1, 1, 1, 1, 1, 1)
            end

            local totalEarned = info.totalEarned
            if totalEarned > 0 then
                GameTooltip:AddDoubleLine(L["currency.tooltip.total_earned"], BreakUpLargeNumbers(totalEarned), 1, 1, 1, 1, 1, 1)
            end
        end
    end

    GameTooltip:AddLine(" ")

    GameTooltip:AddLine(format("|cffFFFFFF%s:|r %s", LC["common.left_click"], L["currency.action.open_bags"]))
    GameTooltip:AddLine(format("|cffFFFFFF%s:|r %s", LC["common.right_click"], L["currency.action.open_currency"]))
    if (YUI.IsForever or YUI.IsRetail) then
        GameTooltip:AddLine(format("|cffFFFFFFShift + %s:|r %s", LC["common.left_click"], L["currency.action.summon_warbank"]))
    end
    GameTooltip:AddLine(format("|cffFFFFFFShift + %s:|r %s", LC["common.right_click"], L["currency.action.quick_menu_clear"]))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))

    GameTooltip:Show()
end

local function ClearAllGoldData()
    local global = GetGlobalDB()
    if global then
        global.Gold = {}
    end
    Module:UpdateGoldDB()
    Module:UpdateBarItem()
    YUI:Print(L["currency.message.gold_data_cleared"])
end

local function ShowClearGoldConfirm()
    local Settings = YUI.Settings
    if not (Settings and Settings.ShowConfirmPopup) then return end
    Settings:ShowConfirmPopup(L["currency.confirm.clear_gold"], ClearAllGoldData, {
        titleText = L["currency.menu.clear_all_gold"],
        acceptTone = "danger",
    })
end

function Module:ShowMenu()
    local menuList = {
        {
            text = L["currency.menu.gold"],
            icon = "Interface\\Icons\\INV_Misc_Coin_02",
            onClick = function()
                self.db.currencyID = 0
                self:UpdateBarItem()
            end
        }
    }

    -- 添加 Tooltip 监控的货币
    local menuCurrencyIDs = YBar.CurrencyTracking and YBar.CurrencyTracking.MenuIDs(self.db) or self.db.tooltipCurrencies
    if not (YUI.IsForever or YUI.IsRetail) and menuCurrencyIDs then
        for _, id in ipairs(menuCurrencyIDs) do
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info then
                 table.insert(menuList, {
                     text = info.name,
                     icon = info.iconFileID,
                     onClick = function()
                         self.db.currencyID = id
                         self:UpdateBarItem()
                     end
                 })
            end
        end
    end

    -- 增加清空所有数据的选项
    local icon = (YUI.IsForever or YUI.IsRetail) and "Interface/Icons/MISC_RnRRedXButton" or "Interface/Icons/INV_Misc_Bone_HumanSkull_01"
    table.insert(menuList, {
        text = "|cffff0000" .. L["currency.menu.clear_all_gold"] .. "|r",
        icon = icon,
        onClick = ShowClearGoldConfirm,
    })

    YBar:CreatePopIconMenu(self.frame, menuList, {columns = 1, colWidth = 150, gui2 = true})
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

    local options = {
        -- 1. 字体
        {
            type = "dropdown",
            label = LC["common.font"],
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function() return self.db.font or defaultFont end,
            set = function(val)
                self.db.font = val
                self:UpdateBarItem()
            end
        },
        -- 2. 尺寸
        {
            type = "slider",
            label = LC["common.size"],
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return self.db.size or DEFAULT_SIZE end,
            set = function(val)
                self.db.size = val
                self:UpdateBarItem()
            end
        },
        -- 3. 显示图标
        {
            type = "checkbox",
            label = LC["common.show_icon"],
            default = true,
            get = function() return self.db.showIcon end,
            set = function(val)
                self.db.showIcon = val
                self:UpdateBarItem()
            end
        },
        -- 4. 显示背包剩余空间
        {
            type = "checkbox",
            label = L["currency.option.show_bag_space"],
            default = false,
            get = function() return self.db.showBagSpace end,
            set = function(val)
                self.db.showBagSpace = val
                self:UpdateBarItem()
            end
        },
        -- 5. 显示银币铜币 (Removed)
        -- {
        --     type = "checkbox",
        --     label = "显示银币铜币",
        --     default = false,
        --     get = function() return self.db.showSmall end,
        --     set = function(val)
        --         self.db.showSmall = val
        --         self:UpdateBarItem()
        --     end
        -- },
        -- 6. 清空数据 (保留原有功能)
        {
            type = "button",
            label = LC["common.clear_data"],
            width = 120,
            onClick = ShowClearGoldConfirm,
        }
    }
    return options
end

YBar:RegisterModule(Module, {
    id = "ybar.currency",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api", "core.locale"},
    defaultEnabled = true,
})

local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components) then return end

local Components = YUI.Components
local L = YUI.Locale and YUI.Locale:Get("RightPlus") or {}
local API = YUI and YUI.WOW_API
local SystemAPI = YUI and YUI.API and YUI.API.System or API
local featureEnabled = false
local initialized = false
local legacyRightFrame

-- 全局常量安全检查
local ADD_FRIEND_TEXT = "|A:socialqueuing-icon-group:14:14|a " ..
                            (ADD_FRIEND or "Add Friend")
local INVITE_GUILD_TEXT = "|A:newplayerchat-chaticon-guide:14:14|a " ..
                              (INVITE or "Invite") .. (GUILD or "Guild")

local FUNCTION_MAP = {
    [ADD_FRIEND_TEXT] = function(name) C_FriendList.AddFriend(name) end,
    [INVITE_GUILD_TEXT] = function(name) GuildInvite(name) end
}

local MENU_LIST = {ADD_FRIEND_TEXT, INVITE_GUILD_TEXT}

-- 获取处理后的名字 (处理跨服名字拼接)
local function GetFullTargetName(name, server)
    -- 只有当服务器名存在且不是当前服务器时才拼接
    if server then
        local success, isValid = pcall(function() 
            return server ~= "" and server ~= GetRealmName() 
        end)
        if success and isValid then
            return name .. "-" .. server
        end
    end
    return name
end

local function InitNewRightPlus()
    if initialized then return true end

    -- 如果有安装 NDUI 或 ElvUI WindTools 则不初始化。
    local isAddOnLoaded = SystemAPI and SystemAPI.IsAddOnLoaded
    if isAddOnLoaded and
        (isAddOnLoaded("NDUI") or isAddOnLoaded("ElvUI_WindTools")) then
        return false
    end

    -- 适配 10.0+ 新菜单系统 (使用 Menu API)
    if Menu and Menu.ModifyMenu then
        local function AddRightPlusMenu(rootDescription, contextData)
            if not featureEnabled or not contextData or not contextData.name then
                return
            end

            local name = GetFullTargetName(contextData.name, contextData.server)

            rootDescription:CreateDivider()
            for _, actionKey in ipairs(MENU_LIST) do
                local action = actionKey
                rootDescription:CreateButton(action, function()
                    if FUNCTION_MAP[action] then
                        FUNCTION_MAP[action](name)
                    end
                end)
            end
        end

        -- 定义需要注入的菜单类型
        local menuTypes = {
            "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_RAID_PLAYER",
            "MENU_UNIT_PARTY", "MENU_UNIT_TARGET", "MENU_UNIT_SELF"
        }

        for _, menuType in ipairs(menuTypes) do
            Menu.ModifyMenu(menuType,
                            function(ownerRegion, rootDescription, contextData)
                if not featureEnabled or not contextData then return end

                -- 简单的过滤逻辑：如果有 unit，必须是玩家；如果是好友列表等无 unit 的情况，直接通过
                if contextData.unit then
                    if UnitIsPlayer(contextData.unit) then
                        AddRightPlusMenu(rootDescription, contextData)
                    end
                else
                    AddRightPlusMenu(rootDescription, contextData)
                end
            end)
        end

    else
        -- 适配经典/旧版菜单系统 (Hook UnitPopup + 侧边栏 Frame)
        local FRAME_WIDTH, FRAME_HEIGHT = 86, 18
        -- 创建侧边栏容器，挂在 DropDownList1 右侧
        local RightF = CreateFrame("Frame", nil, UIParent)
        RightF:SetPoint("TOPLEFT", DropDownList1, "TOPRIGHT", 0, -10)
        RightF:SetSize(FRAME_WIDTH, FRAME_HEIGHT * #MENU_LIST + 16)
        RightF:SetFrameStrata("FULLSCREEN_DIALOG")
        RightF:Hide()
        legacyRightFrame = RightF

        -- 设置背景样式 (使用原生样式，移除外部插件依赖)
        -- 尝试获取系统默认菜单背景
        local bgFile = DropDownList1MenuBackdrop and
                           DropDownList1MenuBackdrop.NineSlice.Center:GetTexture()
        if bgFile then
            local r, g, b =
                DropDownList1MenuBackdrop.NineSlice.Center:GetVertexColor()
            local br, bg, bb =
                DropDownList1MenuBackdrop:GetBackdropBorderColor()
            RightF:SetBackdrop({
                bgFile = bgFile,
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = false,
                tileSize = 0,
                edgeSize = 14,
                insets = {left = 4, right = 4, top = 4, bottom = 4}
            })
            RightF:SetBackdropColor(r, g, b)
            RightF:SetBackdropBorderColor(br, bg, bb)
        else
            -- Fallback 样式
            RightF:SetBackdrop({
                bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
                edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                tile = true,
                tileSize = 32,
                edgeSize = 32,
                insets = {left = 8, right = 8, top = 8, bottom = 8}
            })
            RightF:SetBackdropColor(0, 0, 0, 0.8)
        end

        -- 创建功能按钮
        RightF.buttons = {}
        for i, actionKey in ipairs(MENU_LIST) do
            local action = actionKey
            local btn = CreateFrame("Button", nil, RightF,
                                    "UIDropDownMenuButtonTemplate")
            btn:SetSize(FRAME_WIDTH - 8, FRAME_HEIGHT)

            if i == 1 then
                btn:SetPoint("TOPLEFT", RightF, "TOPLEFT", 4, -8)
            else
                btn:SetPoint("TOPLEFT", RightF.buttons[i - 1], "BOTTOMLEFT", 0,
                             0)
            end

            btn:SetText(action)

            -- 按钮点击逻辑
            btn:SetScript("OnClick", function(self)
                if not featureEnabled then return end

                local dropdown = UIDROPDOWNMENU_INIT_MENU
                if not dropdown then return end

                local name = GetFullTargetName(dropdown.name, dropdown.server)
                if FUNCTION_MAP[action] then
                    FUNCTION_MAP[action](name)
                end

                RightF:Hide()
                CloseDropDownMenus()
            end)

            -- 鼠标悬停高亮 & 保持菜单显示
            btn:SetScript("OnEnter", function(self)
                if self.Highlight then self.Highlight:Show() end
                if DropDownList1 then DropDownList1.RF = true end
            end)
            btn:SetScript("OnLeave", function(self)
                if self.Highlight then self.Highlight:Hide() end
                if DropDownList1 then DropDownList1.RF = nil end
            end)

            RightF.buttons[i] = btn
        end

        -- 更新侧边栏状态
        local function UpdateRightFrame()
            if RightF:IsShown() then
                -- 动态显示/隐藏按钮 (虽然当前是固定的，但保留扩展性)
                local visibleCount = 0
                for _, btn in ipairs(RightF.buttons) do
                    btn:Show()
                    visibleCount = visibleCount + 1
                end
                RightF:SetHeight(visibleCount * FRAME_HEIGHT + 16)
            end
        end

        -- Hook UnitPopup_ShowMenu 监听菜单打开
        hooksecurefunc("UnitPopup_ShowMenu",
                       function(dropdownMenu, which, unit, name, userData)
            -- 只处理一级菜单
            if UIDROPDOWNMENU_MENU_LEVEL > 1 then return end

            RightF:Hide()
            if not featureEnabled then return end

            local shouldShow = false
            local menuName = dropdownMenu:GetName()

            -- 判定显示条件
            if menuName == "FriendsDropDown" and
                (which == "FRIEND" or which == "CHAT_ROSTER" or which == "RAID") then
                shouldShow = true
            elseif which == "CHAT_ROSTER" then
                shouldShow = true
            elseif (menuName == "TargetFrameDropDown" or which == "TARGET") and
                UnitIsPlayer(unit) then
                shouldShow = true
            elseif which == "PLAYER" or which == "PARTY" or which ==
                "RAID_PLAYER" then
                shouldShow = true
            end

            if shouldShow then
                RightF:Show()
                UpdateRightFrame()
            end
        end)

        -- 菜单关闭时的清理
        if DropDownList1 then
            DropDownList1:HookScript("OnHide", function()
                RightF:Hide()
                DropDownList1.RF = nil
            end)

            -- 防止计时器自动关闭菜单 (当鼠标在侧边栏时)
            DropDownList1:SetScript("OnUpdate", function(self, elapsed)
                if self.shouldRefresh then
                    UIDropDownMenu_RefreshDropDownSize(self)
                    self.shouldRefresh = false
                end
                if self.RF then return end -- 如果鼠标在侧边栏，不执行倒计时关闭

                if not self.showTimer or not self.isCounting then
                    return
                elseif self.showTimer < 0 then
                    self:Hide()
                    self.showTimer = nil
                    self.isCounting = nil
                else
                    self.showTimer = self.showTimer - elapsed
                end
            end)
        end

        -- 侧边栏本身的鼠标事件，用于维持主菜单显示
        RightF:HookScript("OnEnter", function()
            if DropDownList1 then DropDownList1.RF = true end
        end)
        RightF:HookScript("OnLeave", function()
            if DropDownList1 then DropDownList1.RF = nil end
        end)
    end

    initialized = true
    return true
end

local function SetFeatureEnabled(enabled)
    featureEnabled = enabled == true

    if featureEnabled then
        InitNewRightPlus()
        return
    end

    if legacyRightFrame then
        legacyRightFrame:Hide()
    end
    if DropDownList1 then
        DropDownList1.RF = nil
    end
end

Components:RegisterFeature("RightPlus", {
    name = L["feature.name"],
    description = L["feature.description"],
    default = false,
    callback = SetFeatureEnabled,
})

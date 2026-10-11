local ADDON_NAME, YUI = ...
local LC = YUI.Locale:Get("Core")
local GUI2 = YUI.GUI2
local Assets = YUI.Assets
local FrameAPI = (YUI.API and YUI.API.Frame) or YUI.WOW_API or {}

if not YUI.IsRetail and not YUI.IsWrath and not YUI.IsForever then return end

local Feature = nil
local featureEnabled = false
local menuHooked = false

local function CloseGameMenu()
    local closed, reason
    if FrameAPI.HideGameMenu then
        closed, reason = FrameAPI.HideGameMenu()
    elseif type(InCombatLockdown) == "function" and InCombatLockdown() then
        closed, reason = false, "IN_COMBAT"
    elseif not GameMenuFrame then
        closed, reason = false, "NO_FRAME"
    elseif not GameMenuFrame:IsShown() then
        closed, reason = true, "ALREADY_HIDDEN"
    else
        local hide = GameMenuFrame.Hide
        local ok = type(hide) == "function" and pcall(hide, GameMenuFrame)
        closed = ok and not GameMenuFrame:IsShown()
        reason = closed and "FALLBACK" or "HIDE_FAILED"
    end

    if not closed and reason == "IN_COMBAT" and type(YUI.Print) == "function" then
        YUI:Print(LC["game_menu.text.001"])
    end

    return closed, reason
end

local function Init() 
    if YUI.IsRetail then 
        Feature = {
            name = LC["game_menu.text.002"],
            default = true,
            description = LC["game_menu.text.003"],
            version = "Retail" -- 标记仅支持 Retail
        }
    elseif YUI.IsWrath or YUI.IsForever then
        Feature = {
            name = LC["game_menu.text.002"],
            default = true,
            description = LC["game_menu.text.003"],
        }
    end
end


-- 按钮创建辅助函数
local function CreateGameMenuButton(parent, text, iconPath, onClick, tooltipTitle, tooltipText, iconSizeW, iconSizeH, iconYOffset, tooltipAnchor)
    -- 创建基础按钮 (56x56 正方形)
    local btn = GUI2:CreateButton(parent, "", 56, 56)
    btn.gui2PreserveIconColor = true
    local iconSizeW = iconSizeW or 32
    local iconSizeH = iconSizeH or 32
    local iconYOffset = iconYOffset or -5
    local tooltipAnchor = tooltipAnchor or "ANCHOR_RIGHT"
    
    if iconPath == "ExBoss" then
        -- 用文本当作图标
        local icon = GUI2:CreateText(btn, "", 20)
        icon.gui2ColorKey = nil
        icon.gui2ColorFallback = nil
        icon:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
        icon:SetShadowOffset(1, -1)
        icon:SetShadowColor(0, 0, 0, 1)
        icon:SetPoint("CENTER", 0, 5)
        icon:SetText("|cFFFF0000Ex|r")
        btn.icon = icon
    else
        -- 添加图标 (32x32, 顶部居中)
        local icon = GUI2:CreateTexture(btn, { layer = "ARTWORK", texture = iconPath })
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetSize(iconSizeW, iconSizeH)
        icon:SetPoint("TOP", 0, iconYOffset)
        btn.icon = icon
    end
    
    -- 添加文本 (底部居中, 4个汉字)
    local fs = GUI2:CreateText(btn, text, 12)
    fs.gui2ColorKey = nil
    fs.gui2ColorFallback = nil
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    -- 保持单行自动宽度，并向右补偿 1 像素的中文字形视觉偏移。
    fs:SetPoint("BOTTOM", 1, 2)
    fs:SetTextColor(1, 0.82, 0) -- 金色
    btn.textLabel = fs
    
    -- 点击事件
    if onClick then
        btn:SetScript("OnClick", onClick)
    end
    
    -- 悬停提示与高亮
    btn:HookScript("OnEnter", function(self)
        if tooltipTitle then
            GameTooltip:SetOwner(self, tooltipAnchor)
            GameTooltip:AddLine(tooltipTitle, 1, 0.82, 0)
            if tooltipText then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
        self.textLabel:SetTextColor(1, 1, 1) -- 白色高亮
    end)
    
    btn:HookScript("OnLeave", function(self)
        YUI.HideGameTooltip()
        self.textLabel:SetTextColor(1, 0.82, 0) -- 恢复金色
    end)
    
    return btn
end

local function CreateBlizzardCooldownButton(parent, anchor)
    local button = CreateGameMenuButton(parent, LC["game_menu.short.cooldowns"],
        Assets:Core("images\\icons\\ycolor\\cooldown_manager_g12_128.png"),
        function()
            if not CloseGameMenu() then return end
            if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
                C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
            end
            if CooldownViewerSettings then
                CooldownViewerSettings:Show()
            else
                print(LC["game_menu.text.016"])
            end
        end,
        LC["game_menu.text.015"], LC["game_menu.text.017"], 36, 36, -5
    )
    button:SetPoint("TOP", anchor, "BOTTOM", 0, -10)
    return button
end

-- 创建并显示游戏菜单顶部 LOGO
local function InitGameMenuLogo()
    if not GameMenuFrame then return end
    if _G["YUIGameMenuLogo"] then
        _G["YUIGameMenuLogo"]:Show()
        return
    end

    --[[
    -- 文字 LOGO，保留以便后续恢复。
    local textLogo = GUI2:CreateText(GameMenuFrame, "", 40)
    textLogo.gui2ColorKey = nil
    textLogo.gui2ColorFallback = nil
    _G["YUIGameMenuLogo"] = textLogo
    textLogo:SetFont(STANDARD_TEXT_FONT, 40, "OUTLINE") -- 增大字体
    textLogo:SetShadowOffset(1, -1)
    textLogo:SetShadowColor(0, 0, 0, 1)
    textLogo:SetPoint("TOP", GameMenuFrame, "TOP", 0, 100) -- 恢复原来的位置
    textLogo:SetText("|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r")
    textLogo:Show()
    ]]

    local logo = GUI2:CreateTexture(GameMenuFrame, {
        layer = "ARTWORK",
        texture = Assets:Core("images\\yui-logo-game-384w.png"),
    })
    _G["YUIGameMenuLogo"] = logo
    logo:SetSize(144, 72)
    logo:SetPoint("TOP", GameMenuFrame, "TOP", 0, 108)
    logo:Show()
end

local function HideGameMenuLogo()
    if _G["YUIGameMenuLogo"] then
        _G["YUIGameMenuLogo"]:Hide()
    end
end

local function GetEnabledHaloDesigner()
    local yhud = YUI.YHUD
    if featureEnabled and yhud and type(yhud.IsEnabled) == "function"
        and yhud:IsEnabled() == true and yhud.DesignerUI
        and type(yhud.DesignerUI.Open) == "function" then
        return yhud.DesignerUI
    end
end

local function RefreshHaloButton()
    local rightFrame = _G.YUIGameMenuRightContainer
    if not (rightFrame and rightFrame.haloButtonAnchor) then return end
    local designer = GetEnabledHaloDesigner()
    local button = rightFrame.haloButton
    if designer and not button then
        button = CreateGameMenuButton(rightFrame, LC["game_menu.short.auras"],
            Assets:Core("images\\icons\\ycolor\\cooldown_style_g12_128.png"),
            function()
                local currentDesigner = GetEnabledHaloDesigner()
                if currentDesigner and CloseGameMenu() then currentDesigner:Open("settings") end
            end,
            LC["game_menu.text.013"], LC["game_menu.text.014"], 36, 36, -5
        )
        button:SetPoint("TOP", rightFrame.haloButtonAnchor, "BOTTOM", 0, -10)
        rightFrame.haloButton = button
    end
    if button then
        if designer then button:Show() else button:Hide() end
    end
    local following = rightFrame.haloFollowingButton
    if following then
        following:ClearAllPoints()
        following:SetPoint("TOP", designer and button or rightFrame.haloButtonAnchor, "BOTTOM", 0, -10)
    end
end

local function OnHaloStateChanged(_, id)
    if id == "yhud" then RefreshHaloButton() end
end

local function InitGameMenu()
    if not GameMenuFrame then return end

    if _G["YUIGameMenuLeftContainer"] then 
        _G["YUIGameMenuLeftContainer"]:Show()
        _G["YUIGameMenuRightContainer"]:Show()
        RefreshHaloButton()
        return 
    end

    

    -- 切换配置函数
    local SAM = _G.SimpleAddonManager
    local switchAddons = function(profileName)
        if SAM then
            local profileModule = SAM:GetModule("Profile")
            if profileModule then
                profileModule:LoadAddonsFromProfile(profileName, false)
                ReloadUI() 
            end
        else
            print(LC["game_menu.text.004"])
        end
    end

    -- 1. 左侧容器 (ElvUI, NDUI, EQoL)
    local leftFrame = GUI2:CreateFrame(GameMenuFrame, { name = "YUIGameMenuLeftContainer" })
    leftFrame:SetSize(60, 120)
    -- 初始锚点，Hook Show 后会调整
    leftFrame:SetPoint("TOPRIGHT", GameMenuFrame, "TOPLEFT", -5, 0)

    --[[ 暂时停用左侧 3 个界面方案切换按钮，保留实现供后续重新启用。
    if YUI.IsRetail then
        -- [ElvUI] 按钮
        local getStarts = function(star, atlas) 
            -- local starts = ""
            -- for i = 1, star do
            --     starts = starts .. YUI.F:GetAtlasString(atlas, 16, 16, 0, 1)
            -- end
            -- return starts
            if star <= 3 then
                return string.format("|cff00ff00%d|r", star)
            elseif star == 4 then
                return string.format("|cffa335ee%d|r", star)
            else
                return string.format("|cffff8000%d|r", star)
            end
        end
    
        local elvBtn = CreateGameMenuButton(leftFrame, "ElvUI", 
            Assets:Core("images\\ElvUI.tga"),
            function()
                YUI.Settings:ShowConfirmPopup("确定要切换到 ElvUI 配置吗？\n注意：这将重新加载界面，请确保已保存所有更改。", function()
                        switchAddons("YUI-ElvUI") 
                        if BLINKIISPORTRAITS and BLINKIISPORTRAITS.db then
                            BLINKIISPORTRAITS.db:SetProfile("YUI-ElvUI")
                        end
                    end, { titleText = "切换界面配置", acceptTone = "warning" })
            end,
            "切换到 ElvUI 界面", string.format("美观度：%s\n可玩性：%s\n流畅度：%s", getStarts(4, "Barbershop-32x32"), getStarts(5, "Vehicle-HammerGold"), getStarts(3, "dragonriding-winds")), 32, 32, -5, "ANCHOR_LEFT"
        )
        elvBtn:SetPoint("TOP", leftFrame, "TOP", 0, 0)
    
        -- [NDUI] 按钮
        local nduiBtn = CreateGameMenuButton(leftFrame, "NDUI",
            Assets:Core("images\\NDUI.tga"),
            function()
                YUI.Settings:ShowConfirmPopup("确定要切换到 NDUI 配置吗？\n注意：这将重新加载界面，请确保已保存所有更改。", function()
                        switchAddons("YUI-NDUI")
                        if BLINKIISPORTRAITS and BLINKIISPORTRAITS.db then
                            BLINKIISPORTRAITS.db:SetProfile("YUI-NDUI")
                        end
                    end, { titleText = "切换界面配置", acceptTone = "warning" })
            end,
            "切换到 NDUI 界面", string.format("美观度：%s\n可玩性：%s\n流畅度：%s", getStarts(4, "Barbershop-32x32"), getStarts(4, "Vehicle-HammerGold"), getStarts(4, "dragonriding-winds")), 32, 16, -15, "ANCHOR_LEFT"
        )
        nduiBtn:SetPoint("TOP", elvBtn, "BOTTOM", 0, -10)
    
        -- [EQoL] 按钮
        local eqolBtn = CreateGameMenuButton(leftFrame, "EQoL",
            Assets:Core("images\\EQoL.tga"),
            function()
                YUI.Settings:ShowConfirmPopup("确定要切换到 EQoL 配置吗？\n注意：这将重新加载界面，请确保已保存所有更改。", function()
                        switchAddons("YUI-EQoL")
                        if BLINKIISPORTRAITS and BLINKIISPORTRAITS.db then
                            BLINKIISPORTRAITS.db:SetProfile("YUI-EQoL")
                        end
                    end, { titleText = "切换界面配置", acceptTone = "warning" })
            end,
            "切换到 EQoL 原生界面", string.format("美观度：%s\n可玩性：%s\n流畅度：%s", getStarts(4, "Barbershop-32x32"), getStarts(3, "Vehicle-HammerGold"), getStarts(5, "dragonriding-winds")), 24, 24, -10, "ANCHOR_LEFT"
        )
        eqolBtn:SetPoint("TOP", nduiBtn, "BOTTOM", 0, -10)
    end
    --]]


    -- 2. 右侧容器 (一键安装, YUI设置, 暴雪冷却)
    local rightFrame = GUI2:CreateFrame(GameMenuFrame, { name = "YUIGameMenuRightContainer" })
    rightFrame:SetWidth(60)
    -- 让右侧容器高度与 GameMenuFrame 保持一致，这样 BOTTOM 锚点才是真正的底部
    rightFrame:SetPoint("TOPLEFT", GameMenuFrame, "TOPRIGHT", 5, 0)
    rightFrame:SetPoint("BOTTOMLEFT", GameMenuFrame, "BOTTOMRIGHT", 5, 0)

    if YUI.IsForever then
        local installBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.setup"],
            Assets:Core("images\\icons\\ycolor\\install_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                if YUI.Installer and YUI.Installer.Show then YUI.Installer:Show() end
            end,
            LC["game_menu.text.005"], LC["game_menu.text.007"], 36, 36, -5
        )
        installBtn:SetPoint("TOP", rightFrame, "TOP", 0, 0)
        local settingsBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.settings"],
            Assets:Core("images\\icons\\ycolor\\settings_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                if YUI.Settings and YUI.Settings.Toggle then
                    YUI.Settings:Toggle()
                end
            end,
            LC["game_menu.text.009"], LC["game_menu.text.010"], 36, 36, -5
        )
        settingsBtn:SetPoint("TOP", installBtn, "BOTTOM", 0, -10)
        rightFrame.haloButtonAnchor = settingsBtn
        local cdBtn = CreateBlizzardCooldownButton(rightFrame, settingsBtn)
        rightFrame.haloFollowingButton = cdBtn
        if C_AddOns and C_AddOns.IsAddOnLoaded("Platynator") then
            local platyBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.nameplates"],
                "Interface\\AddOns\\Platynator\\Assets\\logo.tga",
                function()
                    if not CloseGameMenu() then return end
                    YUI.WOW_API.RunSlashCmd("/platy")
                end,
                LC["game_menu.text.021"], LC["game_menu.text.022"], 36, 36, 0
            )
            platyBtn:SetPoint("TOP", cdBtn, "BOTTOM", 0, -10)
        end
    elseif YUI.IsRetail then
        -- [一键安装] 按钮
        local installBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.setup"],
            Assets:Core("images\\icons\\ycolor\\install_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                if YUI.Installer and YUI.Installer.Show then
                    YUI.Installer:Show()
                else
                    print(LC["game_menu.text.006"])
                end
            end,
            LC["game_menu.text.005"], LC["game_menu.text.007"], 36, 36, -5
        )
        installBtn:SetPoint("TOP", rightFrame, "TOP", 0, 0)
    
        -- [YUI设置] 按钮
        local settingsBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.settings"],
            Assets:Core("images\\icons\\ycolor\\settings_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                if YUI.Settings and YUI.Settings.Toggle then
                    YUI.Settings:Toggle()
                end
            end,
            LC["game_menu.text.009"], LC["game_menu.text.010"], 36, 36, -5
        )
        settingsBtn:SetPoint("TOP", installBtn, "BOTTOM", 0, -10)
    
        -- [常见问题] 按钮
        local qaBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.faq"],
            Assets:Core("images\\icons\\ycolor\\faq_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                YUI:OpenSettings("常见问题")
            end,
            LC["game_menu.text.011"], LC["game_menu.text.012"], 36, 36, -5
        )
        qaBtn:SetPoint("TOP", settingsBtn, "BOTTOM", 0, -10)
    
        rightFrame.haloButtonAnchor = qaBtn

        -- [暴雪冷却] 按钮
        local cdBtn = CreateBlizzardCooldownButton(rightFrame, qaBtn)
        rightFrame.haloFollowingButton = cdBtn
        local lastRightBtn = cdBtn
    
        -- [首领警报] 按钮
        if C_AddOns.IsAddOnLoaded("EXBoss") then
            local bossBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.boss"],
                Assets:Core("images\\icons\\ycolor\\boss_alert_g12_128.png"),
                function()
                    if not CloseGameMenu() then return end
                    YUI.WOW_API.RunSlashCmd("/exboss")
                end,
                LC["game_menu.text.018"], LC["game_menu.text.019"], 36, 36, -5
            )
            -- 定位到游戏菜单右下角 (相对于 rightFrame)
            bossBtn:SetPoint("TOP", cdBtn, "BOTTOM", 0, -10)
            lastRightBtn = bossBtn
        end

        -- [Platynator] 按钮
        if C_AddOns.IsAddOnLoaded("Platynator") then
            local platyBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.nameplates"],
                "Interface\\AddOns\\Platynator\\Assets\\logo.tga",
                function()
                    if not CloseGameMenu() then return end
                    YUI.WOW_API.RunSlashCmd("/platy")
                end,
                LC["game_menu.text.021"], LC["game_menu.text.022"], 36, 36, 0
            )
            platyBtn:SetPoint("TOP", lastRightBtn, "BOTTOM", 0, -10)
        end
    elseif YUI.IsWrath then
        -- [语音提醒] 按钮
        local soundBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.voice"],
            Assets:Core("images\\icons\\ycolor\\voice_alert_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                YUI:OpenSettings("语音提醒")
            end,
            LC["game_menu.text.023"], LC["game_menu.text.024"], 36, 36, -5
        )
        soundBtn:SetPoint("TOP", rightFrame, "TOP", 0, 0)
    
        -- [YUI设置] 按钮
        local settingsBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.settings"],
            Assets:Core("images\\icons\\ycolor\\settings_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                if YUI.Settings and YUI.Settings.Toggle then
                    YUI.Settings:Toggle()
                end
            end,
            LC["game_menu.text.009"], LC["game_menu.text.010"], 36, 36, -5
        )
        settingsBtn:SetPoint("TOP", soundBtn, "BOTTOM", 0, -10)
    
        -- [常见问题] 按钮
        local qaBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.faq"],
            Assets:Core("images\\icons\\ycolor\\faq_g12_128.png"),
            function()
                if not CloseGameMenu() then return end
                YUI:OpenSettings("常见问题")
            end,
            LC["game_menu.text.011"], LC["game_menu.text.012"], 36, 36, -5
        )
        qaBtn:SetPoint("TOP", settingsBtn, "BOTTOM", 0, -10)

        -- [Platynator] 按钮
        if C_AddOns.IsAddOnLoaded("Platynator") then
            local platyBtn = CreateGameMenuButton(rightFrame, LC["game_menu.short.nameplates"],
                "Interface\\AddOns\\Platynator\\Assets\\logo.tga",
                function()
                    if not CloseGameMenu() then return end
                    YUI.WOW_API.RunSlashCmd("/platy")
                end,
                LC["game_menu.text.021"], LC["game_menu.text.022"], 36, 36, 0
            )
            platyBtn:SetPoint("TOP", qaBtn, "BOTTOM", 0, -10)
        end
    end
    RefreshHaloButton()
end


Init()

function Feature.callback(enable)
    local wasEnabled = featureEnabled
    featureEnabled = enable == true
    if enable then
        if YUI.IsRetail or YUI.IsForever then
            InitGameMenuLogo()
        end
        InitGameMenu()
        if (YUI.IsRetail or YUI.IsForever) and GameMenuFrame and not menuHooked then
            GameMenuFrame:HookScript("OnShow", RefreshHaloButton)
            menuHooked = true
        end
        if (YUI.IsRetail or YUI.IsForever) and not wasEnabled and YUI.Event then
            YUI.Event:On("YUI_MODULE_ENABLED", OnHaloStateChanged, Feature)
            YUI.Event:On("YUI_MODULE_DISABLED", OnHaloStateChanged, Feature)
        end
        if _G["YUIGameMenuLeftContainer"] then 
            _G["YUIGameMenuLeftContainer"]:Show()
            _G["YUIGameMenuRightContainer"]:Show()
        end
    else
        if YUI.Event then YUI.Event:OffOwner(Feature) end
        RefreshHaloButton()
        if YUI.IsRetail or YUI.IsForever then
            HideGameMenuLogo()
        end
        if _G["YUIGameMenuLeftContainer"] then 
            _G["YUIGameMenuLeftContainer"]:Hide()
            _G["YUIGameMenuRightContainer"]:Hide()
        end
    end
end

-- 如需额外兜底，可通过 YUI.Event:On("YUI_WORLD_READY", ...) 确保 LOGO 在不启用模块时也能显示
-- local f = CreateFrame("Frame")
-- f:RegisterEvent("PLAYER_ENTERING_WORLD")
-- f:SetScript("OnEvent", function()
--     InitGameMenuLogo()
-- end)

YUI.Components:RegisterFeature("GameMenuButtons", Feature)

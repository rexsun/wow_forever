local YUI = _G.YUI
local CL = YUI.Changelog or {}
YUI.Changelog = CL
local Assets = YUI.Assets
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}

-- 缓存
local ipairs, pairs = ipairs, pairs
local tinsert = table.insert
local CreateFrame = CreateFrame
local C_Timer = C_Timer

-- 模块变量
local frame = nil

-- 创建弹窗
function CL:CreatePopup(version)
    -- 确保 GUI 模块可用
    local GUI2 = YUI.GUI2
    if not GUI2 then return end

    local f = GUI2:CreateButtonFrame(UIParent, {
        name = "YUI_UpdatePopup",
        template = "BackdropTemplate",
        width = 300,
        height = 80,
        movable = true,
        drag = "LeftButton",
    })
    f:SetPoint("LEFT", 50, 0)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    GUI2:ApplyBackdrop(f, "color.surface.popup")
    
    GUI2:CreateBorder(f, "color.popup.border")
    GUI2:CreateShadow(f)
    
    -- Icon
    local icon = GUI2:CreateTexture(f, {
        texture = Assets and Assets.Core and Assets:Core("images\\YUI-LOGO-300.png") or "Interface\\AddOns\\YUI\\Media\\Core\\images\\YUI-LOGO-300.png",
        layer = "ARTWORK",
    })
    icon:SetSize(48, 48)
    icon:SetPoint("LEFT", 15, 0)
    
    -- Title
    local title = GUI2:CreateText(f, LC["settings.changelog.popup_title"], "font.size.lg", "color.text.heading")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 15, -5)
    
    -- Subtext
    local sub = GUI2:CreateText(f, string.format(LC["settings.changelog.popup_subtext"], version), "font.size.md", "color.text.primary")
    sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 15, 5)
    
    -- StatusBar 是 WoW 原生控件，保留原生创建并由 GUI2 提供纹理/颜色。
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(300, 4)
    bar:SetPoint("BOTTOM", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(GUI2:GetColor("color.accent.primary"))
    bar:SetMinMaxValues(0, 10)
    bar:SetValue(10)
    
    -- Make sure it's shown and interactive
    f:SetAlpha(0) -- Start invisible for fade-in
    f:Show()
    f:EnableMouse(true)
    
    -- Debug position
    f:ClearAllPoints()
    f:SetPoint("LEFT", 50, 0)
    
    -- Click Handler
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", function(self, button)
        CL:MarkAsSeen(version)
        f:Hide()
        
        if button == "LeftButton" then
            -- Open Settings
            if YUI.Settings and YUI.Settings.Toggle then
                YUI.Settings:Toggle()
                -- Select Changelog module
                local module = YUI.Settings.modulesById and YUI.Settings.modulesById["core.changelog"]
                if module then
                    YUI.Settings:SelectModule(module)
                end
            end
        end
        -- RightButton just closes and marks as seen (handled above)
    end)
    
    -- Hover Effect
    f:SetScript("OnEnter", function(self)
        self.gui2Surface = "color.control.hover"
        GUI2:RefreshPrimitive(self)
        GUI2:SetBorderColor(self, "color.popup.border")
    end)
    f:SetScript("OnLeave", function(self)
        self.gui2Surface = "color.surface.popup"
        GUI2:RefreshPrimitive(self)
        GUI2:SetBorderColor(self, "color.popup.border")
    end)
    
    -- Timer Logic
    local timeLeft = 10
    local isCounting = false -- 等待动画播放完再开始倒计时
    local isFadingOut = false -- 正在淡出
    
    -- Animation
    f.fadeInGroup = f:CreateAnimationGroup()
    local fadeIn = f.fadeInGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(1.5) -- 增加到1.5秒以便观察
    fadeIn:SetSmoothing("OUT")
    f.fadeInGroup:SetScript("OnFinished", function() 
        f:SetAlpha(1)
        isCounting = true 
    end)
    f.fadeInGroup:Play()
    
    -- Fade Out Animation
    f.fadeOutGroup = f:CreateAnimationGroup()
    local fadeOut = f.fadeOutGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1.5)
    fadeOut:SetSmoothing("OUT")
    f.fadeOutGroup:SetScript("OnFinished", function()
        CL:MarkAsSeen(version)
        f:Hide()
    end)
    
    f:SetScript("OnUpdate", function(self, elapsed)
        if not isCounting or isFadingOut then return end
        
        -- 鼠标悬停时暂停倒计时
        if self:IsMouseOver() then return end
        
        timeLeft = timeLeft - elapsed
        bar:SetValue(timeLeft)
        if timeLeft <= 0 then
            isFadingOut = true
            f.fadeOutGroup:Play()
        end
    end)
    
    -- print("|cff00ffff[YUI]|r 检测到新版本: " .. version)
end

-- 检查版本
function CL:CheckVersion()
    -- 获取最新版本
    local data = self:GetData()
    if not data or #data == 0 then return end
    
    local latestVer = data[1].version
    
    -- 获取上次检查的版本
    local lastVer = YUI.global and YUI.global.lastChangelogVersion
    
    -- 首次运行（无记录），直接记录当前版本，不弹窗
    if not lastVer then
        if YUI.global then
            YUI.global.lastChangelogVersion = latestVer
        end
        return
    end
    
    -- 比较
    local compareResult = self:CompareVersion(latestVer, lastVer)
    
    -- Dev模式下只要版本不同(包括降级)都显示，方便调试
    -- 正常模式下只显示新版本
    --if compareResult > 0 or YUI.IsDev then
    if compareResult > 0 then
        -- 延迟显示，确保 UI 加载完毕
        C_Timer.After(8, function()
            self:CreatePopup(latestVer)
        end)
    end
end

-- 初始化事件监听
local function Initialize()
    if not YUI.Event then return end

    YUI.Event:Once("PLAYER_ENTERING_WORLD", function()
        -- 尝试检查版本
        if YUI.global then
            CL:CheckVersion()
        else
            print("|cff00ffff[YUI]|r DB not ready, retrying...")
            -- 如果 DB 还没好（极低概率），延迟重试
            C_Timer.After(1, function()
                if YUI.global then CL:CheckVersion() end
            end)
        end
    end)
end

Initialize()

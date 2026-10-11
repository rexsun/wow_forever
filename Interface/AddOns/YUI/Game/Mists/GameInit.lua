local ADDON_NAME, YUI = ...

function YUI:prepareDBAndSettings()
    local LibBlzSettings = LibStub("LibBlzSettings-1.0")

    -- 创建自定义面板
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(1, 1) -- 需要设置大小，否则可能无法正确显示内容
    panel:Hide()

    panel.OnCommit = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function() end

    -- 标题 YUI (渐变色)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("CENTER", 0, 100)
    title:SetText("|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r")

    -- 尝试获取字体，如果 STANDARD_TEXT_FONT 不存在则使用备用
    local fontPath = STANDARD_TEXT_FONT
    if not fontPath then
        local font, _, _ = GameFontNormal:GetFont()
        fontPath = font
    end
    title:SetFont(fontPath, 64, "OUTLINE")

    -- /yui
    local slashText = panel:CreateFontString(nil, "ARTWORK",
                                             "GameFontNormalLarge")
    slashText:SetPoint("CENTER", 0, -50)
    slashText:SetText("/yui")
    slashText:SetFont(fontPath, 40, "OUTLINE")
    slashText:SetTextColor(1, 0.8, 0, 1) -- Goldish

    -- 按钮
    local btn = YUI.Settings:CreateButton(panel, "打开设置页面", 280, 56)
    btn:SetPoint("TOP", slashText, "BOTTOM", 0, -30)
    btn.text:SetFont(fontPath, 18) -- 更大的字体

    btn:SetScript("OnClick", function()
        -- 如果 Settings 模块已加载
        if YUI.Settings and YUI.Settings.Toggle then
            YUI.Settings:Toggle()
        else
            print("YUI 设置模块未加载")
        end

        -- 延迟关闭，避免状态卡死
        C_Timer.After(0.01, function()
            if SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
        end)
    end)

    -- Pass the frame to LibBlzSettings
    local settings = {
        name = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r 帮助与设置 ",
        frame = panel
    }

    local settingsDB = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile(YUI.ProductId or "suite") or {}
    LibBlzSettings:RegisterVerticalSettingsTable(ADDON_NAME, settings, settingsDB,
                                                 true)
end

local function OnGameInitEvent(event, ...)
    if event == "YUI_DB_READY" then
        if YUI.Trace and YUI.Trace.Measure then
            YUI.Trace:Measure("Framework", "GameInit settings", function()
                YUI:prepareDBAndSettings()
            end, "mists", {
                moduleId = "GameInit",
                phase = "settings",
            })
        else
            YUI:prepareDBAndSettings()
        end

    elseif event == "YUI_WORLD_READY" then
        local function UpdateWorldState()
            YUI.Player.Name = UnitName("player")
            YUI.Player.Server = GetRealmName()
            YUI.Player.Class, _ = select(2, UnitClass("player"))
        end
        if YUI.Trace and YUI.Trace.Measure then
            YUI.Trace:Measure("World", "GameInit player state", UpdateWorldState, "mists", {
                moduleId = "GameInit",
                phase = "player state",
            })
        else
            UpdateWorldState()
        end
    end
end

YUI.Event:On("YUI_DB_READY", OnGameInitEvent, nil, {
    priority = 6000,
    traceName = "GameInit:YUI_DB_READY",
    moduleId = "GameInit",
    phase = "YUI_DB_READY",
})
YUI.Event:On("YUI_WORLD_READY", OnGameInitEvent, nil, {
    priority = 6000,
    traceName = "GameInit:YUI_WORLD_READY",
    moduleId = "GameInit",
    phase = "YUI_WORLD_READY",
})

-- 注册 Slash 命令
SLASH_YUI1 = "/yui"
SlashCmdList["YUI"] = function(msg)
    -- First try to handle via Installer's command handler if available
    if YUI.HandleSlashCommand and YUI:HandleSlashCommand(msg) then
        return
    end
    
    -- Fallback to toggling Settings window
    YUI.Settings:Toggle()
end

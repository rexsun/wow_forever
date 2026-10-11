local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local LC = YUI.Locale:Get("Core")

-- Color Presets
local C_LEGENDARY_1 = {1, 0.5, 0} -- Orange
local C_LEGENDARY_2 = {1, 0.84, 0}   -- Gold

local C_EPIC_1 = {0.64, 0.21, 0.93} -- Epic Purple
local C_EPIC_2 = {0.9, 0.4, 1}        -- Lighter Purple

local C_RARE_1 = {0, 0.44, 0.87} -- Rare Blue
local C_RARE_2 = {0, 0.8, 1}     -- Cyan

local C_UNCOMMON_1 = {0.12, 1.00, 0.00} -- Green
local C_UNCOMMON_2 = {0.00, 0.60, 0.00} -- Darker Green

local function GetConfig()
    local F = YUI.F
    local config = {
        { type = "header", label = LC["settings.credits.title"] },
        { type = "space", height = 5 },
    }
    
    -- 1. Partners
    table.insert(config, { type = "divider", label = LC["settings.credits.partners"], alignLeft = false, width = 600 })
    table.insert(config, { type = "text", label = LC["settings.credits.partner_desc"], justify = "LEFT", colorKey = "color.text.secondary", width = 600, wrap = true })
    table.insert(config, { 
        type = "text", 
        label = F:GetGradientText("忘忧景久", C_LEGENDARY_1, C_LEGENDARY_2), 
        justify = "LEFT",
        width = 600,
        style = "header"
    })
    table.insert(config, { type = "space", height = 5 })

    -- 2. Seniors
    table.insert(config, { type = "divider", label = LC["settings.credits.seniors"], alignLeft = false, width = 600 })
    table.insert(config, { type = "text", label = LC["settings.credits.seniors_desc"], justify = "LEFT", colorKey = "color.text.secondary", width = 600, wrap = true })
    table.insert(config, { type = "space", height = 5 })
    
    local seniors = {"露露缇雅", "田园双皮奶", "雨帆灬", "Luxthos", "Merfin"}
    local seniorText = ""
    for i, name in ipairs(seniors) do
        seniorText = seniorText .. F:GetGradientText(name, C_EPIC_1, C_EPIC_2)
        if i < #seniors then seniorText = seniorText .. "   " end
    end
    table.insert(config, { type = "text", label = seniorText, justify = "LEFT", width = 600 })
    table.insert(config, { type = "space", height = 5 })

    -- 3. Addons
    table.insert(config, { type = "divider", label = LC["settings.credits.addons"], alignLeft = false, width = 600 })
    table.insert(config, { type = "text", label = LC["settings.credits.addons_desc"], justify = "LEFT", colorKey = "color.text.secondary", width = 600, wrap = true })
    table.insert(config, { type = "space", height = 5 })
    
    local addons = {"ToxiUI", "WindTools", "CharacterStats", "TeleportMenu", "HDSkada", "Leatrix Plus", "!Pig"}
    local addonText = ""
    for i, name in ipairs(addons) do
        addonText = addonText .. F:GetGradientText(name, C_RARE_1, C_RARE_2)
        if i < #addons then addonText = addonText .. "   " end
    end
    table.insert(config, { type = "text", label = addonText, justify = "LEFT", width = 600 })
    table.insert(config, { type = "space", height = 5 })

    -- 4. Players
    table.insert(config, { type = "divider", label = LC["settings.credits.players"], alignLeft = false, width = 600 })
    table.insert(config, { type = "text", label = LC["settings.credits.players_desc"], justify = "LEFT", colorKey = "color.text.secondary", width = 600, wrap = true })
    table.insert(config, { type = "space", height = 5 })
    
    local players = {"创世群", "银河群", "内测组", "梁总", "游佐悠", "蛋蛋", "橘神", "牛排排", "神我人", "不出围城", "Eason", "鸡哥", "张老师不熬夜", "张诗扶", "Manjusaka", "夜", "重庆小面匠", "老司基", "SecondLift", "陈野", "等待", "一蓑烟雨任平生", "冰雪欢欢", "李汐穹", "月落烏啼", "萤火悲歌", "Seven丨自由", "力量似闪电", "魔兽冠希", "shenqh", "葱苗", "高冷蛋黄酥"}
    local playerText = ""
    for i, name in ipairs(players) do
        playerText = playerText .. name --F:GetGradientText(name, C_UNCOMMON_1, C_UNCOMMON_2)
        if i < #players then playerText = playerText .. "   " end
    end
    playerText = playerText .. LC["settings.credits.players_suffix"]

    playerText = F:GetGradientText(playerText, C_UNCOMMON_1, C_UNCOMMON_2)
    
    table.insert(config, { type = "text", label = playerText, justify = "LEFT", width = 600 })
    
    return config
end

local function Render(parent)
    S:RenderConfig(parent, GetConfig())
end

S:RegisterModule("Credits", "Interface\\Icons\\INV_Misc_Note_02", Render, { id = "core.credits", product = "core", scope = "core", suiteOnly = true, titleKey = "settings.modules.credits" })

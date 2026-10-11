local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local CL = YUI.Changelog
local F = YUI.F
local LC = YUI.Locale:Get("Core")
local MAX_VISIBLE_VERSIONS = 10

local GOLD_1 = { 1, 0.50, 0 }
local GOLD_2 = { 1, 0.84, 0 }
local PURPLE_1 = { 0.64, 0.21, 0.93 }
local PURPLE_2 = { 0.90, 0.40, 1 }

local v200GoldLines = {
    ["历经180+次迭代，这不是一次普通的更新"] = true,
    ["而是为YUI未来10年的插件发展打好地基"] = true,
}

local v200PurpleLines = {
    ["Slow is fast"] = true,
    ["Less is more"] = true,
}

local function ApplyLineStyle(log, line, labelText)
    if not F or not F.GetGradientText or not log or log.version ~= "v200" then
        return labelText
    end

    if v200GoldLines[line] then
        return F:GetGradientText(labelText, GOLD_1, GOLD_2)
    end

    if v200PurpleLines[line] then
        return F:GetGradientText(labelText, PURPLE_1, PURPLE_2)
    end

    return labelText
end

-- 3. Get Config
local function GetConfig()
    local config = {
        { type = "header", label = LC["settings.changelog.title"] },
        { type = "space", height = 10 },
    }
    
    -- 从 Core 模块获取数据
    -- 注意：Settings 模块加载时，CL 可能还未完全初始化，或者 Data 还未加载
    -- GetData() 内部会尝试 LoadData
    local productId = S.ActiveProductId or "suite"
    local data = CL and CL.GetData and CL:GetData(MAX_VISIBLE_VERSIONS, productId) or {}
    
    if #data == 0 then
        -- 如果没有数据，尝试重新加载
        if CL and CL.LoadData then 
             CL:LoadData(productId)
             data = CL:GetData(MAX_VISIBLE_VERSIONS, productId)
        end
    end
    
    if #data == 0 then
        table.insert(config, { type = "text", label = LC["settings.changelog.empty"], colorKey = "color.text.secondary" })
        return config
    end

    if CL:HasUntranslatedHistory(productId) then
        table.insert(config, { type = "text", label = LC["settings.changelog.older_chinese"], colorKey = "color.text.secondary" })
    end
    
    for _, log in ipairs(data) do
        table.insert(config, {
            type = "text",
            label = string.format("|cff00ffff%s|r  |cff888888%s|r", log.version, log.date),
            size = 14, -- 使用固定字号，避免 GUI2.Fonts.size_header 未定义
            justify = "LEFT",
        })
        
        for _, line in ipairs(log.content) do
            local labelText
            if string.sub(line, 1, 1) == " " then
                 labelText = "    " .. line
            else
                 labelText = "  • " .. line
            end
            labelText = ApplyLineStyle(log, line, labelText)
            
            table.insert(config, {
                type = "text",
                label = labelText,
                colorKey = "color.text.primary",
                -- width = 600, -- 移除固定宽度，自适应容器
                justify = "LEFT", -- 左对齐
            })
        end
        
        table.insert(config, { type = "space", height = 15 })
    end
    
    return config
end

-- 4. Render
local function Render(parent)
    S:RenderConfig(parent, GetConfig())
    
    -- 查看日志时，更新最新版本记录
    if CL and CL.GetData then
        local productId = S.ActiveProductId or "suite"
        local data = CL:GetData(nil, productId)
        if data and data[1] then
            CL:MarkAsSeen(data[1].version, productId)
        end
    end
end

-- 7. Register Module
local icon = YUI.IsRetail and 1455684 or 134330
S:RegisterModule("Changelog", icon, Render, {
    id = "core.changelog",
    hidden = true,
    product = "core",
    scope = "core",
    titleKey = "settings.modules.changelog",
})

local YUI = _G.YUI
local S = YUI.Settings
local API = YUI.WOW_API
local CombatAPI = YUI.API and YUI.API.Combat or API
local UnitAPI = YUI.API and YUI.API.Unit or API

-- local WA = YUI.WA -- Removed early binding
local C_LEGENDARY_1 = {1, 0.5, 0} -- Orange
local C_LEGENDARY_2 = {1, 0.84, 0}   -- Gold

-- Only load in Wrath
if YUI.GameVersion ~= "Wrath" then return end

-- Default Group IDs (Array)
-- 默认分组 ID 列表
local DEFAULT_GROUPS_ID = {
    "!YUI · 语音 · 通用（有图形）",
    "!YUI · 语音 · 通用（无图形）",
    "!YUI · 语音 · 职业",
}

-- 直接获取字符串按指定字符分割后的最后一个元素
-- 参数1：待处理字符串 str
-- 参数2：分割符 sep（单个字符）
-- 返回：最后一个元素
function getLastSplitElement(str, sep)
    -- 处理特殊字符转义（如 " · " 中的点号）
    local pattern = "(.*)" .. sep:gsub("([%.%+%-%%])", "%%%1") .. "(.*)"
    local _, lastPart = str:match(pattern)
    return lastPart or str
end

-- Class Localization Mapping
-- 职业本地化映射表 (Key: 中文名, Value: 英文职业ID)
local CLASS_LOCALE = {
    ["法师"] = "MAGE",
    ["战士"] = "WARRIOR",
    ["潜行者"] = "ROGUE",
    ["盗贼"] = "ROGUE", -- 兼容性
    ["牧师"] = "PRIEST",
    ["德鲁伊"] = "DRUID",
    ["小德"] = "DRUID", -- 兼容性
    ["圣骑士"] = "PALADIN",
    ["骑士"] = "PALADIN", -- 兼容性
    ["萨满祭司"] = "SHAMAN",
    ["萨满"] = "SHAMAN", -- 兼容性
    ["猎人"] = "HUNTER",
    ["术士"] = "WARLOCK",
    ["死亡骑士"] = "DEATHKNIGHT",
    ["死骑"] = "DEATHKNIGHT", -- 兼容性
}

-- Helper to sort class sub-groups
-- 职业子分组排序辅助函数
local function SortClassGroups(parentGroupId, children)
    if parentGroupId ~= "!YUI · 语音 · 职业" then return end
    local playerClass = YUI.Player.Class or select(2, UnitAPI.UnitClass("player"))
    
    table.sort(children, function(a, b)
        local aName = getLastSplitElement(a, " · ")
        local bName = getLastSplitElement(b, " · ")
        
        -- 从中文名获取英文职业 ID
        local aClass = CLASS_LOCALE[aName]
        local bClass = CLASS_LOCALE[bName]
        
        -- 当前职业优先
        if aClass == playerClass and bClass ~= playerClass then return true end
        if bClass == playerClass and aClass ~= playerClass then return false end
        
        -- 按职业ID字母顺序排序
        if aClass and bClass then
            return aClass < bClass
        end
        
        -- 兜底：按显示名称排序
        return aName < bName
    end)
end

-- Helper to get all leaf children recursively
-- 递归获取所有子项
local function GetLeafChildren(groupId, list)
    list = list or {}
    if not WeakAuras or not WeakAuras.GetData then return list end
    
    local data = WeakAuras.GetData(groupId)
    if not data then return list end
    
    if data.controlledChildren and #data.controlledChildren > 0 then
        -- 职业分组排序
        SortClassGroups(groupId, data.controlledChildren)
        
        -- 是分组，添加小标题 & 遍历子项
        table.insert(list, {groupId, "Title"})
        
        for _, childId in ipairs(data.controlledChildren) do
            GetLeafChildren(childId, list)
        end
    else
        -- 是叶子节点，添加到列表
        table.insert(list, {groupId, "Voice"})
    end
    
    return list
end

local function GetConfig()
    local F = YUI.F
    local config = {
        {type = "header", label = "语音提醒"}, {
            type = "text",
            label = "语音包由" .. F:GetGradientText("忘忧景久", C_LEGENDARY_1, C_LEGENDARY_2) .. "|cffffffff独家提供。在此界面设置开关等同于在/wa中设置是否【载入】。",
            colorKey = "color.text.primary"
        }, {
            type = "row",
            children = {
                {
                    type = "button",
                    label = "刷新列表",
                    width = 100,
                    onClick = function(self)
                        -- 刷新逻辑：重新加载当前模块
                        -- 防止连点 (1秒冷却)
                        if self.lastClick and CombatAPI.GetTime() - self.lastClick < 1 then return end
                        self.lastClick = CombatAPI.GetTime()
                        
                        for _, mod in ipairs(S.modules) do
                            if mod.name == "语音提醒" then
                                if mod.frame then
                                    mod.frame:Hide()
                                    mod.frame:SetParent(nil)
                                    mod.frame = nil
                                end
                                S:SelectModule(mod)
                                break
                            end
                        end
                    end
                },
                {
                    type = "button",
                    label = "赞助【忘忧景久】",
                    width = 120,
                    onClick = function(self)
                        YUI.Settings:ShowCopyPopup("赞助【忘忧景久】", "https://afdian.com/a/evorrow")
                    end
                }
            }
        },
        {type = "space", height = 10}
    }

    if not WeakAuras then
        table.insert(config, {
            type = "text",
            label = "未检测到 WeakAuras 插件",
            colorKey = "color.state.danger"
        })
        return config
    end

    local hasAny = false

    for _, rootId in ipairs(DEFAULT_GROUPS_ID) do
        local leaves = {}
        GetLeafChildren(rootId, leaves)

        if #leaves > 0 then
            hasAny = true
            local displayName = getLastSplitElement(rootId, " · ")
            table.insert(config, {
                type = "text",
                label = displayName,
                colorKey = "color.text.heading"
            })
            table.insert(config, {type = "space", height = 5})

            local currentRow = {type = "row", children = {}}
            local itemsPerRow = 3
            local itemWidth = 160

            for i, child in ipairs(leaves) do
                local childId = child[1]
                local childType = child[2]
                local childLabel = getLastSplitElement(childId, " · ")

                if childType == "Title" then
                    -- 如果有未完成的行，先结束它
                    if #currentRow.children > 0 then
                        table.insert(config, currentRow)
                        currentRow = {type = "row", children = {}}
                    end

                    -- 跳过根分组标题（已经在循环外显示了）
                    if childId ~= rootId then
                        local color = {0.6, 0.8, 1} -- 默认浅蓝

                        -- 如果是职业名称，则对文本进行职业染色
                        local classKey = CLASS_LOCALE[childLabel]
                        if classKey then
                            local c = RAID_CLASS_COLORS[classKey]
                            if c then
                                color = {c.r, c.g, c.b}
                            end
                        end

                        local icon = ""
                        if WeakAuras and WeakAuras.GetData then
                            local waData = WeakAuras.GetData(childId)
                            if waData then
                                local waIcon = waData.groupIcon
                                if waIcon then
                                    -- 裁剪边缘
                                    icon = "|T" .. waIcon .. ":14:14:0:2:64:64:4:60:4:60|t "
                                end
                            end
                        end

                        table.insert(config, {type = "space", height = 10})
                        table.insert(config, {
                            type = "text",
                            label = "— " .. icon .. childLabel .. " —",
                            color = color
                        })
                    end

                elseif childType == "Voice" then
                    local icon = ""
                    if WeakAuras and WeakAuras.GetData then
                        local waData = WeakAuras.GetData(childId)
                        if waData then
                            local waIcon = waData.thumbnailIcon
                            if waIcon then
                                -- 裁剪边缘
                                icon = "|T" .. waIcon .. ":14:14:0:0:64:64:4:60:4:60|t "
                            end
                        end
                    end

                    table.insert(currentRow.children, {
                        type = "checkbox",
                        label = icon .. childLabel,
                        width = itemWidth, -- 固定宽度对齐
                        get = function()
                            local never = YUI.WA:GetWeakAuraNever(childId)
                            return not never
                        end,
                        set = function(checked)
                            YUI.WA:SetWeakAuraNever(childId, not checked)
                        end
                    })

                    -- 如果行满了，添加到配置并开始新行
                    if #currentRow.children >= itemsPerRow then
                        table.insert(config, currentRow)
                        currentRow = {type = "row", children = {}}
                    end
                end
            end

            -- 添加最后一行剩余的项目
            if #currentRow.children > 0 then
                table.insert(config, currentRow)
            end
            table.insert(config, {type = "space", height = 15})
        else
            -- 可选：显示空分组消息
        end
    end

    if not hasAny then
        table.insert(config, {
            type = "text",
            label = "未找到相关 WA 分组",
            colorKey = "color.text.secondary"
        })
    end

    return config
end

local function Render(parent) S:RenderConfig(parent, GetConfig()) end

S:RegisterModule("语音提醒", 236709, Render)

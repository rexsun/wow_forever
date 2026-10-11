local _, YUI = ...
local LC = YUI.Locale:Get("Core")
local Components = YUI.Components

local Feature = {
    name = LC["raid_opt.text.001"],
    default = true,
    description = LC["raid_opt.text.002"],
}

local defaults = {
    DisableElvUIPortrait = true,
}

local function GetPortraitState(create)
    if not Components or not Components.GetStoreValue then
        return nil
    end

    local state = Components:GetStoreValue("RaidOpt_ElvUIPortraitState")
    if type(state) ~= "table" and create ~= false then
        state = {}
        Components:SetStoreValue("RaidOpt_ElvUIPortraitState", state)
    end
    return state
end

-- 获取或初始化默认配置
local function GetDB()
    if Components and Components.EnsureConfig then
        return Components:EnsureConfig("RaidOptimization_Config", defaults) or defaults
    end
    return defaults
end

function Feature.GetOptions(feature)
    local db = GetDB()
    return {
        { type = "text", label = LC["raid_opt.text.003"], color = YUI.Settings.Colors.text },
        { type = "space", height = 20 },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = LC["raid_opt.text.004"],
                    tooltip = LC["raid_opt.text.005"],
                    get = function() return db.DisableElvUIPortrait end,
                    set = function(v) db.DisableElvUIPortrait = v end
                },
            }
        }
    }
end

-- 检查是否在团本中
local function IsInRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

-- 禁用 3D 头像并记录状态
local function DisableElvUIPortraits()
    if not C_AddOns.IsAddOnLoaded("ElvUI") then return end
    
    local E = _G.ElvUI and _G.ElvUI[1]
    if not E or not E.db or not E.db.unitframe or not E.db.unitframe.units then return end

    local state = GetPortraitState(true)
    if not state then return end
    local hasChanges = false

    -- 遍历所有单位
    for unitName, unitConfig in pairs(E.db.unitframe.units) do
        if type(unitConfig) == "table" and unitConfig.portrait then
            if unitConfig.portrait.enable and unitConfig.portrait.style == "3D" then
                -- 记录原始状态
                state[unitName] = {
                    enable = true,
                    style = "3D"
                }
                -- 关闭头像
                unitConfig.portrait.enable = false
                hasChanges = true
            end
        end
    end

    if hasChanges then
        YUI:Print(LC["raid_opt.text.006"])
        E:UpdateUnitFrames()
    end
end

-- 恢复 3D 头像
local function RestoreElvUIPortraits()
    if not C_AddOns.IsAddOnLoaded("ElvUI") then return end
    
    local E = _G.ElvUI and _G.ElvUI[1]
    if not E or not E.db or not E.db.unitframe or not E.db.unitframe.units then return end

    local state = GetPortraitState(false)
    if type(state) ~= "table" or not next(state) then return end

    local hasChanges = false

    -- 恢复状态
    for unitName, originalConfig in pairs(state) do
        local unitConfig = E.db.unitframe.units[unitName]
        if unitConfig and type(unitConfig) == "table" and unitConfig.portrait then
            unitConfig.portrait.enable = originalConfig.enable
            unitConfig.portrait.style = originalConfig.style
            hasChanges = true
        end
    end

    -- 清空记录
    wipe(state)

    if hasChanges then
        YUI:Print(LC["raid_opt.text.007"])
        E:UpdateUnitFrames()
    end
end

YUI.Event:On("YUI_WORLD_READY", function()
        -- 获取总开关状态，如果尚未初始化则使用默认值
        local isEnabled = Components and Components.IsEnabled and Components:IsEnabled("RaidOptimization")

        local db = GetDB()

        if isEnabled and db.DisableElvUIPortrait then
            if IsInRaidInstance() then
                -- 如果在团本内，且之前没有记录（说明是新进团本），则执行关闭
                local state = GetPortraitState(false)
                if type(state) ~= "table" or not next(state) then
                    DisableElvUIPortraits()
                end
            else
                -- 如果不在团本内，但有记录，说明离开了团本（或在团本外上线），则恢复
                local state = GetPortraitState(false)
                if type(state) == "table" and next(state) then
                    RestoreElvUIPortraits()
                end
            end
        else
            -- 如果功能被关闭，但存在以前遗留的记录（比如之前开启并在团本中，后来关了功能），离开团本时也应当恢复
            local state = GetPortraitState(false)
            if type(state) == "table" and next(state) then
                if not IsInRaidInstance() then
                     RestoreElvUIPortraits()
                end
            end
        end
end)

YUI.Components:RegisterFeature("RaidOptimization", Feature)

-------------------------------------------------------------------------------
-- YUI | SenseiClassResourceBar
-------------------------------------------------------------------------------
local _, YUI = ...

YUI.SCRB = {}
local S = YUI.SCRB

local LibStub = LibStub
local SCRB = _G.SCRB

function S:fullUpdateBars()
    if not SCRB then return end

    local LEM = LibStub and LibStub("LibEQOLEditMode-1.0", true)
    if not LEM then return end

    if LEM.eventHandlersExit then
        for _, callback in pairs(LEM.eventHandlersExit) do
            pcall(callback)
        end
    end
end

function S:ImportProfile(importString)
    if not SCRB then
        return false, "SenseiClassResourceBar 插件未加载"
    end

    local data, err = SCRB.importProfileFromString(importString)

    if data then
        if SCRB.fullUpdateBars then SCRB.fullUpdateBars() end
        return true
    else
        return false, err or "导入配置失败"
    end
end

function S:ImportDefaultProfile() 
    local profileString = YUI.Data and YUI.Data:GetData("SCRB")
    if not profileString then return false, "未找到 SCRB 默认配置" end
    return self:ImportProfile(profileString) 
end


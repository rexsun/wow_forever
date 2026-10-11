-------------------------------------------------------------------------------
-- YUI | 数据模块核心
-------------------------------------------------------------------------------
local _, YUI = ...
YUI.Data = {}

local Data = YUI.Data

-- 获取数据内容
-- 用法: YUI.Data:GetData("EditMode")
-- 用法: YUI.Data:GetData("CooldownMgr", "MAGE", "奥术")
function Data:GetData(key, ...)
    local node = YUI.IsForever and self.Forever or self.Mainline
    if YUI.IsForever and not self.Forever then return nil end
    if not node then return nil end
    
    -- 遍历路径
    local path = {key, ...}
    for _, k in ipairs(path) do
        if node and type(node) == "table" then
            node = node[k]
        else
            return nil
        end
    end
    
    if node and type(node) == "table" then
        if node.Data then
            return node.Data
        else
            -- 如果节点本身是表且没有Data字段，直接返回该表
            -- 适用于 GetData("CooldownMgr", "MAGE") 返回该职业下所有专精的表
            return node
        end
    end
    
    return nil
end

-- 获取数据版本号
function Data:GetVersion(key, ...)
    local node = YUI.IsForever and self.Forever or self.Mainline
    if YUI.IsForever and not self.Forever then return 0 end
    if not node then return 0 end
    
    local path = {key, ...}
    for _, k in ipairs(path) do
        if node and type(node) == "table" then
            node = node[k]
        else
            return 0
        end
    end
    
    if node and type(node) == "table" and node.Version then
        return node.Version
    end
    
    return 0
end

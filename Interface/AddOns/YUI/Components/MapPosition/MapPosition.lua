local ADDON_NAME, YUI = ...

-- 确保 Components 存在
if not YUI.Components then return end
local Components = YUI.Components
local SecurityAPI = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}

local function InCombatLockdownSafe()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown() == true
    end
    if InCombatLockdown then
        return InCombatLockdown() == true
    end
    return false
end

local function SaveMapPosition()
    
    -- 如果是最大化状态，不保存位置
    if WorldMapFrame:IsMaximized() then return end
    
    local point, relativeTo, relativePoint, x, y = WorldMapFrame:GetPoint()
    
    -- 确保相对于 UIParent 保存，简化恢复逻辑
    Components:SetStoreValue("MapPos", {point, "UIParent", relativePoint, x, y})
end

local function RestoreMapPosition()
    local pos = Components:GetStoreValue("MapPos")
    if not pos then return end
    
    -- 如果是最大化状态，不恢复位置
    if WorldMapFrame:IsMaximized() then return end
    
    if not pos or #pos < 5 then return end
    
    local point, relativeTo, relativePoint, x, y = unpack(pos)
    
    -- 边缘检测：防止地图在屏幕外无法找回
    -- 获取屏幕尺寸
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()
    local mapWidth = WorldMapFrame:GetWidth()
    local mapHeight = WorldMapFrame:GetHeight()
    local scale = WorldMapFrame:GetScale()
    
    -- 简单计算中心点大致位置 (忽略复杂的锚点转换，主要防止完全偏离)
    -- 如果 x, y 绝对值过大导致地图大部分在屏幕外，则重置
    -- 这里使用一个简单的启发式规则：如果偏移量超过屏幕的一半以上，可能就有问题了
    -- 更严谨的做法是计算四个角的坐标，但对于恢复位置来说，只要保证可见即可
    
    -- 检查是否在屏幕可视范围内
    -- 如果 x 或 y 导致地图中心点偏离屏幕中心太远
    local isOffScreen = false
    
    -- 简单的边界检查逻辑：
    -- 假设锚点是 CENTER/TOPLEFT 等，x,y 是偏移量
    -- 如果 x 的绝对值 > 屏幕宽度/2 + 地图宽度/2，说明地图可能在屏幕外
    if math.abs(x) > (screenWidth / 2 + mapWidth / 2) then
        isOffScreen = true
    end
    
    if math.abs(y) > (screenHeight / 2 + mapHeight / 2) then
        isOffScreen = true
    end
    
    if isOffScreen then
        YUI:Debug("Components | MapPosition | 地图位置异常，重置到屏幕中间")
        WorldMapFrame:ClearAllPoints()
        WorldMapFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    else
        WorldMapFrame:ClearAllPoints()
        WorldMapFrame:SetPoint(point, UIParent, relativePoint, x, y)
    end
end

local isHooked = false
local pendingRestore = false
local restoreEventFrame

local function FlushPendingRestore()
    if not pendingRestore then return end
    if InCombatLockdownSafe() then return end

    pendingRestore = false
    if restoreEventFrame then
        restoreEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    if Components:IsEnabled("MapPosition") then
        RestoreMapPosition()
    end
end

local function QueueRestoreMapPosition()
    pendingRestore = true
    if not CreateFrame then return end

    if not restoreEventFrame then
        restoreEventFrame = CreateFrame("Frame")
        restoreEventFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                FlushPendingRestore()
            end
        end)
    end

    restoreEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- 包装一下 Save/Restore 以支持开关检查
local function SaveMapPositionWrapper()
    if not Components:IsEnabled("MapPosition") then return end
    SaveMapPosition()
end

local function RestoreMapPositionWrapper()
    if not Components:IsEnabled("MapPosition") then return end
    if InCombatLockdownSafe() then
        QueueRestoreMapPosition()
        return
    end
    RestoreMapPosition()
end

-- 开启/关闭功能的回调函数
-- 注意：HookScript 是一次性的，无法取消。
-- 因此我们只在第一次开启时 Hook，之后通过 Wrapper 内部检查开关状态来控制逻辑。
local function InitMapPosition(enable)
    if isHooked then return end
    
    -- 使用 Wrapper 确保只有开启时才执行逻辑
    WorldMapFrame:HookScript("OnShow", RestoreMapPositionWrapper)
    WorldMapFrame:HookScript("OnHide", SaveMapPositionWrapper)
    
    isHooked = true
end

-- 注册到 Components
YUI.Components:RegisterFeature("MapPosition", {
    name = "地图位置记忆",
    description = "记住非最大化大地图的位置，异常跑出屏幕时自动拉回中间。",
    default = true,
    callback = InitMapPosition
})

local ADDON_NAME, YUI = ...
local LC = YUI.Locale:Get("Core")
local Components = YUI.Components
local GUI2 = YUI.GUI2
local SecurityAPI = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}
local cpuWatchdog = YUI.CPUWatchdog

local function InCombatLockdownSafe()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown() == true
    end
    if InCombatLockdown then
        return InCombatLockdown() == true
    end
    return false
end

-- 如果 EnhanceQoL 未加载，则不注册此功能
if not _G.EnhanceQoL then return end

local isFeatureEnabled = false
local legacyShiftFocusDisabled = true
local mapEnhancementsMovedToYMap = YUI.IsRetail == true

local defaults = {
    uiScale = 0.7,
    enableScale = false,
    hideXPBar = false,
    hideRepBar = false,
    ufHealthTextSize = 0,
    centerMinimapZoneText = false,
    worldMapScale = 1.2,
    enableQueueStatus = false,
    queueStatusSize = 32,
    queueStatusAnchor = "BOTTOMLEFT",
    queueStatusOffsetX = -5,
    queueStatusOffsetY = -5,
    hideMinimapZoom = false,
    hideBlizzardRaidManager = false,
    enableShiftFocus = false,
    autoAdaptBelowMinimapWidget = false,
    adaptUFHeight = false,
}

-- 获取独立配置表
local function SafeCall(func, ...)
    if type(func) ~= "function" then return false end
    local ok, result = pcall(func, ...)
    if not ok and YUI.Debug then
        YUI:Debug("Components | EQoL适配 | 第三方调用失败: " .. tostring(result))
    end
    return ok, result
end

local function SafeHook(object, method, callback)
    if type(hooksecurefunc) ~= "function" then return false end
    if not object or type(method) ~= "string" or type(object[method]) ~= "function" then return false end

    local ok, err = pcall(hooksecurefunc, object, method, function(...)
        SafeCall(callback, ...)
    end)
    if not ok and YUI.Debug then
        YUI:Debug("Components | EQoL适配 | Hook 失败: " .. tostring(method) .. " - " .. tostring(err))
    end
    return ok
end

local function GetDB()
    local db = (Components and Components.EnsureConfig and Components:EnsureConfig("EQoLAdapter_Config", defaults)) or defaults
    return db
end

-- 扩展 EnhanceQoL 原生 Edit Mode 能量条高度 slider 下限，不修改外部插件源码。
local function GetEQoLPowerHeightLabel()
    local libStub = _G.LibStub
    if libStub then
        local aceLocale = libStub("AceLocale-3.0", true)
        local locale = aceLocale and aceLocale:GetLocale("EnhanceQoL", true)
        if locale and locale["Power height"] then
            return locale["Power height"]
        end
    end
    return "Power height"
end

local function IsEQoLPowerHeightSetting(setting, powerHeightLabel)
    if type(setting) ~= "table" then return false end
    if setting.minValue ~= 6 then return false end
    local name = setting.name
    return name == powerHeightLabel or name == "Power height"
end

local function PatchEQoLPowerHeightSettings()
    local editMode = _G.EnhanceQoL and _G.EnhanceQoL.EditMode
    local internal = editMode and editMode.lib and editMode.lib.internal
    if not internal or not internal.GetFrameSettings then
        return false
    end

    local changed = false
    local powerHeightLabel = GetEQoLPowerHeightLabel()
    local frames = editMode.frames
    if type(frames) == "table" then
        for _, entry in pairs(frames) do
            local frame = type(entry) == "table" and entry.frame or nil
            local settings
            if frame then
                local ok, value = SafeCall(internal.GetFrameSettings, internal, frame)
                if ok then
                    settings = value
                end
            end
            if type(settings) == "table" then
                for index = 1, #settings do
                    local setting = settings[index]
                    if IsEQoLPowerHeightSetting(setting, powerHeightLabel) then
                        setting.minValue = 1
                        changed = true
                    end
                end
            end
        end
    end

    if changed and internal.RequestRefreshSettings then
        SafeCall(internal.RequestRefreshSettings, internal)
    end
    return changed
end

local powerHeightPatchQueued = false
local function QueuePatchEQoLPowerHeightSettings()
    if powerHeightPatchQueued then return end
    powerHeightPatchQueued = true
    local function RunPatch()
        powerHeightPatchQueued = false
        PatchEQoLPowerHeightSettings()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, RunPatch)
    else
        RunPatch()
    end
end

local function SetupEQoLPowerHeightPatch()
    local editMode = _G.EnhanceQoL and _G.EnhanceQoL.EditMode
    if not editMode then return end

    if not editMode.__yuiPowerHeightSettingsHooked and type(editMode.RegisterSettings) == "function" then
        local hooked = false
        if hooksecurefunc then
            hooked = SafeHook(editMode, "RegisterSettings", QueuePatchEQoLPowerHeightSettings)
        end

        if not hooked then
            local originalRegisterSettings = editMode.RegisterSettings
            editMode.RegisterSettings = function(self, ...)
                SafeCall(originalRegisterSettings, self, ...)
                QueuePatchEQoLPowerHeightSettings()
            end
        end

        editMode.__yuiPowerHeightSettingsHooked = true
    end

    PatchEQoLPowerHeightSettings()
end

-- 检测 EnhanceQoL 自身是否开启了缩放
local function IsEQoLScalingEnabled()
    local eqol = _G.EnhanceQoL
    if eqol and eqol.db and eqol.db.uiScalePreset then
        -- 如果不是 "NoScaling"，说明 EnhanceQoL 自己的缩放功能在工作
        return eqol.db.uiScalePreset ~= "NoScaling"
    end
    return false
end

-- 隐藏原生暴雪团队管理框架
local function ApplyBlizzardRaidManagerVisibility()
    if not isFeatureEnabled then return end
    local db = GetDB()
    
    if db.hideBlizzardRaidManager then
        -- 1. 隐藏小队框架
        if _G.CompactPartyFrame then
            _G.CompactPartyFrame:UnregisterAllEvents()
        end
        
        -- 2. 写入系统设置，阻止团队管理面板显示
        if _G.CompactRaidFrameManager_SetSetting then
            _G.CompactRaidFrameManager_SetSetting("IsShown", "0")
        end
        
        -- 3. 将管理面板挂载到隐藏框架，实现安全隔离
        if _G.CompactRaidFrameManager then
            _G.CompactRaidFrameManager:UnregisterAllEvents()
            local hiddenFrame = YUI.HiddenFrame
            if not hiddenFrame then
                hiddenFrame = CreateFrame("Frame")
                hiddenFrame:Hide()
            end
            _G.CompactRaidFrameManager:SetParent(hiddenFrame)
        end
    end
end

local function GetFocusMacroText()
    return "/clearfocus [@mouseover,noexists]\n/focus [@mouseover,exists]"
end

local function SetupFrameFocus(frame)
    if not frame or frame._yui_shift_focus_setup or InCombatLockdown() then return end
    -- 排除一些特殊框体（如姓名板资源点等）
    local name = frame.GetName and frame:GetName()
    if name and string.match(name, "oUF_NPs") then return end
    
    pcall(function()
        frame:SetAttribute("shift-type1", "macro")
        frame:SetAttribute("shift-macrotext1", GetFocusMacroText())
    end)
    frame._yui_shift_focus_setup = true
end

-- 应用 Shift+左键 设为/取消焦点功能
local function ApplyShiftFocus()
    if legacyShiftFocusDisabled then return end
    if not isFeatureEnabled then return end
    local db = GetDB()
    
    if not db.enableShiftFocus or InCombatLockdown() then return end
    
    -- 1. 创建全局点击按钮以支持点击空白处清除焦点或3D模型设置焦点
    if not YUIShiftFocuserButton then
        local btn = CreateFrame("CheckButton", "YUIShiftFocuserButton", UIParent, "SecureActionButtonTemplate")
        GUI2.Secure:RegisterActionClicks(btn)
        btn:SetAttribute("type", "macro")
        YUIShiftFocuserButton = btn
    end
    YUIShiftFocuserButton:SetAttribute("macrotext1", GetFocusMacroText())
    SetOverrideBindingClick(YUIShiftFocuserButton, true, "SHIFT-BUTTON1", "YUIShiftFocuserButton")
    
    -- 2. 遍历并绑定常见单位框架
    local framesToBind = {
        "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame",
        "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4", "PartyMemberFrame5",
        "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame",
        "EQOLUFPlayerFrame", "EQOLUFTargetFrame", "EQOLUFToTFrame", "EQOLUFFocusFrame",
        "EQOLUFBoss1Frame", "EQOLUFBoss2Frame", "EQOLUFBoss3Frame", "EQOLUFBoss4Frame", "EQOLUFBoss5Frame"
    }
    
    for _, name in ipairs(framesToBind) do
        local f = _G[name]
        if f then SetupFrameFocus(f) end
    end
    
    -- 绑定姓名板
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in pairs(C_NamePlate.GetNamePlates()) do 
            SetupFrameFocus(plate) 
        end
    end
end

local focusEventOwner = {}
local focusRefreshScheduled = false
local focusRefreshTimer
local focusRefreshRosterTransaction = false

local function RunQueuedFocusRefresh()
    focusRefreshScheduled = false
    focusRefreshTimer = nil
    local rosterTransaction = focusRefreshRosterTransaction
    focusRefreshRosterTransaction = false
    local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
    ApplyShiftFocus()
    if startedAt then
        cpuWatchdog:EndProbeTiming(
            "component.eqol-adapter.shift-focus-batch",
            startedAt,
            "EQoLAdapter shift-focus batch",
            nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
        )
    end
end

local function QueueFocusRefresh(event)
    if event == "GROUP_ROSTER_UPDATE" then
        focusRefreshRosterTransaction = true
    end
    if focusRefreshScheduled then return end
    focusRefreshScheduled = true
    if C_Timer and C_Timer.NewTimer then
        focusRefreshTimer = C_Timer.NewTimer(0.1, RunQueuedFocusRefresh)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.1, RunQueuedFocusRefresh)
    else
        RunQueuedFocusRefresh()
    end
end

local function OnFocusEvent(event, unit)
    local db = GetDB()
    if not isFeatureEnabled or not db.enableShiftFocus then return end
    
    if event == "NAME_PLATE_UNIT_ADDED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then SetupFrameFocus(plate) end
    else
        if not InCombatLockdown() then
            QueueFocusRefresh(event)
        end
    end
end

YUI.Event:On("YUI_WORLD_READY", OnFocusEvent, focusEventOwner)
YUI.Event:On("PLAYER_REGEN_ENABLED", OnFocusEvent, focusEventOwner)
YUI.Event:On("NAME_PLATE_UNIT_ADDED", OnFocusEvent, focusEventOwner)
YUI.Event:On("GROUP_ROSTER_UPDATE", OnFocusEvent, focusEventOwner, {
    moduleId = "component:EQoLAdapter",
    traceName = "EQoLAdapter:ShiftFocus:GROUP_ROSTER_UPDATE",
    throttle = 0.1,
})

-- 应用缩放逻辑
local function ApplyUIScale()
    if not isFeatureEnabled then return end
    
    local db = GetDB()
    if not db.enableScale then return end

    -- 优先级判断：如果 EQoL 自己的缩放开启了，我们的缩放就不生效
    if IsEQoLScalingEnabled() then
        YUI:Debug("Components | EQoL适配 | 检测到 EnhanceQoL 原生缩放已开启，YUI 缩放功能失效")
        return
    end

    local scale = db.uiScale
    if not scale then return end

    YUI:Debug("Components | EQoL适配 | 应用自定义 UI 缩放: " .. tostring(scale))

    local eqol = _G.EnhanceQoL
    if eqol and eqol.functions and eqol.functions.setCVarValue then
        SafeCall(eqol.functions.setCVarValue, "useUiScale", "1")
        SafeCall(eqol.functions.setCVarValue, "uiscale", tostring(scale))
    elseif C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("useUiScale", "1")
        C_CVar.SetCVar("uiscale", tostring(scale))
    end

    if UIParent and UIParent.SetScale then UIParent:SetScale(scale) end

    if eqol and eqol.Tooltip and eqol.Tooltip.ApplyScale then
        C_Timer.After(0.25, function()
            if eqol.Tooltip and eqol.Tooltip.ApplyScale then
                SafeCall(eqol.Tooltip.ApplyScale)
            end
        end)
    end
end

-- 处理经验条和声望条的隐藏逻辑
local function ApplyBarVisibility()
    if not isFeatureEnabled then return end
    local db = GetDB()
    
    if StatusTrackingBarManager then
        -- 针对正式服 10.0+ 的状态条管理器
        if db.hideXPBar then
            StatusTrackingBarManager:Hide()
            -- 尝试更激进的隐藏方式防止它在战斗中重新出现
            if not StatusTrackingBarManager._yui_hooked_hide then
                hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", function(self)
                    if GetDB().hideXPBar then
                        self:Hide()
                    end
                end)
                StatusTrackingBarManager._yui_hooked_hide = true
            end
        else
            StatusTrackingBarManager:UpdateBarsShown()
        end
    else
        -- 兼容旧版/怀旧服
        if MainMenuExpBar then
            if db.hideXPBar then
                MainMenuExpBar:Hide()
                if not MainMenuExpBar._yui_hooked_hide then
                    MainMenuExpBar:HookScript("OnShow", function(self)
                        if GetDB().hideXPBar then self:Hide() end
                    end)
                    MainMenuExpBar._yui_hooked_hide = true
                end
            else
                MainMenuExpBar:Show()
            end
        end
        if ReputationWatchBar then
            if db.hideRepBar then
                ReputationWatchBar:Hide()
                if not ReputationWatchBar._yui_hooked_hide then
                    ReputationWatchBar:HookScript("OnShow", function(self)
                        if GetDB().hideRepBar then self:Hide() end
                    end)
                    ReputationWatchBar._yui_hooked_hide = true
                end
            else
                ReputationWatchBar:Show()
            end
        end
    end
end

-- 隐藏原生小地图缩放按钮
local function ApplyMinimapZoomVisibility()
    if mapEnhancementsMovedToYMap or not isFeatureEnabled then return end
    local db = GetDB()
    
    local zoomIn = _G.MinimapZoomIn or (Minimap and Minimap.ZoomIn)
    local zoomOut = _G.MinimapZoomOut or (Minimap and Minimap.ZoomOut)
    
    if db.hideMinimapZoom then
        if zoomIn then zoomIn:Hide() end
        if zoomOut then zoomOut:Hide() end
        
        -- Hook 以防止被系统或其他插件重新显示
        if not YUI._eqol_minimap_zoom_hooked then
            if zoomIn then
                hooksecurefunc(zoomIn, "Show", function(self)
                    if GetDB().hideMinimapZoom then self:Hide() end
                end)
            end
            if zoomOut then
                hooksecurefunc(zoomOut, "Show", function(self)
                    if GetDB().hideMinimapZoom then self:Hide() end
                end)
            end
            YUI._eqol_minimap_zoom_hooked = true
        end
    else
        -- 只有在曾经隐藏过，且现在关闭了该选项时才重新显示
        if zoomIn and zoomIn:IsObjectType("Button") then zoomIn:Show() end
        if zoomOut and zoomOut:IsObjectType("Button") then zoomOut:Show() end
    end
end

-- 居中小地图区域名称文本
local function ApplyMinimapZoneTextAlignment()
    if mapEnhancementsMovedToYMap or not isFeatureEnabled then return end
    local db = GetDB()
    local isCenter = db.centerMinimapZoneText

    -- 获取区域文本对象 (正式服通常在 MinimapCluster 下)
    local zoneText = MinimapCluster and MinimapCluster.ZoneTextButton and MinimapCluster.ZoneTextButton.ZoneText
                     or _G.MinimapZoneText
    
    if not zoneText then return end

    if isCenter then
        -- 核心：清除原有固定点，重新锚定左右两端，使其填满父级宽度
        local parent = zoneText:GetParent()
        if parent then
            zoneText:ClearAllPoints()
            -- 小地图顶部的背景并非完全对称，左侧通常有留白给图标等
            -- 将 offset 设为 0，让文本框与父级完全等宽，实现真正的物理居中
            local offsetX = 15
            zoneText:SetPoint("LEFT", parent, "LEFT", offsetX, 0)
            zoneText:SetPoint("RIGHT", parent, "RIGHT", offsetX, 0)
            -- 当填满父级后，使用 CENTER 即可在整个背景条内居中
            zoneText:SetJustifyH("CENTER")
            
            -- 防止原生代码重置排版
            if not YUI._eqol_minimap_zone_hooked then
                hooksecurefunc(zoneText, "SetJustifyH", function(self, justify)
                    if GetDB().centerMinimapZoneText and justify ~= "CENTER" then
                        self:SetJustifyH("CENTER")
                    end
                end)
                YUI._eqol_minimap_zone_hooked = true
            end
        end
    else
        -- 关闭功能时，恢复为 EnhanceQoL 或原生的靠左排版 (通常是 LEFT 或左偏移锚点)
        zoneText:SetJustifyH("LEFT")
        -- 完整的锚点还原需要 /reload，因为原生的 offset 难以精准保存，但关闭开关后至少不再强行居中
    end
end

-- 处理队列状态小地图图标
local isUpdatingQueueStatus = false
local function ApplyQueueStatusIcon()
    if mapEnhancementsMovedToYMap or not isFeatureEnabled then return end
    local db = GetDB()
    local btn = _G.QueueStatusButton or _G.MiniMapLFGFrame or _G.LFGMinimapFrame
    if not btn then return end

    if db.enableQueueStatus then
        local function UpdatePosition()
            if isUpdatingQueueStatus then return end
            isUpdatingQueueStatus = true
            
            btn:SetParent(Minimap)
            btn:SetFrameLevel(999)
            btn:SetIgnoreParentScale(true)
            -- 使用缩放来调整大小，避免破坏原生内部图标组件
            btn:SetScale(db.queueStatusSize / 32)
            btn:ClearAllPoints()
            btn:SetPoint(db.queueStatusAnchor, Minimap, db.queueStatusAnchor, db.queueStatusOffsetX, db.queueStatusOffsetY)
            
            isUpdatingQueueStatus = false
        end

        UpdatePosition()

        if not YUI._eqol_queue_status_hooked then
            hooksecurefunc(btn, "SetPoint", function()
                if not isUpdatingQueueStatus then
                    UpdatePosition()
                end
            end)
            hooksecurefunc(btn, "SetParent", function()
                if not isUpdatingQueueStatus then
                    UpdatePosition()
                end
            end)
            hooksecurefunc(btn, "SetScale", function()
                if not isUpdatingQueueStatus then
                    UpdatePosition()
                end
            end)
            YUI._eqol_queue_status_hooked = true
        end
    else
        -- 如果用户关闭了该功能，我们不再主动去移动它，让系统或其它插件接管即可
        -- 完整的还原需要 reload，这里仅停止干预
    end
end

-- 应用世界地图缩放逻辑
local isUpdatingWorldMapScale = false
local worldMapScalePending = false
local worldMapScaleEventFrame
local ApplyWorldMapScale

local function QueueWorldMapScaleUpdate()
    if worldMapScalePending then return end
    worldMapScalePending = true
    if not CreateFrame then return end

    if not worldMapScaleEventFrame then
        worldMapScaleEventFrame = CreateFrame("Frame")
        worldMapScaleEventFrame:SetScript("OnEvent", function(_, event)
            if event ~= "PLAYER_REGEN_ENABLED" then return end
            if InCombatLockdownSafe() then return end

            worldMapScalePending = false
            worldMapScaleEventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            ApplyWorldMapScale()
        end)
    end

    worldMapScaleEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

ApplyWorldMapScale = function()
    if mapEnhancementsMovedToYMap or not isFeatureEnabled then return end
    if not WorldMapFrame then return end

    local function GetTargetScale()
        local currentDB = GetDB()
        if not currentDB.worldMapScale then return nil end
        if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then
            return 1
        end
        return currentDB.worldMapScale
    end

    local function UpdateScale()
        if isUpdatingWorldMapScale then return end
        if InCombatLockdownSafe() then
            QueueWorldMapScaleUpdate()
            return
        end

        local targetScale = GetTargetScale()
        if not targetScale then return end
        if WorldMapFrame.GetScale and WorldMapFrame:GetScale() == targetScale then return end

        isUpdatingWorldMapScale = true
        WorldMapFrame:SetScale(targetScale)
        isUpdatingWorldMapScale = false
    end

    local function DelayedUpdateScale()
        if isUpdatingWorldMapScale then return end
        if InCombatLockdownSafe() then
            QueueWorldMapScaleUpdate()
            return
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, UpdateScale)
        else
            UpdateScale()
        end
    end

    UpdateScale()

    if not YUI._eqol_worldmap_scale_hooked then
        if WorldMapFrame.SynchronizeDisplayState then
            hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", DelayedUpdateScale)
        end
        if WorldMapFrame.Minimize then
            hooksecurefunc(WorldMapFrame, "Minimize", DelayedUpdateScale)
        end
        WorldMapFrame:HookScript("OnShow", DelayedUpdateScale)

        -- 拦截任何其他试图重置缩放的行为
        hooksecurefunc(WorldMapFrame, "SetScale", function(_, scale)
            if isUpdatingWorldMapScale then return end
            local targetScale = GetTargetScale()
            if targetScale and scale ~= targetScale then
                DelayedUpdateScale()
            end
        end)

        YUI._eqol_worldmap_scale_hooked = true
    end
end

-- 自动适配地图下方小工具
local isUpdatingBelowMinimapWidget = false
local function ApplyBelowMinimapWidgetFix()
    if mapEnhancementsMovedToYMap or not isFeatureEnabled then return end
    local db = GetDB()
    
    local widget = _G.UIWidgetBelowMinimapContainerFrame
    if not widget then return end
    
    if db.autoAdaptBelowMinimapWidget then
        local function UpdateWidget()
            if isUpdatingBelowMinimapWidget then return end
            isUpdatingBelowMinimapWidget = true
            
            widget:SetScale(0.6)
            widget:ClearAllPoints()
            -- 居中对齐到小地图下方，适当下移10像素避免重叠
            widget:SetPoint("TOP", Minimap, "BOTTOM", 0, 0)
            
            isUpdatingBelowMinimapWidget = false
        end
        
        UpdateWidget()
        
        -- 防止原生 UI 刷新覆盖我们的设定
        if not YUI._eqol_below_minimap_hooked then
            hooksecurefunc(widget, "SetPoint", function()
                if not isUpdatingBelowMinimapWidget and GetDB().autoAdaptBelowMinimapWidget then
                    UpdateWidget()
                end
            end)
            hooksecurefunc(widget, "SetScale", function()
                if not isUpdatingBelowMinimapWidget and GetDB().autoAdaptBelowMinimapWidget then
                    UpdateWidget()
                end
            end)
            YUI._eqol_below_minimap_hooked = true
        end
    else
        -- 恢复默认的缩放为1，位置只能交由系统自动恢复，这里不做强行恢复
        if not isUpdatingBelowMinimapWidget then
            isUpdatingBelowMinimapWidget = true
            widget:SetScale(1)
            isUpdatingBelowMinimapWidget = false
        end
    end
end

-- 玩家和目标框架生命值居中文本尺寸覆盖
local function ApplyUFHealthTextSize()
    if not isFeatureEnabled then return end
    local db = GetDB()
    local size = db.ufHealthTextSize

    local eqol = _G.EnhanceQoL
    if not eqol or not eqol.variables or not eqol.variables.states then return end

    local function OverrideSizeForUnit(unit)
        local st = eqol.variables.states[unit]
        -- 在 EnhanceQoL 的源码中，生命值的三段文本分别是 healthTextLeft, healthTextCenter, healthTextRight
        if st and st.healthTextCenter then
            local textObj = st.healthTextCenter
            if textObj and textObj.SetFont then
                local font, _, outline = textObj:GetFont()
                if size > 0 then
                    textObj:SetFont(font, size, outline)
                end
                
                -- 防止 EnhanceQoL 的刷新覆盖我们的设置
                if not textObj._yui_hooked_fontsize then
                    hooksecurefunc(textObj, "SetFont", function(self, f, s, flags)
                        local currentSize = GetDB().ufHealthTextSize
                        -- 如果启用了覆盖，并且当前正在设置的大小不是我们的目标大小，则强制改回去
                        -- 为了防止无限递归，只有在 s ~= currentSize 时才重新设置
                        if currentSize > 0 and s ~= currentSize then
                            self:SetFont(f, currentSize, flags)
                        end
                    end)
                    textObj._yui_hooked_fontsize = true
                end
            end
        end
    end

    OverrideSizeForUnit("player")
    OverrideSizeForUnit("target")
end

local ufHeightAdapted = false
local function ApplyUFHeightAdaption()
    if not isFeatureEnabled then return end
    local db = GetDB()
    if not db.adaptUFHeight or ufHeightAdapted then return end

    local eqol = _G.EnhanceQoL
    if not eqol or not eqol.Aura or not eqol.Aura.UF then return end
    
    local UF = eqol.Aura.UF
    
    local function FixFrameHeight(unit)
        local prefix = unit == "player" and "EQOLUFPlayer" or "EQOLUFTarget"
        local frame = _G[prefix .. "Frame"]
        local status = _G[prefix .. "Status"]
        local health = _G[prefix .. "Health"]
        
        if frame and status and health then
            local barGroup = health:GetParent()
            
            -- 将生命条容器顶靠至主框架顶部
            if barGroup then
                local bp1, bRelTo1, bRelPoint1, bx1, by1 = barGroup:GetPoint(1)
                local bp2, bRelTo2, bRelPoint2, bx2, by2 = barGroup:GetPoint(2)
                
                barGroup:ClearAllPoints()
                barGroup:SetPoint(bp1 or "TOPLEFT", bRelTo1 or frame, bRelPoint1 or "TOPLEFT", bx1 or 0, 0)
                if bp2 then
                    barGroup:SetPoint(bp2 or "TOPRIGHT", bRelTo2 or frame, bRelPoint2 or "TOPRIGHT", bx2 or 0, 0)
                end
            end
            
            -- 名字文本区域移出主框架外
            if status then
                local p1, relTo1, relPoint1, x1, y1 = status:GetPoint(1)
                local p2, relTo2, relPoint2, x2, y2 = status:GetPoint(2)
                
                status:ClearAllPoints()
                status:SetPoint("BOTTOMLEFT", relTo1 or frame, "TOPLEFT", x1 or 0, 0)
                if p2 then
                    status:SetPoint("BOTTOMRIGHT", relTo2 or frame, "TOPRIGHT", x2 or 0, 0)
                end
            end
            
            -- 主框架高度裁剪至刚好等于生命条+能量条的高度
            if barGroup then
                local barsHeight = barGroup:GetHeight()
                if barsHeight and barsHeight > 0 then
                    frame:SetHeight(barsHeight)
                end
            end
        end
    end

    hooksecurefunc(UF, "RefreshUnit", function(unit)
        if unit == "player" or unit == "target" then
            FixFrameHeight(unit)
        end
    end)
    
    hooksecurefunc(UF, "Refresh", function()
        FixFrameHeight("player")
        FixFrameHeight("target")
    end)
    
    ufHeightAdapted = true
    
    -- 只有当框架已经生成时，尝试触发一次初始渲染
    if UF.RefreshUnit then
        pcall(function()
            UF.RefreshUnit("player")
            UF.RefreshUnit("target")
        end)
    end
end

local function ApplySkinUnitFrames()
    if not isFeatureEnabled then return end
    -- EhanceQoL
    -- 优化单位框架
    -- if EQOLUFPlayerPower then
    --     YUI:CreateBorder(EQOLUFPlayerPower, 0, 0, 0, 0.6)
    -- end

    -- if EQOLUFTargetPower then
    --     YUI:CreateBorder(EQOLUFTargetPower, 0, 0, 0, 0.6)
    -- end

    -- if EQOLUFToTPower then
    --     YUI:CreateBorder(EQOLUFToTPower, 0, 0, 0, 0.6)
    -- end

    -- if EQOLUFFocusPower then
    --     YUI:CreateBorder(EQOLUFFocusPower, 0, 0, 0, 0.6)
    -- end

    -- if EQOLUFPetPower then
    --     YUI:CreateBorder(EQOLUFPetPower, 0, 0, 0, 0.6)
    -- end

    -- if EQOLUFPlayerHealth then
    --     YUI:CreateSoftShadow(EQOLUFPlayerHealth)
    -- end

    -- if EQOLUFTargetHealth then
    --     YUI:CreateSoftShadow(EQOLUFTargetHealth)
    -- end
end

-- 构建设置面板
local function GetOptions(feature)
    local db = GetDB()
    local isEQoLScaleOn = IsEQoLScalingEnabled()
    
    local function Refresh()
        if feature and feature.RefreshCurrentModule then
            feature:RefreshCurrentModule()
        end
    end

    return {
        {
            type = "custom",
            render = function(parent, x, y, availableWidth)
                local pageWidth = math.min(availableWidth or 660, 660)
                local rowHeight = 32
                local rowGap = 10
                local sectionGap = 14
                local fieldGap = 18
                local sliderLabelWidth = 118
                local compactLabelWidth = 72
                local sliderValueWidth = 56
                local cursorY = 0

                local root = GUI2:CreateFrame(parent, { width = pageWidth, height = 1 })
                root:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

                local function Advance(amount)
                    cursorY = cursorY - amount
                end

                local function CellWidth(columns, span)
                    span = span or 1
                    local baseWidth = math.floor((pageWidth - fieldGap * (columns - 1)) / columns)
                    return baseWidth * span + fieldGap * (span - 1)
                end

                local function ColX(columns, index)
                    return (index - 1) * (CellWidth(columns, 1) + fieldGap)
                end

                local function AddRow(height, gap)
                    local row = GUI2:CreateFrame(root, { width = pageWidth, height = height or rowHeight })
                    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, cursorY)
                    Advance((height or rowHeight) + (gap or rowGap))
                    return row
                end

                local function AddTextRow(text, colorKey)
                    local row = AddRow(24)
                    local label = GUI2:CreateText(row, text, "font.size.md", colorKey or "color.text.primary")
                    label:SetPoint("LEFT", row, "LEFT", 0, 0)
                    label:SetWidth(pageWidth)
                    label:SetJustifyH("LEFT")
                    label:SetWordWrap(false)
                    return label
                end

                local function AddLabel(row, text, xOffset, width)
                    local label = GUI2:CreateText(row, text, "font.size.md", "color.text.primary")
                    label:SetPoint("LEFT", row, "LEFT", xOffset, 0)
                    label:SetWidth(width)
                    label:SetJustifyH("LEFT")
                    label:SetWordWrap(false)
                    return label
                end

                local function AddCheckbox(row, columns, colIndex, label, opts, span)
                    local xOffset = ColX(columns, colIndex)
                    local width = CellWidth(columns, span or 1)
                    local checkbox = GUI2.Form:CreateCheckbox(row, {
                        label = label,
                        width = width,
                        get = opts.get,
                        set = opts.set,
                    })
                    checkbox:SetPoint("LEFT", row, "LEFT", xOffset, 0)
                    if checkbox.text then
                        checkbox.text:SetWidth(math.max(width - 26, 1))
                        checkbox.text:SetWordWrap(false)
                    end
                    return checkbox
                end

                local function AddSlider(row, columns, colIndex, label, opts, span, labelWidth)
                    local xOffset = ColX(columns, colIndex)
                    local width = CellWidth(columns, span or 1)
                    local slider = GUI2.Form:CreateSlider(row, {
                        label = label,
                        inline = true,
                        width = width,
                        labelWidth = labelWidth or sliderLabelWidth,
                        inputWidth = sliderValueWidth,
                        min = opts.min,
                        max = opts.max,
                        step = opts.step,
                        precision = opts.precision,
                        instantUpdate = opts.instantUpdate,
                        get = opts.get,
                        set = opts.set,
                    })
                    slider:SetPoint("LEFT", row, "LEFT", xOffset, 0)
                    return slider
                end

                local function AddStackedSlider(row, columns, colIndex, label, opts, span)
                    local xOffset = ColX(columns, colIndex)
                    local width = CellWidth(columns, span or 1)
                    local labelText = GUI2:CreateText(row, label, "font.size.md", "color.text.primary")
                    labelText:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset, 0)
                    labelText:SetWidth(width)
                    labelText:SetJustifyH("LEFT")
                    labelText:SetWordWrap(false)

                    local slider = GUI2.Form:CreateSlider(row, {
                        inline = true,
                        width = width,
                        inputWidth = sliderValueWidth,
                        min = opts.min,
                        max = opts.max,
                        step = opts.step,
                        precision = opts.precision,
                        get = opts.get,
                        set = opts.set,
                    })
                    slider:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset, -22)
                    return slider
                end

                local function AddDropdown(row, columns, colIndex, label, opts, span, labelWidth)
                    labelWidth = labelWidth or compactLabelWidth
                    local xOffset = ColX(columns, colIndex)
                    local width = CellWidth(columns, span or 1)
                    AddLabel(row, label, xOffset, labelWidth)
                    local dropdown = GUI2.Form:CreateDropdown(row, {
                        width = math.max(width - labelWidth, 80),
                        options = opts.options,
                        get = opts.get,
                        set = opts.set,
                    })
                    dropdown:SetPoint("LEFT", row, "LEFT", xOffset + labelWidth, 0)
                    return dropdown
                end

                local scaleRow = AddRow()
                AddCheckbox(scaleRow, 2, 1, LC["eqol_adapter.text.001"], {
                    get = function() return db.enableScale end,
                    set = function(v)
                        db.enableScale = v
                        if v then ApplyUIScale() end
                        Refresh()
                    end,
                })

                if db.enableScale and not isEQoLScaleOn then
                    AddSlider(scaleRow, 2, 2, LC["eqol_adapter.text.002"], {
                        min = 0.3,
                        max = 1.0,
                        step = 0.01,
                        precision = 2,
                        instantUpdate = false,
                        get = function() return db.uiScale end,
                        set = function(v)
                            if IsMouseButtonDown and IsMouseButtonDown("LeftButton") then
                                return
                            end
                            db.uiScale = v
                            ApplyUIScale()
                        end,
                    })
                end

                if db.enableScale and isEQoLScaleOn then
                    AddTextRow(LC["eqol_adapter.text.003"], "color.state.danger")
                end

                local visibilityRow = AddRow()
                AddCheckbox(visibilityRow, 2, 1, LC["eqol_adapter.text.004"], {
                    get = function() return db.hideXPBar end,
                    set = function(v)
                        db.hideXPBar = v
                        -- 在正式服，由于 XP 和 Rep 共用一个 BarManager，这里简化为一个总开关
                        db.hideRepBar = v
                        ApplyBarVisibility()
                    end,
                })

                local raidManagerOptions = {
                    get = function() return db.hideBlizzardRaidManager end,
                    set = function(v)
                        db.hideBlizzardRaidManager = v
                        ApplyBlizzardRaidManagerVisibility()
                        YUI.Settings:ShowReload()
                        if YUI.Print then
                            YUI:Print(LC["eqol_adapter.text.005"])
                        end
                    end,
                }
                local healthTextOptions = {
                    min = 0,
                    max = 36,
                    step = 1,
                    get = function() return db.ufHealthTextSize end,
                    set = function(v)
                        db.ufHealthTextSize = v
                        YUI.Settings:ShowReload()
                        ApplyUFHealthTextSize()
                    end,
                }

                if mapEnhancementsMovedToYMap then
                    AddCheckbox(visibilityRow, 2, 2, LC["eqol_adapter.text.006"], raidManagerOptions)

                    local unitFrameRow = AddRow(50)
                    AddStackedSlider(unitFrameRow, 2, 1, LC["eqol_adapter.text.007"], healthTextOptions)
                else
                    AddCheckbox(visibilityRow, 2, 2, LC["eqol_adapter.text.008"], {
                        get = function() return db.hideMinimapZoom end,
                        set = function(v)
                            db.hideMinimapZoom = v
                            ApplyMinimapZoomVisibility()
                            Refresh()
                        end,
                    })

                    local mapRow2 = AddRow()
                    AddCheckbox(mapRow2, 2, 1, LC["eqol_adapter.text.009"], {
                        get = function() return db.centerMinimapZoneText end,
                        set = function(v)
                            db.centerMinimapZoneText = v
                            ApplyMinimapZoneTextAlignment()
                            Refresh()
                        end,
                    })
                    AddCheckbox(mapRow2, 2, 2, LC["eqol_adapter.text.006"], raidManagerOptions)

                    local behaviorRow = AddRow()
                    AddCheckbox(behaviorRow, 2, 1, LC["eqol_adapter.text.010"], {
                        get = function() return db.autoAdaptBelowMinimapWidget end,
                        set = function(v)
                            db.autoAdaptBelowMinimapWidget = v
                            ApplyBelowMinimapWidgetFix()
                            Refresh()
                        end,
                    })

                    local scaleControlRow = AddRow()
                    AddSlider(scaleControlRow, 2, 1, LC["eqol_adapter.text.011"], {
                        min = 0.5,
                        max = 2.0,
                        step = 0.05,
                        precision = 2,
                        get = function() return db.worldMapScale end,
                        set = function(v)
                            db.worldMapScale = v
                            ApplyWorldMapScale()
                        end,
                    })
                    AddSlider(scaleControlRow, 2, 2, LC["eqol_adapter.text.007"], healthTextOptions, 1, 190)

                    local divider = GUI2:CreateDivider(root, pageWidth, nil, LC["eqol_adapter.text.012"], true)
                    divider:SetPoint("TOPLEFT", root, "TOPLEFT", 0, cursorY - 4)
                    Advance((divider:GetHeight() or 18) + sectionGap)

                    local queueRow1 = AddRow()
                    AddCheckbox(queueRow1, 2, 1, LC["eqol_adapter.text.013"], {
                        get = function() return db.enableQueueStatus end,
                        set = function(v)
                            db.enableQueueStatus = v
                            if v then ApplyQueueStatusIcon() end
                            Refresh()
                        end,
                    })

                    if db.enableQueueStatus then
                        local queueRow2 = AddRow()
                        AddDropdown(queueRow2, 2, 1, LC["eqol_adapter.text.014"], {
                            options = {
                                { text = LC["eqol_adapter.text.015"], value = "TOPLEFT" },
                                { text = LC["eqol_adapter.text.016"], value = "TOPRIGHT" },
                                { text = LC["eqol_adapter.text.017"], value = "BOTTOMLEFT" },
                                { text = LC["eqol_adapter.text.018"], value = "BOTTOMRIGHT" },
                            },
                            get = function() return db.queueStatusAnchor end,
                            set = function(v)
                                db.queueStatusAnchor = v
                                ApplyQueueStatusIcon()
                            end,
                        })
                        AddSlider(queueRow2, 2, 2, LC["eqol_adapter.text.019"], {
                            min = 6,
                            max = 64,
                            step = 1,
                            get = function() return db.queueStatusSize end,
                            set = function(v)
                                db.queueStatusSize = v
                                ApplyQueueStatusIcon()
                            end,
                        }, 1, compactLabelWidth)

                        local queueRow3 = AddRow()
                        AddSlider(queueRow3, 2, 1, LC["eqol_adapter.text.020"], {
                            min = -200,
                            max = 200,
                            step = 1,
                            get = function() return db.queueStatusOffsetX end,
                            set = function(v)
                                db.queueStatusOffsetX = v
                                ApplyQueueStatusIcon()
                            end,
                        }, 1, compactLabelWidth)
                        AddSlider(queueRow3, 2, 2, LC["eqol_adapter.text.021"], {
                            min = -200,
                            max = 200,
                            step = 1,
                            get = function() return db.queueStatusOffsetY end,
                            set = function(v)
                                db.queueStatusOffsetY = v
                                ApplyQueueStatusIcon()
                            end,
                        }, 1, compactLabelWidth)
                    end
                end

                local height = math.max(-cursorY, rowHeight)
                root:SetHeight(height)
                return pageWidth, height
            end,
        },
    }
end

local function OnEnable(enable)
    isFeatureEnabled = enable
    if enable then
        SetupEQoLPowerHeightPatch()
        ApplyUIScale()
        ApplyBarVisibility()
        if not mapEnhancementsMovedToYMap then
            ApplyMinimapZoomVisibility()
            ApplyBelowMinimapWidgetFix()
            ApplyWorldMapScale()
            ApplyQueueStatusIcon()
            ApplyMinimapZoneTextAlignment()
        end
        ApplyBlizzardRaidManagerVisibility()
        ApplyShiftFocus()
        ApplyUFHeightAdaption()
        
        -- 由于单位框架可能在插件加载后稍晚创建完成，这里延迟执行字体覆盖逻辑
        C_Timer.After(1, SetupEQoLPowerHeightPatch)
        C_Timer.After(1, ApplyUFHealthTextSize)
        C_Timer.After(3, ApplyUFHealthTextSize)
    end
end

-- 如果我们在文件加载时处于开启状态，并且需要接管 EnhanceQoL 登录时的默认缩放行为，
-- 我们可能需要 Hook 一次原生的 applyUIScalePreset，以便当 EnhanceQoL 在 PLAYER_LOGIN
-- 调用它时，我们能在它之后立刻补上我们的缩放，或者如果它没开启，我们来执行。
local function HookEQoLApplyScale()
    local eqol = _G.EnhanceQoL
    if eqol and eqol.functions and eqol.functions.applyUIScalePreset then
        if not eqol.functions._yui_hooked_standalone_scale then
            local orig_applyUIScalePreset = eqol.functions.applyUIScalePreset
            eqol.functions.applyUIScalePreset = function(...)
                SafeCall(orig_applyUIScalePreset, ...)
                -- 原生应用完后，如果我们开启了，并且原生没有开启，我们覆盖它的结果
                if isFeatureEnabled then
                    local db = GetDB()
                    if db.enableScale and not IsEQoLScalingEnabled() then
                        ApplyUIScale()
                    end
                end
            end
            eqol.functions._yui_hooked_standalone_scale = true
        end
    end
end

HookEQoLApplyScale()

Components:RegisterFeature("EQoLAdapter", {
    name = LC["eqol_adapter.text.022"],
    description = LC["eqol_adapter.text.023"],
    default = true,
    callback = OnEnable,
    GetOptions = GetOptions
})

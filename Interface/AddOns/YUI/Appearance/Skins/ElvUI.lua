local ADDON_NAME, YUI = ...
local Skins = YUI.Appearance and YUI.Appearance.Skins or YUI.Skins
local cpuWatchdog = YUI.CPUWatchdog

local function Measured(callback, kind)
    if cpuWatchdog and cpuWatchdog.WrapAppearanceCallback then
        return cpuWatchdog:WrapAppearanceCallback("elvui", kind, callback)
    end
    return callback
end
local function ScheduleAfter(delay, callback)
    return C_Timer.After(delay, Measured(callback, "delayed"))
end
local function ScheduleTimer(delay, callback)
    return C_Timer.NewTimer(delay, Measured(callback, "delayed"))
end

local function IsFeatureEnabled()
    if Skins and Skins.IsEnabled then
        return Skins.IsEnabled("elvUI")
    end
    return false
end

local function GetOption(key, default)
    if Skins and Skins.GetOption then
        return Skins.GetOption(key, default)
    end
    return default
end

-- 如果 ElvUI 未加载，则不注册此功能
if type(_G.ElvUI) ~= "table" then return end

local ok, E = pcall(unpack, _G.ElvUI)
if not ok or type(E) ~= "table" then return end

-- ==========================================
-- 辅助函数
-- ==========================================

local function SafeCall(func, ...)
    if type(func) ~= "function" then return false end
    local success, result = pcall(func, ...)
    if not success and YUI.Debug then
        YUI:Debug("Appearance | ElvUI skin callback failed: " .. tostring(result))
    end
    return success, result
end

local function SafeHook(object, method, callback)
    if type(hooksecurefunc) ~= "function" then return false end
    if not object or type(method) ~= "string" or type(object[method]) ~= "function" then return false end

    callback = Measured(callback, "hook")
    local success, err = pcall(hooksecurefunc, object, method, function(...)
        SafeCall(callback, ...)
    end)
    if not success and YUI.Debug then
        YUI:Debug("Appearance | ElvUI hook failed: " .. tostring(method) .. " - " .. tostring(err))
    end
    return success
end

local lootHitCache = setmetatable({}, { __mode = "k" })
local skipBackdropCache = setmetatable({}, { __mode = "k" })

local function IsDescendantOrSelf(obj, root)
    if not obj or not root then return false end
    if obj == root then return true end

    if obj.IsObjectType and obj:IsObjectType("Frame") and obj.IsDescendantOf then
        if obj:IsDescendantOf(root) then return true end
    end

    local depth = 0
    local p = obj.GetParent and obj:GetParent()
    while p and depth < 30 do
        if p == root then return true end
        p = p.GetParent and p:GetParent()
        depth = depth + 1
    end

    return false
end

local function IsLootUI(frame)
    if not frame then return false end

    if lootHitCache[frame] then return true end

    local glh = _G.GroupLootHistoryFrame
    local lf = _G.LootFrame
    local gl1 = _G.GroupLootFrame1
    if not glh and not lf and not gl1 then return false end

    if glh and IsDescendantOrSelf(frame, glh) then
        lootHitCache[frame] = true
        return true
    end
    if lf and IsDescendantOrSelf(frame, lf) then
        lootHitCache[frame] = true
        return true
    end
    if gl1 and IsDescendantOrSelf(frame, gl1) then
        lootHitCache[frame] = true
        return true
    end

    for i = 2, 4 do
        local f = _G["GroupLootFrame" .. i]
        if not f then break end
        if IsDescendantOrSelf(frame, f) then
            lootHitCache[frame] = true
            return true
        end
    end

    return false
end

local function IsFrameBlacklisted(frame)
    if not frame then return true end

    -- 0. 如果不是Retail版本，则直接不判断
    if not YUI.IsRetail then return false end
    
    -- 1. 严格检查是否为 Tooltip 类型 (核心防 Taint)
    if frame.IsObjectType and frame:IsObjectType("GameTooltip") then
        return true
    end
    
    -- 2. 检查是否为禁止/受保护框架
    if frame.IsForbidden and frame:IsForbidden() then return true end
    if frame.IsProtected and frame:IsProtected() then return true end

    if IsLootUI(frame) then return true end
    
    -- 3. 特定黑名单
    local name = frame.GetName and frame:GetName()

    if name then
        if name:find("Tooltip", 1, true) then return true end
        if name:find("NamePlate", 1, true) then return true end -- 避免大量姓名板造成的性能开销
        if name:find("GroupLootFrame", 1, true) then return true end -- 避免战利品界面 Taint
        if name:find("GroupLootHistoryFrame", 1, true) then return true end -- 避免战利品界面 Taint
        if name:find("BackgroundArtFrame", 1, true) then return true end -- 避免战利品界面 Taint
        if name:find("LootFrame", 1, true) then return true end
        if name:find("CastingBar", 1, true) then return true end
        if name:find("SpellBar", 1, true) then return true end
        -- if name:find("CastingBar", 1, true) then return true end -- 避免施法条 Taint
        -- if name:find("SpellBar", 1, true) then return true end -- 避免施法条 Taint
    end
    
    return false
end

local function ApplySkinToFrame(frame, onlyShadow)
    -- 避免重复应用
    if not frame or (YUI.Skins and YUI.Skins.IsSkinned(frame)) then return end
    if not IsFeatureEnabled() then return end
    if YUI.Skins and YUI.Skins.ShouldSkipFrame and YUI.Skins.ShouldSkipFrame(frame) then return end

    local isBlacklisted = IsFrameBlacklisted(frame)

    if isBlacklisted then return end
    
    -- 调用 Core 中定义的渲染 API
    if YUI.Skins then
        local options = {
            edgeSize = E.twoPixelsPlease and 2 or 1,
            -- ElvUI 柔和阴影当前强制关闭，忽略玩家 DB 中的 YUISkins_Shadow/Appearance.skins.shadow。
            -- 未来若确认 ElvUI 阴影稳定，可移除此覆盖并重新在设置页显示对应选项。
            forceShadow = false,
            setupTextureCoordinates = E.ReplaceSetupTextureCoordinates and function(shadowFrame) 
                E:ReplaceSetupTextureCoordinates(shadowFrame) 
            end or nil,
            scaleFunc = function(size) return E:Scale(size) end
        }
        YUI.Skins.CreateSkinFrame(frame, nil, nil, onlyShadow, options)
    end
end

-- ==========================================
-- UnitFrame 特殊处理
-- ==========================================

local function IsCastbarElement(bar)
    if not bar then return true end

    local ok, name = pcall(function()
        return bar.GetName and bar:GetName()
    end)
    if ok and name then
        if name:find("CastingBar", 1, true) then return true end
        if name:find("Castbar", 1, true) then return true end
        if name:find("CastBar", 1, true) then return true end
        if name:find("SpellBar", 1, true) then return true end
    end

    return false
end

local function ApplyLightModeToBar(bar, unit)
    if IsCastbarElement(bar) then return end

    if Skins and Skins.ApplyLightModeToBar then
        Skins.ApplyLightModeToBar(bar, unit)
    end
end

local function SkinUnitFrameBar(bar)
    ApplySkinToFrame(bar, true) -- 单位框架仅添加阴影
end

local function SkinUnitFrameHealthBar(bar, unit)
    SkinUnitFrameBar(bar)
    ApplyLightModeToBar(bar, unit)
end

local function SkinUnitFrame(frame)
    if not frame then return end
    
    local unit = frame.unit
    
    -- 对整个单位框架应用外阴影
    ApplySkinToFrame(frame, true)

    if frame.Health then
        SkinUnitFrameHealthBar(frame.Health, unit)
    end
    if frame.Power then
        SkinUnitFrameBar(frame.Power)
    end
    if frame.Castbar then
        SkinUnitFrameBar(frame.Castbar)
    end
    if frame.AlternativePower then
        SkinUnitFrameBar(frame.AlternativePower)
    end
    if frame.ClassPower then
        SkinUnitFrameBar(frame.ClassPower)
    end
end

local RefreshLightMode
local lightModeRefreshQueued = false
local lightModeRefreshTimer
local lightModeRosterTransaction = false

local function RunQueuedLightModeRefresh()
    lightModeRefreshQueued = false
    lightModeRefreshTimer = nil
    local rosterTransaction = lightModeRosterTransaction
    lightModeRosterTransaction = false
    local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
    RefreshLightMode()
    if startedAt then
        cpuWatchdog:EndProbeTiming(
            "appearance.elvui.light-mode-refresh",
            startedAt,
            "ElvUI light-mode refresh",
            nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
        )
    end
end

local function RequestRefreshLightMode(event)
    if event == "GROUP_ROSTER_UPDATE" then lightModeRosterTransaction = true end
    if lightModeRefreshQueued then return end
    lightModeRefreshQueued = true
    if C_Timer and C_Timer.NewTimer then
        lightModeRefreshTimer = ScheduleTimer(0, RunQueuedLightModeRefresh)
    elseif C_Timer and C_Timer.After then
        ScheduleAfter(0, RunQueuedLightModeRefresh)
    else
        RunQueuedLightModeRefresh()
    end
end

RefreshLightMode = function()
    if not IsFeatureEnabled() or GetOption("lightMode", false) ~= true then return end

    local single = {
        { name = "Player", unit = "player" },
        { name = "Target", unit = "target" },
        { name = "TargetTarget", unit = "targettarget" },
        { name = "Focus", unit = "focus" },
        { name = "FocusTarget", unit = "focustarget" },
        { name = "Pet", unit = "pet" },
        { name = "Boss1", unit = "boss1" },
        { name = "Boss2", unit = "boss2" },
        { name = "Boss3", unit = "boss3" },
        { name = "Boss4", unit = "boss4" },
        { name = "Boss5", unit = "boss5" },
        { name = "Arena1", unit = "arena1" },
        { name = "Arena2", unit = "arena2" },
        { name = "Arena3", unit = "arena3" },
        { name = "Arena4", unit = "arena4" },
        { name = "Arena5", unit = "arena5" },
    }

    for _, info in ipairs(single) do
        local frame = _G["ElvUF_" .. info.name]
        if frame and frame.Health then
            ApplyLightModeToBar(frame.Health, info.unit or frame.unit)
        end
    end

    local function ApplyToHeader(header)
        if not header or not header.GetNumChildren then return end
        for i = 1, header:GetNumChildren() do
            local child = select(i, header:GetChildren())
            if child then
                if child.unit and child.Health then
                    ApplyLightModeToBar(child.Health, child.unit)
                end
                if child.GetNumChildren then
                    for j = 1, child:GetNumChildren() do
                        local button = select(j, child:GetChildren())
                        if button and button.unit and button.Health then
                            ApplyLightModeToBar(button.Health, button.unit)
                        end
                    end
                end
            end
        end
    end

    local header
    if _G.ElvUF_Raid1 and _G.ElvUF_Raid1.IsShown and _G.ElvUF_Raid1:IsShown() then
        header = _G.ElvUF_Raid1
    elseif _G.ElvUF_Raid2 and _G.ElvUF_Raid2.IsShown and _G.ElvUF_Raid2:IsShown() then
        header = _G.ElvUF_Raid2
    elseif _G.ElvUF_Raid3 and _G.ElvUF_Raid3.IsShown and _G.ElvUF_Raid3:IsShown() then
        header = _G.ElvUF_Raid3
    elseif _G.ElvUF_Party and _G.ElvUF_Party.IsShown and _G.ElvUF_Party:IsShown() then
        header = _G.ElvUF_Party
    end
    ApplyToHeader(header)

    if header == _G.ElvUF_Party then
        for i = 1, 5 do
            local pet = _G["ElvUF_PartyGroup1UnitButton" .. i .. "Pet"]
            if pet and pet.Health then
                ApplyLightModeToBar(pet.Health, pet.unit)
            end
        end
    end

    ApplyToHeader(_G.ElvUF_Tank)

    if _G["ElvUF_TankUnitButton1Target"] and _G["ElvUF_TankUnitButton1Target"].IsShown and _G["ElvUF_TankUnitButton1Target"]:IsShown() then
        for i = 1, 8 do
            local t = _G["ElvUF_TankUnitButton" .. i .. "Target"]
            if t and t.Health then
                ApplyLightModeToBar(t.Health, t.unit)
            end
        end
    end

    ApplyToHeader(_G.ElvUF_Assist)

    local raidpet = _G.ElvUF_RaidpetGroup1 or _G.ElvUF_Raidpet
    ApplyToHeader(raidpet)
end

local unitEventsRegistered = false
local unitFrameHooksInstalled = false
local lightModeEventOwner = {}

local function HookElvUIUnitFrames()
    local moduleOk, UF = pcall(E.GetModule, E, "UnitFrames", true)
    if not moduleOk or not UF then return false end
    if unitFrameHooksInstalled then
        if UF.units then
            for _, frame in pairs(UF.units) do SkinUnitFrame(frame) end
        end
        if UF.headers then
            for _, header in pairs(UF.headers) do
                if header and header.GetNumChildren then
                    for i = 1, header:GetNumChildren() do
                        local group = select(i, header:GetChildren())
                        if group and group.GetNumChildren then
                            for j = 1, group:GetNumChildren() do
                                local frame = select(j, group:GetChildren())
                                if frame and frame.Health then SkinUnitFrame(frame) end
                            end
                        end
                    end
                end
            end
        end
        ScheduleAfter(0.1, RequestRefreshLightMode)
        return true
    end
    unitFrameHooksInstalled = true

    -- 使用 oUF 官方回调：这是最稳妥的方案
    if E.oUF and E.oUF.RegisterInitCallback then
        pcall(E.oUF.RegisterInitCallback, E.oUF, function(frame)
            if frame and frame.unitframeType then
                ScheduleAfter(0.1, function()
                    SafeCall(SkinUnitFrame, frame)
                end)
            end
        end)
    end

    -- 拦截常用的 Configure 方法
    if UF.Configure_HealthBar then
        SafeHook(UF, "Configure_HealthBar", function(self, frame) SkinUnitFrame(frame) end)
    end
    if UF.Configure_Power then
        SafeHook(UF, "Configure_Power", function(self, frame) SkinUnitFrame(frame) end)
    end
    if UF.Configure_Castbar then
        SafeHook(UF, "Configure_Castbar", function(self, frame) SkinUnitFrame(frame) end)
    end

    if UF.PostUpdateHealthColor then
        SafeHook(UF, "PostUpdateHealthColor", function()
            RequestRefreshLightMode()
        end)
    end
    if UF.Style then
        SafeHook(UF, "Style", function()
            RequestRefreshLightMode()
        end)
    end
    
    -- 组框架重载配置钩子
    if UF.ConfigureFrame then
        SafeHook(UF, "ConfigureFrame", function(self, frame, which)
            if which and (which:find("party") or which:find("raid")) then
                ScheduleAfter(0.1, function()
                    SafeCall(SkinUnitFrame, frame)
                end)
            end
        end)
    end

    -- 处理已存在的框架
    if UF.units then
        for _, frame in pairs(UF.units) do SkinUnitFrame(frame) end
    end
    
    if UF.headers then
        for groupName, header in pairs(UF.headers) do
            if header and header.GetNumChildren then
                for i = 1, header:GetNumChildren() do
                    local group = select(i, header:GetChildren())
                    if group and group.GetNumChildren then
                        for j = 1, group:GetNumChildren() do
                            local frame = select(j, group:GetChildren())
                            if frame and frame.Health then SkinUnitFrame(frame) end
                        end
                    end
                end
            end
        end
    end

    if not unitEventsRegistered then
        unitEventsRegistered = true
        YUI.Event:On("PLAYER_TARGET_CHANGED", RequestRefreshLightMode, lightModeEventOwner)
        YUI.Event:On("PLAYER_FOCUS_CHANGED", RequestRefreshLightMode, lightModeEventOwner)
        YUI.Event:On("GROUP_ROSTER_UPDATE", RequestRefreshLightMode, lightModeEventOwner, {
            traceName = "Appearance:ElvUI:GROUP_ROSTER_UPDATE",
            throttle = 0.1,
        })
        YUI.Event:On("UNIT_PET", RequestRefreshLightMode, lightModeEventOwner)
    end

    ScheduleAfter(0.1, RequestRefreshLightMode)
    return true
end

local function TrySkinBackdrop(frame, tried)
    if not frame or skipBackdropCache[frame] then return end
    if not IsFeatureEnabled() then return end
    if IsFrameBlacklisted(frame) then
        skipBackdropCache[frame] = true
        return
    end
    
    tried = tried or 2

    -- 如果框架有 backdrop，我们对它的 backdrop 应用美化
    if frame.backdrop then
        ApplySkinToFrame(frame.backdrop)
    else
        -- 延迟重试，等待 ElvUI 创建 backdrop
        if tried > 0 then
            ScheduleAfter(0.1, function()
                TrySkinBackdrop(frame, tried - 1)
            end)
        end
    end
end

-- ==========================================
-- 全局皮肤 Hook
-- ==========================================

local skinSetTemplateHooked = false
local skinCreateBackdropHooked = false
local manualSkinScanQueued = false

local function HookElvUISkins()
    -- 1. 拦截 SetTemplate
    local mt = getmetatable(CreateFrame("Frame")).__index
    if not mt then return false end
    if mt.SetTemplate and not skinSetTemplateHooked then
        skinSetTemplateHooked = true
        SafeHook(mt, "SetTemplate", function(frame, template, glossaryTex, ignoreUpdates, forcePixelMode, isUnitFrameElement, isNamePlateElement)
            if isUnitFrameElement or isNamePlateElement then return end 
            if not frame or (YUI.Skins and YUI.Skins.IsSkinned(frame)) then return end
            ApplySkinToFrame(frame)
        end)
    end
    
    -- 2. 拦截 CreateBackdrop
    -- ElvUI 的很多大面板（如角色、背包）是创建一个内部的 backdrop 子框架作为背景的
    if mt.CreateBackdrop and not skinCreateBackdropHooked then
        skinCreateBackdropHooked = true
        SafeHook(mt, "CreateBackdrop", function(frame, template, glossTex, ignoreUpdates, forcePixelMode, isUnitFrameElement, isNamePlateElement)
            if isUnitFrameElement or isNamePlateElement then return end 
            if not frame or skipBackdropCache[frame] then return end
            TrySkinBackdrop(frame)
        end)
    end

    -- 3. 手动扫描并美化那些在插件加载前就已经创建了背景的框架
    -- ElvUI 在启动时会处理一些暴雪原生框架，我们的 hook 可能错过它们
    if not manualSkinScanQueued then
        manualSkinScanQueued = true
        ScheduleAfter(2, function()
            manualSkinScanQueued = false
            if not IsFeatureEnabled() then return end
            -- 遍历一些常见的带有 backdrop 的大面板
            local commonFrames = {
                _G.CharacterFrame,
                _G.SpellBookFrame,
                _G.FriendsFrame,
                _G.PVEFrame,
                _G.EncounterJournal,
                _G.GarrisonLandingPage,
                _G.QuestLogPopupDetailFrame,
                _G.WorldMapFrame,
                _G.BankFrame,
                _G.ContainerFrame1,
                _G.ContainerFrame2,
                _G.ContainerFrame3,
                _G.ContainerFrame4,
                _G.ContainerFrame5,
                _G.ProfessionsBookFrame,
            }

            for _, frame in ipairs(commonFrames) do
                if frame then
                    -- 如果主框架有模板，美化主框架
                    if frame.template then
                        ApplySkinToFrame(frame)
                    end
                    -- 如果主框架有 backdrop，美化其 backdrop
                    if frame.backdrop then
                        ApplySkinToFrame(frame.backdrop)
                    end
                end
            end
        
            -- 深度扫描：遍历 ElvUI 记录的所有被美化的框架
            if E.frames then
                for frame in pairs(E.frames) do
                    if frame then ApplySkinToFrame(frame) end
                end
            end
        end)
    end
    return skinSetTemplateHooked and skinCreateBackdropHooked
end

-- ==========================================
-- 模块注册
-- ==========================================

local enableRetryToken = 0
local enableRetryDelays = { 0.25, 0.5, 1, 2, 4 }

local function EnableSkins(attempt)
    if not IsFeatureEnabled() then return end

    local skinsReady = HookElvUISkins()
    local unitsReady = HookElvUIUnitFrames()
    if skinsReady and unitsReady then return end

    attempt = attempt or 1
    local delay = enableRetryDelays[attempt]
    if delay and C_Timer and C_Timer.After then
        local token = enableRetryToken
        ScheduleAfter(delay, function()
            if token == enableRetryToken then
                EnableSkins(attempt + 1)
            end
        end)
    end
end

local function OnEnable(enable)
    enableRetryToken = enableRetryToken + 1
    if enable then
        EnableSkins(1)
    end
end

local function RefreshEnabledState()
    OnEnable(IsFeatureEnabled())
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_LOGIN", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_ENTERING_WORLD", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("YUI_APPEARANCE_SKIN_OPTION_CHANGED", function(_, key, enabled)
        if key == "elvUI" then
            OnEnable(enabled == true)
        elseif IsFeatureEnabled() and (key == "lightMode" or key == "noise") then
            EnableSkins(1)
        end
    end)
end

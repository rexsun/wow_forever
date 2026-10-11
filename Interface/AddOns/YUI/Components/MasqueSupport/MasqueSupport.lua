local _, YUI = ...
local L = YUI.Locale and YUI.Locale:Get("MasqueSupport") or setmetatable({}, { __index = function(_, key) return tostring(key) end })
local SystemAPI = YUI.API and YUI.API.System or YUI.WOW_API

if not YUI.Components then return end
local Components = YUI.Components

local Masque = LibStub and LibStub("Masque", true)
if not Masque then return end

local function IsAddOnLoaded(name)
    return SystemAPI and SystemAPI.IsAddOnLoaded and SystemAPI.IsAddOnLoaded(name)
end

-- 如果有ElvUI or NDUI，则无需此模块
if IsAddOnLoaded("ElvUI") or IsAddOnLoaded("NDUI") or IsAddOnLoaded("NDui") then return end

-- 默认配置
local defaults = {
    blizzardActionBars = false,
    blizzardAuras = false,
}

local function GetDB(create)
    if not Components then return nil end
    if create == false then
        local store = Components:GetStore()
        local db = store and store.MasqueSupport_Config
        if type(db) ~= "table" then return nil end
        return db
    end
    if Components.EnsureConfig then
        return Components:EnsureConfig("MasqueSupport_Config", defaults)
    end
    return nil
end

local feature = {
    name = L["feature.name"],
    default = false,
    description = L["feature.description"],
    requiresReload = true,
}

-- 组实例缓存
local groups = {}
local skinnedButtons = {}
local pendingActionButtons = {}
local actionBarEventOwner = {}
local actionBarRegenOwner = {}
local actionBarRefreshEventsRegistered = false
local SecurityAPI = YUI.API and YUI.API.Security or YUI.WOW_API
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API

local function IsSecretValue(value)
    if SecurityAPI and SecurityAPI.IsSecretValue then
        return SecurityAPI.IsSecretValue(value) == true
    end
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function ReadSafeMember(owner, key)
    if owner == nil or IsSecretValue(owner) then return nil end
    local ok, value = pcall(function() return owner[key] end)
    if not ok or IsSecretValue(value) then return nil end
    return value
end

-- 工具：安全获取 Masque 组
local function GetMasqueGroup(groupName, staticID)
    if not Masque then return nil end
    local cacheKey = staticID or groupName
    if not groups[cacheKey] then
        groups[cacheKey] = Masque:Group("Blizzard", groupName, staticID)
    end
    return groups[cacheKey]
end

local function InCombatLockdownSafe()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown()
    end
    return InCombatLockdown and InCombatLockdown()
end

local function ProcessPendingActionButtons()
    if InCombatLockdownSafe() then
        if YUI.Event then
            YUI.Event:OffOwner(actionBarRegenOwner)
            YUI.Event:On("PLAYER_REGEN_ENABLED", ProcessPendingActionButtons, actionBarRegenOwner)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(1, ProcessPendingActionButtons)
        end
        return
    end

    if YUI.Event then
        YUI.Event:OffOwner(actionBarRegenOwner)
    end

    for btn, data in pairs(pendingActionButtons) do
        pendingActionButtons[btn] = nil
        if btn and data and data.group then
            if not skinnedButtons[btn] then
                local ok = pcall(data.group.AddButton, data.group, btn, nil, data.buttonType or "Action")
                if ok then
                    skinnedButtons[btn] = true
                end
            end
        end
    end
end

local function QueueActionButton(group, btn, buttonType)
    if not group or not btn then return end
    pendingActionButtons[btn] = { group = group, buttonType = buttonType or "Action" }
    if YUI.Event then
        YUI.Event:OffOwner(actionBarRegenOwner)
        YUI.Event:On("PLAYER_REGEN_ENABLED", ProcessPendingActionButtons, actionBarRegenOwner)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(1, ProcessPendingActionButtons)
    end
end

-- 动作条按钮直接交给 Masque；动态数值继续由 Blizzard ActionButton 自己维护。
local function SkinBlizzardButton(group, btn, buttonType)
    if not group or not btn then return end
    if skinnedButtons[btn] then return end
    if pendingActionButtons[btn] then return end

    if InCombatLockdownSafe() then
        QueueActionButton(group, btn, buttonType)
        return
    end

    local ok = pcall(group.AddButton, group, btn, nil, buttonType or "Action")
    if ok then
        skinnedButtons[btn] = true
    end
end

local function SkinExtraActionButton(group)
    local btn = ExtraActionButton1
    if btn then
        SkinBlizzardButton(group, btn, "Action")
        if btn.style then
            pcall(btn.style.SetDrawLayer, btn.style, "ARTWORK", -1)
        end
    end
end

local function SkinKnownActionButtons(group)
    local actionButtonCount = NUM_ACTIONBAR_BUTTONS or 12
    local multiBarButtonCount = NUM_MULTIBAR_BUTTONS or 12
    local petButtonCount = NUM_PET_ACTION_SLOTS or 10
    local possessButtonCount = NUM_POSSESS_SLOTS or 2

    local actionBars = {
        { prefix = "ActionButton", count = actionButtonCount, buttonType = "Action" },
        { prefix = "MultiBarBottomLeftButton", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "MultiBarBottomRightButton", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "MultiBarRightButton", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "MultiBarLeftButton", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "MultiBar5Button", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "MultiBar6Button", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "MultiBar7Button", count = multiBarButtonCount, buttonType = "Action" },
        { prefix = "PetActionButton", count = petButtonCount, buttonType = "Pet" },
        { prefix = "StanceButton", count = 10, buttonType = "Stance" },
        { prefix = "PossessButton", count = possessButtonCount, buttonType = "Possess" },
        { prefix = "OverrideActionBarButton", count = 6, buttonType = "Action" },
    }

    for _, bar in ipairs(actionBars) do
        for i = 1, bar.count do
            SkinBlizzardButton(group, _G[bar.prefix .. i], bar.buttonType)
        end
    end

    SkinExtraActionButton(group)
end

local function RegisterActionBarRefreshEvents(group)
    if not YUI.Event or actionBarRefreshEventsRegistered then return end
    actionBarRefreshEventsRegistered = true

    YUI.Event:OffOwner(actionBarEventOwner)

    local function refresh()
        SkinKnownActionButtons(group)
    end

    local events = {
        "PLAYER_ENTERING_WORLD",
        "UPDATE_EXTRA_ACTIONBAR",
        "UPDATE_OVERRIDE_ACTIONBAR",
        "UPDATE_VEHICLE_ACTIONBAR",
        "UPDATE_BONUS_ACTIONBAR",
        "PET_BAR_UPDATE",
        "UPDATE_SHAPESHIFT_FORM",
        "UPDATE_SHAPESHIFT_FORMS",
    }

    for _, event in ipairs(events) do
        YUI.Event:On(event, refresh, actionBarEventOwner)
    end
end

-- 延迟注册定时器
local function SetupMasqueGroups()
    local db = GetDB(false)
    if not db then return end

    if db.blizzardActionBars then
        local group = GetMasqueGroup(L["masque.group.action_bars"], "ActionBars")
        if group then
            SkinKnownActionButtons(group)
            RegisterActionBarRefreshEvents(group)
        end
    end

    if db.blizzardAuras then
        local group = GetMasqueGroup(L["masque.group.player_auras"], "PlayerAuras")
        if group then
            local dispelColorCurve
            if C_CurveUtil then
                local DEBUFF_DISPLAY_COLOR_INFO = {
                    [0] = DEBUFF_TYPE_NONE_COLOR,
                    [1] = DEBUFF_TYPE_MAGIC_COLOR,
                    [2] = DEBUFF_TYPE_CURSE_COLOR,
                    [3] = DEBUFF_TYPE_DISEASE_COLOR,
                    [4] = DEBUFF_TYPE_POISON_COLOR,
                    [9] = DEBUFF_TYPE_BLEED_COLOR, -- enrage
                    [11] = DEBUFF_TYPE_BLEED_COLOR,
                }
                dispelColorCurve = C_CurveUtil.CreateColorCurve()
                dispelColorCurve:SetType(Enum.LuaCurveType.Step)
                for i, c in pairs(DEBUFF_DISPLAY_COLOR_INFO) do
                    dispelColorCurve:AddPoint(i, c)
                end
            end

            local skinned = {}

            local function makeHook(containerGroup, container)
                local function updateFrames(frames)
                    for i = 1, #frames do
                        local frame = frames[i]
                        if frame.Icon and frame.Icon.GetTexture then
                            local skinWrapper = skinned[frame]
                            if not skinWrapper then
                                -- 创建承载可换肤组件的 wrapper，因为 11.0 原生光环不是正方形
                                skinWrapper = CreateFrame("Frame")
                                skinned[frame] = skinWrapper
                                skinWrapper:SetParent(frame)
                                skinWrapper:SetSize(30, 30)

                                -- 劫持原生图标，防止原生代码不断重置其位置
                                frame.Icon:Hide()
                                frame.SkinnedIcon = skinWrapper:CreateTexture(nil, "BACKGROUND")
                                frame.SkinnedIcon:SetSize(30, 30)
                                frame.SkinnedIcon:SetPoint("CENTER")
                                frame.SkinnedIcon:SetTexture(frame.Icon:GetTexture())
                                hooksecurefunc(frame.Icon, "SetTexture", function(_, tex)
                                    frame.SkinnedIcon:SetTexture(tex)
                                end)

                                if frame.Count then
                                    frame.Count:SetParent(skinWrapper)
                                end
                                if frame.DebuffBorder then
                                    frame.DebuffBorder:SetParent(skinWrapper)
                                    if AuraUtil.SetAuraBorderAtlas and dispelColorCurve then
                                        local texture
                                        hooksecurefunc(frame.DebuffBorder, "SetAtlas", function(self, atlas)
                                            if texture then
                                                self:SetTexture(texture)
                                            end

                                            if not IsSecretValue(atlas) then
                                                for type, info in pairs(AuraUtil.GetDebuffDisplayInfoTable()) do
                                                    if atlas == info.dispelAtlas or atlas == info.basicAtlas then
                                                        self:SetVertexColor(info.color:GetRGB())
                                                        return
                                                    end
                                                end
                                            end

                                            local buttonInfo = ReadSafeMember(frame, "buttonInfo")
                                            if type(buttonInfo) ~= "table" then buttonInfo = nil end
                                            local auraInstanceID = ReadSafeMember(frame, "deadlyInstanceID")
                                                or ReadSafeMember(buttonInfo, "auraInstanceID")
                                            local buttonIndex = ReadSafeMember(buttonInfo, "index")
                                            local unit = ReadSafeMember(frame, "unit") or "player"
                                            if not auraInstanceID and buttonIndex
                                                and UnitAPI and UnitAPI.ReadAuraIdentityByIndex then
                                                local filterOK, filter = pcall(frame.GetFilter, frame)
                                                local identity = UnitAPI.ReadAuraIdentityByIndex(
                                                    unit,
                                                    buttonIndex,
                                                    filterOK and filter or nil
                                                )
                                                auraInstanceID = identity and identity.auraInstanceID
                                            end
                                            if not auraInstanceID then
                                                self:SetVertexColor(DEBUFF_TYPE_NONE_COLOR:GetRGB())
                                                return
                                            end
                                            local success, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, dispelColorCurve)
                                            if not success or not color then
                                                self:SetVertexColor(DEBUFF_TYPE_NONE_COLOR:GetRGB())
                                                return
                                            end
                                            self:SetVertexColor(color:GetRGB())
                                        end)
                                        hooksecurefunc(frame.DebuffBorder, "SetTexture", function(self, tex)
                                            texture = tex
                                        end)
                                    end
                                end
                                if frame.TempEnchantBorder then
                                    frame.TempEnchantBorder:SetParent(skinWrapper)
                                    frame.TempEnchantBorder:SetVertexColor(0.75, 0, 1)
                                end
                                if frame.Symbol then
                                    frame.Symbol:SetParent(skinWrapper)
                                end

                                local bType = frame.auraType or "Aura"
                                if bType == "DeadlyDebuff" then
                                    bType = "Debuff"
                                end

                                containerGroup:AddButton(skinWrapper, {
                                    Icon = frame.SkinnedIcon,
                                    DebuffBorder = frame.DebuffBorder,
                                    EnchantBorder = frame.TempEnchantBorder,
                                    Count = frame.Count,
                                    HotKey = frame.Symbol
                                }, bType)
                            end

                            -- 更新 wrapper 的锚点位置
                            local auraContainer = container.AuraContainer
                            local point = "TOP"
                            if auraContainer then
                                if auraContainer.isHorizontal then
                                    if auraContainer.addIconsToTop then
                                        point = "BOTTOM"
                                    end
                                else
                                    if auraContainer.addIconsToRight then
                                        point = "LEFT"
                                    else
                                        point = "RIGHT"
                                    end
                                end
                            end
                            skinWrapper:ClearAllPoints()
                            skinWrapper:SetPoint(point)
                        end
                    end
                end

                return function(self)
                    updateFrames(self.auraFrames)
                    if self.exampleAuraFrames then
                        updateFrames(self.exampleAuraFrames)
                    end
                end
            end

            if BuffFrame and BuffFrame.UpdateAuraButtons then
                local buffHook = makeHook(group, BuffFrame)
                hooksecurefunc(BuffFrame, "UpdateAuraButtons", buffHook)
                hooksecurefunc(BuffFrame, "OnEditModeEnter", buffHook)
                hooksecurefunc(BuffFrame, "UpdateGridLayout", buffHook)
                buffHook(BuffFrame)
            end
            
            if DebuffFrame and DebuffFrame.UpdateAuraButtons then
                local debuffHook = makeHook(group, DebuffFrame)
                hooksecurefunc(DebuffFrame, "UpdateAuraButtons", debuffHook)
                hooksecurefunc(DebuffFrame, "OnEditModeEnter", debuffHook)
                hooksecurefunc(DebuffFrame, "UpdateGridLayout", debuffHook)
                debuffHook(DebuffFrame)
            end

            -- 目标/焦点框架光环 (Target / Focus)
            local targetBuffGroup = GetMasqueGroup(L["masque.group.target_buffs"], "TargetBuffs")
            local targetDebuffGroup = GetMasqueGroup(L["masque.group.target_debuffs"], "TargetDebuffs")
            
            if targetBuffGroup and targetDebuffGroup then
                local targetSkinned = {}
                
                local function skinTargetAuraFrame(frame, msqGroup, auraType)
                    if targetSkinned[frame] then return end
                    targetSkinned[frame] = true

                    msqGroup:AddButton(frame, {
                        Icon = frame.Icon,
                        Border = frame.Border,
                        Count = frame.Count,
                        Cooldown = frame.Cooldown,
                    }, auraType)
                end

                local function hookTargetFrameAuras(targetFrame)
                    if not targetFrame then return end
                    hooksecurefunc(targetFrame, "UpdateAuras", function(self)
                        if not self.auraPools then return end

                        local buffPool = self.auraPools:GetPool("TargetBuffFrameTemplate")
                        local debuffPool = self.auraPools:GetPool("TargetDebuffFrameTemplate")

                        if buffPool then
                            for frame in buffPool:EnumerateActive() do
                                skinTargetAuraFrame(frame, targetBuffGroup, "Buff")
                            end
                        end

                        if debuffPool then
                            for frame in debuffPool:EnumerateActive() do
                                skinTargetAuraFrame(frame, targetDebuffGroup, "Debuff")
                            end
                        end
                    end)
                end

                hookTargetFrameAuras(TargetFrame)
                hookTargetFrameAuras(FocusFrame)
            end

            -- 修复 EnhanceQoL 单位框架光环因加载顺序导致 Masque 丢失的问题
            if _G.EnhanceQoL and _G.EnhanceQoL.Aura and _G.EnhanceQoL.Aura.UF and _G.EnhanceQoL.Aura.UF.AuraUtil then
                local groupName = L["masque.group.unit_frame_buffs_debuffs"]
                
                local eqolGroup = Masque:Group("EnhanceQoL", groupName, "UnitFrameBuffsDebuffs")
                if eqolGroup then
                    local AuraUtil = _G.EnhanceQoL.Aura.UF.AuraUtil
                    hooksecurefunc(AuraUtil, "ensureAuraButton", function(_, icons, index)
                        local btn = icons and icons[index]
                        if btn and not skinnedButtons[btn] then
                            eqolGroup:AddButton(btn, {
                                Icon = btn.icon,
                                Cooldown = btn.cd,
                                Border = btn.border,
                            })
                            skinnedButtons[btn] = true
                        end
                    end)
                end
            end
        end
    end

end

-- 回调函数
feature.callback = function(enable)
    GetDB(true)

    if enable then
        SetupMasqueGroups()
    end
end

-- 设置面板选项
feature.GetOptions = function(self)
    local db = GetDB(true) or defaults

    local function Refresh()
        if self.RefreshCurrentModule then
            self:RefreshCurrentModule()
        end
    end

    local options = {
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = L["settings.blizzard_action_bars.label"],
                    tooltip = L["settings.blizzard_action_bars.tooltip"],
                    get = function() return db.blizzardActionBars end,
                    set = function(v) 
                        db.blizzardActionBars = v
                        Refresh()
                    end
                },
                {
                    type = "checkbox",
                    label = L["settings.blizzard_auras.label"],
                    tooltip = L["settings.blizzard_auras.tooltip"],
                    get = function() return db.blizzardAuras end,
                    set = function(v) 
                        db.blizzardAuras = v
                        Refresh()
                    end
                },
            }
        },
        {
            type = "text",
            label = L["settings.reload_note"],
            color = YUI.Settings.Colors.text,
        }
    }

    return options
end

YUI.Components:RegisterFeature("MasqueSupport", feature)

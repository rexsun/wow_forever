local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("Talents") end
    if YUI.YBar and YUI.YBar.EnsureDB then
        return YUI.YBar:EnsureDB()
    end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    return profile.YBar
end
local YBar = YUI.YBar
local GUI2 = YUI.GUI2
local L = YUI.Locale and YUI.Locale:Get("YBar") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}
local LegacyAPI = YUI.WOW_API
local API = (YUI.API and YUI.API.Talent) or LegacyAPI
local FrameAPI = (YUI.API and YUI.API.Frame) or LegacyAPI
local SecurityAPI = (YUI.API and YUI.API.Security) or LegacyAPI
local Icons = YUI.API and YUI.API.Icons

local function T(key, fallback, ...)
    local value = L[key] or fallback or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(format, value, ...)
        return ok and formatted or value
    end
    return value
end

local function GetSpecializationName(specID, fallback)
    if YUI.Locale and YUI.Locale.GetSpecializationName then
        return YUI.Locale:GetSpecializationName(specID, fallback)
    end
    return fallback or tostring(specID or "")
end
local LSM = LibStub("LibSharedMedia-3.0")
local Module = YBar.Module:New("Talents")

-- 常量
local ICON_SCOPE_ID = "ybar"
local DEFAULT_SIZE = 14
local DEFAULT_SPACING = 5
local DEFAULT_FONT = STANDARD_TEXT_FONT
local CURR_TALENT_FONT_WIDTH = 100
local talentRefreshPending = false
local talentPostCombatRefreshHandle = nil
local ScheduleTalentRefresh

local function GetCurrentMarkerText()
    return "|cff00ff00(" .. T("talents.menu.current_marker", "Current") .. ")|r"
end

local function GetStarterConfigText()
    return T("talents.menu.starter_build", "Starter Build")
end

local function GetScopedSpecIcon(specID, nativeIcon)
    if Icons and Icons.GetScopedSpecIcon then
        return Icons.GetScopedSpecIcon(specID, nativeIcon, ICON_SCOPE_ID)
    end
    return {
        texture = nativeIcon or 134400,
        texCoord = { 0, 1, 0, 1 },
    }
end

local function ApplyTalentButtonIcon(btn, specID, nativeIcon)
    local iconData = GetScopedSpecIcon(specID, nativeIcon)
    local fallback = nativeIcon or 134400

    if btn.iconSlot and YBar.SetIconSlotIcon then
        YBar:SetIconSlotIcon(btn.iconSlot, iconData, fallback)
    elseif btn.icon and Icons and Icons.ApplyIcon and iconData then
        Icons.ApplyIcon(btn.icon, iconData)
        if iconData.kind == "spec" and iconData.custom ~= true and not iconData.atlas then
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    elseif btn.icon then
        btn.icon:SetTexture(fallback)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function TalentContainerOnEvent()
    if YUI.IsRetail then
        ScheduleTalentRefresh(0)
    else
        Module:UpdateTalents()
    end
end

function Module:OnInitialize()
    self.frame = nil
    self.buttons = {}
end

function Module:AttachRuntime()
    local container = self.frame
    if not container then return end

    YUI.Event:OffOwner(self)
    YUI.Event:On("YUI_WORLD_READY", TalentContainerOnEvent, self)
    YUI.Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", TalentContainerOnEvent, self)
    YUI.Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", function(_, scopeID)
        if scopeID == ICON_SCOPE_ID then
            TalentContainerOnEvent()
        end
    end, self)

    if YUI.IsRetail then
        YUI.Event:On("PLAYER_SPECIALIZATION_CHANGED", TalentContainerOnEvent, self)
        YUI.Event:On("PLAYER_LOOT_SPEC_UPDATED", TalentContainerOnEvent, self)
        YUI.Event:On("ACTIVE_COMBAT_CONFIG_CHANGED", TalentContainerOnEvent, self)
        YUI.Event:On("CONFIG_COMMIT_FAILED", TalentContainerOnEvent, self)
        YUI.Event:On("STARTER_BUILD_ACTIVATION_FAILED", TalentContainerOnEvent, self)
        YUI.Event:On("TRAIT_CONFIG_UPDATED", TalentContainerOnEvent, self)
    else
        YUI.Event:On("CHARACTER_POINTS_CHANGED", TalentContainerOnEvent, self)
        YUI.Event:On("PLAYER_TALENT_UPDATE", TalentContainerOnEvent, self)
        YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", TalentContainerOnEvent, self)
    end
end

function Module:DetachRuntime()
    YUI.Event:OffOwner(self)
    talentPostCombatRefreshHandle = nil
    self.talentRefreshPendingInCombat = false
    self.talentRefreshNeedsLayout = false
    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner == self.frame then
            YUI.HideGameTooltip()
        elseif self.buttons then
            for _, btn in ipairs(self.buttons) do
                if owner == btn then
                    YUI.HideGameTooltip()
                    break
                end
            end
        end
    end
end

local function QueueTalentRefreshAfterCombat(skipLayout)
    Module.talentRefreshPendingInCombat = true
    if not skipLayout then
        Module.talentRefreshNeedsLayout = true
    end

    if talentPostCombatRefreshHandle then return end

    talentPostCombatRefreshHandle = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
        talentPostCombatRefreshHandle = nil
        if not Module.talentRefreshPendingInCombat then return end

        local needsLayout = Module.talentRefreshNeedsLayout
        Module.talentRefreshPendingInCombat = false
        Module.talentRefreshNeedsLayout = false

        if Module.UpdateTalents then
            Module:UpdateTalents(not needsLayout)
        end
    end, Module)
end

local function CreateTalentButton(parent, index)
    local size = DEFAULT_SIZE
    local iconSize = size + 2

    local btn = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = iconSize + 4 + CURR_TALENT_FONT_WIDTH,
        height = size + 6,
        showIcon = true,
        iconSize = iconSize,
        iconShape = "square",
        iconPadding = 0,
        iconLeftPadding = 0,
        hoverIcon = false,
        text = "",
        value = false,
        textColorKey = "color.ybar.text",
        textRightPadding = 0,
        gap = 4,
    })

    btn:SetHeight(size + 6)

    -- 图标
    if btn.iconSlot then
        btn.iconSlot:SetPoint("LEFT", btn, "LEFT", 0, 0)
    else
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
    end

    -- 文本
    -- 字体将在更新时设置
    btn.text:SetFont(DEFAULT_FONT, size, "")
    btn.text:SetShadowColor(0, 0, 0, 1)
    btn.text:SetShadowOffset(1, -1)
    btn.text:ClearAllPoints()
    btn.text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", 4, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWidth(CURR_TALENT_FONT_WIDTH)
    btn.text:SetWordWrap(false)

    btn:SetScript("OnEnter", function(self)
        if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(self:GetParent()) end
        if self.text then YBar:SetThemedTextAccent(self.text) end
        local tooltipAnchor = "ANCHOR_TOP"
        local bar = Module.parent

        if bar and bar:GetBottom() > GetScreenHeight() / 2 then
            tooltipAnchor = "ANCHOR_BOTTOM"
        end

        GameTooltip:SetOwner(self, tooltipAnchor)
        GameTooltip:ClearLines()

        if self.tooltipFunc then
            self.tooltipFunc()
        end

        GameTooltip:Show()

    end)

    btn:SetScript("OnLeave", function(self)
        if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(self:GetParent()) end
        YUI.HideGameTooltip()
        if self.text then YBar:RestoreThemedTextColor(self.text, "color.ybar.text") end
    end)

    YBar:CreateActionHost(btn, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })

    return btn
end

local function MarkSecureTalentClick()
    if not LegacyAPI.MarkCastBarDiagAction then return end

    LegacyAPI.MarkCastBarDiagAction("ToggleTalentFrameSecureClick")
    if LegacyAPI.LogCastBarDiag then
        LegacyAPI.LogCastBarDiag("ToggleTalentFrameSecureClick before")
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                LegacyAPI.LogCastBarDiag("ToggleTalentFrameSecureClick +0")
            end)
            C_Timer.After(0.2, function()
                LegacyAPI.LogCastBarDiag("ToggleTalentFrameSecureClick +0.2")
            end)
        end
    end
end

function ScheduleTalentRefresh(delay)
    if not Module.UpdateTalents then return end

    if not C_Timer or not C_Timer.After then
        Module:UpdateTalents()
        return
    end

    if talentRefreshPending then return end

    talentRefreshPending = true
    C_Timer.After(delay or 0, function()
        talentRefreshPending = false
        if Module.UpdateTalents then
            Module:UpdateTalents()
        end
    end)
end

local function GetStarterBuildName()
    return GetStarterConfigText()
end

local function GetCurrentLoadoutID(specID)
    if not YUI.IsRetail then return nil end

    if API.GetStarterBuildActive and API.GetStarterBuildActive() then
        return API.GetStarterBuildConfigID and API.GetStarterBuildConfigID()
    end

    if specID and API.GetLastSelectedSavedConfigID then
        local configID = API.GetLastSelectedSavedConfigID(specID)
        if configID then
            return configID
        end
    end

    if API.GetCurrentConfigID then
        return API.GetCurrentConfigID()
    end

    return specID and API.GetActiveConfigID(specID) or nil
end

local function GetConfigDisplayName(configID)
    if not configID then return nil end

    if API.IsStarterBuildConfigID and API.IsStarterBuildConfigID(configID) then
        return GetStarterBuildName()
    end

    local configInfo = API.GetConfigInfo(configID)
    if configInfo and configInfo.name then
        return configInfo.name
    end

    return nil
end

local function GetDefaultLoadoutName()
    return T(
        "talents.menu.default_loadout",
        _G.TALENT_FRAME_DROP_DOWN_DEFAULT or "默认配置"
    )
end

-- 辅助函数：获取配置名称（正式服）
local function GetLoadoutName()
    if YUI.IsRetail then
        local specID = API.GetSpecializationInfo(API.GetSpecialization())
        if API.GetStarterBuildActive and API.GetStarterBuildActive() then
            return GetStarterBuildName()
        end

        if specID and API.GetLastSelectedSavedConfigID then
            local savedConfigID = API.GetLastSelectedSavedConfigID(specID)
            if savedConfigID then
                return GetConfigDisplayName(savedConfigID)
            end
            return GetDefaultLoadoutName()
        end

        return GetConfigDisplayName(GetCurrentLoadoutID(specID))
    end
    return nil
end

local function GetLoadConfigResultName(result)
    local enum = Enum and Enum.LoadConfigResult
    if enum then
        if result == enum.Error then return "Error" end
        if result == enum.NoChangesNecessary then return "NoChangesNecessary" end
        if result == enum.LoadInProgress then return "LoadInProgress" end
        if result == enum.Ready then return "Ready" end
    end
    return tostring(result)
end

local function DebugLoadConfigResult(action, result, changeError)
    local enum = Enum and Enum.LoadConfigResult
    if (not result) or (enum and (result == enum.Error or result == enum.LoadInProgress)) or changeError then
        YUI:Debug(action .. " result:", GetLoadConfigResultName(result), changeError)
    end
end

local function LoadConfigByID(configID)
    local result, changeError, _, success = API.LoadAndApplyConfig(configID)
    DebugLoadConfigResult("LoadAndApplyConfig", result, changeError)
    if success then
        ScheduleTalentRefresh(0.2)
    end
    return result
end

local function HandleSpecButtonClick(self, button)
    if button == "LeftButton" then
        if FrameAPI.IsAltKeyDown() then
            YUI:OpenYBarModuleSettings("Talents")
            return
        end

        if YUI.IsRetail then return end
        if SecurityAPI.InCombatLockdown() then return end
        API.ToggleTalentFrame()
    elseif button == "RightButton" then
        local currentSpecIndex = API.GetSpecialization()

        if FrameAPI.IsShiftKeyDown() then
            LegacyAPI.RunSlashCmd("/me")
        elseif FrameAPI.IsControlKeyDown() and API.HasClassTalents and API.HasClassTalents() then
             local specID = API.GetSpecializationInfo(currentSpecIndex) -- 正式服返回 SpecID
             local configIDs = API.GetConfigIDsBySpecID(specID)
             local starterConfigID = API.GetStarterBuildConfigID and API.GetStarterBuildConfigID()
             local activeConfigID = GetCurrentLoadoutID(specID)
             local savedConfigID = API.GetLastSelectedSavedConfigID
                 and API.GetLastSelectedSavedConfigID(specID)
             local menuData = {}
             local menuConfigIDs = {}

             if configIDs then
                for _, id in ipairs(configIDs) do
                    table.insert(menuConfigIDs, id)
                end
             end

             if API.GetHasStarterBuild() and starterConfigID then
                local hasStarterConfig = false
                for _, id in ipairs(menuConfigIDs) do
                    if id == starterConfigID then
                        hasStarterConfig = true
                        break
                    end
                end
                if not hasStarterConfig then
                    table.insert(menuConfigIDs, starterConfigID)
                end
             end

             if #menuConfigIDs > 1 then
                for _, id in ipairs(menuConfigIDs) do
                    local cid, configName
                    if API.IsStarterBuildConfigID and API.IsStarterBuildConfigID(id) then
                        cid = id
                        configName = GetStarterBuildName()
                    else
                        local config = API.GetConfigInfo(id)
                        if config and config.ID then
                            cid = config.ID
                            configName = savedConfigID == nil
                                and config.ID == activeConfigID
                                and GetDefaultLoadoutName()
                                or GetConfigDisplayName(config.ID)
                        end
                    end

                    if cid and configName then
                        table.insert(menuData, {
                            icon = nil,
                            text = (cid == activeConfigID) and "|c" .. YBar.Colors_Hex.HEADER_TEXT_COLOR .. configName .. "|r" or configName,
                            rText = (cid == activeConfigID) and GetCurrentMarkerText() or "",
                            onClick = function()
                                LoadConfigByID(cid)
                            end
                        })
                    end
                end

                YBar:CreatePopIconMenu(self, menuData, {columns = 1, colWidth = 280, iconSize = 0, fontSize = 14, itemHeight = 18, gui2 = true})
             end
        else
            -- 鍒囨崲涓撶簿鑿滃崟
            local menuData = {}
            local numSpecs = API.GetNumSpecializations()

            -- 妫€鏌ュ弻澶╄祴锛堢粡鍏告棫涓?宸鐜嬩箣鎬掞級
            local hasDualSpec = false
            local activeGroup = nil
            if not YUI.IsRetail then -- Classic/Wrath
                 hasDualSpec = API.GetNumSpecializations() == 2
                 activeGroup = API.GetSpecialization()

                 -- 濡傛灉鏄粡鍏告棫涓?宸鐜嬩箣鎬掞紝鍙抽敭鐩存帴鍒囨崲鍙屽ぉ璧嬶紙濡傛灉瀛樺湪锛?
                 if hasDualSpec then
                      API.SetSpecialization(activeGroup == 1 and 2 or 1)
                      return
                 end
            end

            -- 姝ｅ紡鏈嶏細鏄剧ず鑿滃崟
            if YUI.IsRetail then
                for i = 1, numSpecs do
                    local id, name, _, icon = API.GetSpecializationInfo(i)
                    table.insert(menuData, {
                        icon = icon,
                        iconData = GetScopedSpecIcon(id, icon),
                        text = GetSpecializationName(id, name),
                        rText = (currentSpecIndex == i) and GetCurrentMarkerText() or "",
                        onClick = function() API.SetSpecialization(i) end
                    })
                end
                YBar:CreatePopIconMenu(self, menuData, {columns = 1, colWidth = 160, iconSize = 24, iconVariant = "surface", iconShape = "square", iconPadding = 2, fontSize = 16, itemHeight = 32, gui2 = true})
            end
        end
    end
end

function Module:UpdateTalents(skipLayout)
    if not self.buttons or #self.buttons == 0 then return end
    if SecurityAPI.InCombatLockdown and SecurityAPI.InCombatLockdown() then
        QueueTalentRefreshAfterCombat(skipLayout)
        return
    end

    -- 加载设置
    local db = GetYBarDB().Talents or {}
    local size = db.size or DEFAULT_SIZE
    local iconSize = size + 2
    local spacing = db.spacing or DEFAULT_SPACING
    local font = db.font
    local fontPath = YBar:ResolveFontPath(font, DEFAULT_FONT, LSM)

    -- 1. 专精拾取按钮
    local lootBtn = self.buttons[1]

    -- 检查是否应启用专精拾取
    local enableLootSpec = db.enableLootSpec
    if enableLootSpec == nil then enableLootSpec = true end

    if not YUI.IsRetail or not enableLootSpec then
        lootBtn:Hide()
    else
        lootBtn:Show()
        local currentLootSpec = API.GetLootSpecialization()
        local lootIcon, lootName, lootSpecID

        if currentLootSpec == 0 then
            local currentSpecIndex = API.GetSpecialization()
            if currentSpecIndex then
                local id, name, _, icon = API.GetSpecializationInfo(currentSpecIndex)
                lootName = T("talents.menu.current_marker", "Current")
                lootSpecID = id
                lootIcon = icon
            else
                lootName = T("talents.tooltip.no_spec", "无")
                lootIcon = 134400 -- Question mark
            end
        else
            local _, name, _, icon = API.GetSpecializationInfoByID(currentLootSpec)
            lootName = GetSpecializationName(currentLootSpec, name)
            lootSpecID = currentLootSpec
            lootIcon = icon
        end

        ApplyTalentButtonIcon(lootBtn, lootSpecID, lootIcon)
        lootBtn.text:SetText(format(T("talents.bar.loot_spec_format", "Loot: %s"), lootName))
    end

    if YUI.IsRetail and enableLootSpec then
        lootBtn.tooltipFunc = function()
            local currentLootSpec = API.GetLootSpecialization()
            local lootName
            if currentLootSpec == 0 then
                lootName = T("talents.menu.current_spec", "当前")
            else
                local _, name = API.GetSpecializationInfoByID(currentLootSpec)
                lootName = GetSpecializationName(currentLootSpec, name)
            end

            GameTooltip:AddLine(string.format("|c%s%s|r: |c%s%s|r", YBar.Colors_Hex.HEADER_TEXT_COLOR, T("talents.tooltip.loot_spec", "专精拾取"), GUI2.Colors_Hex.class, lootName), 1, 1, 1)
            -- GameTooltip:AddLine(" ")
            -- GameTooltip:AddLine(string.format("|cffffffff当前: |r|c%s%s|r", YBar.Colors_Hex.HEADER_TEXT_COLOR, lootName))
            GameTooltip:AddLine(" ")
            local white = "|cffffffff"
            local gold = "|c" .. CreateColor(1, 0.82, 0):GenerateHexColor()
            GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("talents.action.switch_loot_spec", "切换专精拾取")))
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
        end

        lootBtn.ybarOnClick = function(self, button)
            if button == "LeftButton" and FrameAPI.IsAltKeyDown() then
                YUI:OpenYBarModuleSettings("Talents")
                return
            end
            if button == "RightButton" then
                local menuData = {}
                local currentLootSpec = API.GetLootSpecialization()

                -- 添加“当前专精”选项
                local currentSpecIndex = API.GetSpecialization()
                local currentSpecID
                local currentIcon
                if currentSpecIndex then
                    local id, _, _, icon = API.GetSpecializationInfo(currentSpecIndex)
                    currentSpecID = id
                    currentIcon = icon
                end

                table.insert(menuData, {
                    icon = currentIcon or 134400,
                    iconData = GetScopedSpecIcon(currentSpecID, currentIcon or 134400),
                    text = T("talents.menu.current_spec", "当前专精"),
                    rText = (currentLootSpec == 0) and GetCurrentMarkerText() or "",
                    onClick = function() API.SetLootSpecialization(0) end
                })

                -- 添加其他专精
                local numSpecs = API.GetNumSpecializations()
                for i = 1, numSpecs do
                    local id, name, _, icon = API.GetSpecializationInfo(i)
                    -- 正式服：id 为 SpecID；巫妖王之怒：id 为 GroupIndex
                    table.insert(menuData, {
                        icon = icon,
                        iconData = GetScopedSpecIcon(id, icon),
                        text = GetSpecializationName(id, name),
                        rText = (currentLootSpec == id) and GetCurrentMarkerText() or "",
                        onClick = function() API.SetLootSpecialization(id) end
                    })
                end

                YBar:CreatePopIconMenu(self, menuData, {columns = 1, colWidth = 160, iconSize = 24, iconVariant = "surface", iconShape = "square", iconPadding = 2, fontSize = 16, itemHeight = 32, gui2 = true})
            end
        end
        if lootBtn.actionHost then
            lootBtn.actionHost:SetActions({
                left = {
                    kind = "custom",
                    onClick = function(_, _, owner)
                        owner:ybarOnClick("LeftButton")
                    end,
                },
                altLeft = {
                    kind = "custom",
                    onClick = function(_, _, owner)
                        owner:ybarOnClick("LeftButton")
                    end,
                },
                right = {
                    kind = "custom",
                    onClick = function(_, _, owner)
                        owner:ybarOnClick("RightButton")
                    end,
                },
            })
        end
    end

    -- 2. 当前专精按钮
    local specBtn = self.buttons[2]
    local currentSpecIndex = API.GetSpecialization()
    local specIcon, specName, specID

    if currentSpecIndex then
        local id, name, _, icon = API.GetSpecializationInfo(currentSpecIndex)
        specName = GetSpecializationName(id, name)
        specID = id
        specIcon = icon

        -- 在正式服，根据设置决定是否显示配置名称
        if YUI.IsRetail then
             local displayMode = db.displayMode or "LOADOUT"
             if displayMode == "LOADOUT" then
                 local loadoutName = GetLoadoutName()
                 if loadoutName then
                     specName = loadoutName
                 end
             end
        end
    else
        specName = T("talents.tooltip.no_spec", "无专精")
        specIcon = 134400
    end

    ApplyTalentButtonIcon(specBtn, specID, specIcon)
    -- specBtn.text:SetText(#specName > 10 and string.sub(specName, 1, 10) or specName)
    specBtn.text:SetText(specName)

    specBtn.tooltipFunc = function()
        -- GameTooltip:AddLine("当前专精", 1, 1, 1)
        GameTooltip:AddLine(string.format("|c%s%s|r: |c%s%s|r", YBar.Colors_Hex.HEADER_TEXT_COLOR, T("talents.tooltip.current_spec", "当前专精"), GUI2.Colors_Hex.class, specName), 1, 1, 1)
        -- GameTooltip:AddLine(" ")
        -- GameTooltip:AddLine(string.format("|cffffffff当前: |r|c%s%s|r", YBar.Colors_Hex.HEADER_TEXT_COLOR, specName))
        GameTooltip:AddLine(" ")
        local white = "|cffffffff"
        local gold = "|c" .. CreateColor(1, 0.82, 0):GenerateHexColor()
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, T("talents.action.open_talents", "打开天赋面板")))
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("talents.action.switch_current_spec", "切换当前专精")))
        if YUI.IsRetail then
            GameTooltip:AddLine(format("%sCtrl + %s: |r%s%s|r", white, LC["common.right_click"], gold, T("talents.action.switch_loadout", "切换天赋配置")))
            GameTooltip:AddLine(format("%sShift + %s: |r%sMurlokExport|r", white, LC["common.right_click"], gold))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
    end

    if not YUI.IsRetail or not SecurityAPI.InCombatLockdown() then
        local actions = {
            altLeft = {
                kind = "custom",
                onClick = function(_, _, owner)
                    HandleSpecButtonClick(owner, "LeftButton")
                end,
            },
            right = {
                kind = "custom",
                onClick = function(_, _, owner)
                    HandleSpecButtonClick(owner, "RightButton")
                end,
            },
            ctrlRight = {
                kind = "custom",
                onClick = function(_, _, owner)
                    HandleSpecButtonClick(owner, "RightButton")
                end,
            },
            shiftRight = {
                kind = "custom",
                onClick = function(_, _, owner)
                    HandleSpecButtonClick(owner, "RightButton")
                end,
            },
        }

        if YUI.IsRetail then
            if PlayerSpellsMicroButton then
                actions.left = {
                    kind = "click",
                    clickbutton = PlayerSpellsMicroButton,
                    beforeClick = function()
                        MarkSecureTalentClick()
                    end,
                }
            else
                actions.left = {
                    kind = "macro",
                    macrotext = "/click PlayerSpellsMicroButton LeftButton",
                    beforeClick = function()
                        MarkSecureTalentClick()
                    end,
                }
            end
            actions.ctrlLeft = { kind = "noop" }
            actions.shiftLeft = { kind = "noop" }
        else
            actions.left = {
                kind = "custom",
                onClick = function(_, _, owner)
                    HandleSpecButtonClick(owner, "LeftButton")
                end,
            }
        end

        if specBtn.actionHost then
            specBtn.actionHost:SetActions(actions)
        end
    end
    -- 通用更新逻辑（尺寸、字体、布局）
    local prev = nil
    local totalWidth = 0

    for i, btn in ipairs(self.buttons) do
        btn:SetHeight(size + 6)
        if btn.iconSlot then
            btn.iconSlot:SetSize(iconSize, iconSize)
            btn.iconSlot:ClearAllPoints()
            btn.iconSlot:SetPoint("LEFT", btn, "LEFT", 0, 0)
        else
            btn.icon:SetSize(iconSize, iconSize)
            btn.icon:ClearAllPoints()
            btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
        end
        local globalDB = GetYBarDB() or {}
        local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")

        btn.text:SetFont(fontPath, size, fontFlag)

        if globalDB.fontShadow then
            btn.text:SetShadowColor(0, 0, 0, 1)
            btn.text:SetShadowOffset(1, -1)
        else
            btn.text:SetShadowOffset(0, 0)
        end
        btn.text:ClearAllPoints()
        btn.text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", 4, 0)

        local textWidth = btn.text:GetStringWidth()
        local btnWidth = iconSize + 4 + math.min(textWidth, CURR_TALENT_FONT_WIDTH)
        btn:SetWidth(btnWidth)

        if (i == 1 and (not YUI.IsRetail or not enableLootSpec)) then
             btn:Hide()
        else
             btn:Show()
             btn:ClearAllPoints()
             if prev then
                 btn:SetPoint("LEFT", prev, "RIGHT", spacing * 2, 0)
             else
                 btn:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
             end
             prev = btn
             totalWidth = totalWidth + btnWidth + (prev and (spacing * 2) or 0)
        end
    end

    -- 调整总宽度
    totalWidth = 0
    local visibleCount = 0
    for i = 1, 2 do
        if self.buttons[i] and self.buttons[i]:IsShown() then
            if visibleCount > 0 then
                totalWidth = totalWidth + (spacing * 2)
            end
            totalWidth = totalWidth + self.buttons[i]:GetWidth()
            visibleCount = visibleCount + 1
        end
    end

    if self.frame then
        self.frame:SetWidth(totalWidth > 0 and totalWidth or 10)
        self.frame:SetHeight(size + 6)
    end

    if not skipLayout and YBar and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
end

function Module:CreateBarItem(parent)
    local container = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        showIcon = false,
        hoverIcon = false,
        text = false,
        value = false,
    })

    self.buttons = {}
    for i = 1, 2 do
        local btn = CreateTalentButton(container, i)
        table.insert(self.buttons, btn)
    end

    self.frame = container

    if not YUI.YBar or YUI.YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end

    Module:UpdateBarItem(container, parent)

    return container
end

function Module:UpdateBarItem(frame, parent)
    if parent then
        self.parent = parent
    end
    if not frame then return end
    self:UpdateTalents(true)
end

function Module:GetWidth()
    if self.frame then
        return self.frame:GetWidth()
    end
    return 10
end

YBar:RegisterModule(Module, {
    id = "ybar.talents",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api"},
    defaultEnabled = true,
})

function Module:GetOptions()
    local S = YUI.Settings
    local LSM = LibStub("LibSharedMedia-3.0")
    local Locale = YUI.Locale
    local YBarL = Locale and Locale:Get("YBar") or {}
    local CoreL = Locale and Locale:Get("Core") or {}

    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFont = nil
    for name, path in pairs(fontList) do
        table.insert(fontOptions, { text = name, value = path })
        if name == "默认" then defaultFont = path end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    local options = {
        {
            type = "dropdown",
            label = CoreL["common.font"] or "Font",
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function() return GetYBarDB().Talents and GetYBarDB().Talents.font or defaultFont end,
            set = function(val)
                if not GetYBarDB().Talents then GetYBarDB().Talents = {} end
                GetYBarDB().Talents.font = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "slider",
            label = CoreL["common.size"] or "Size",
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return GetYBarDB().Talents and GetYBarDB().Talents.size or DEFAULT_SIZE end,
            set = function(val)
                if not GetYBarDB().Talents then GetYBarDB().Talents = {} end
                GetYBarDB().Talents.size = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "slider",
            label = CoreL["common.spacing"] or "Spacing",
            width = 220,
            min = 0, max = 50, step = 1,
            get = function() return GetYBarDB().Talents and GetYBarDB().Talents.spacing or DEFAULT_SPACING end,
            set = function(val)
                if not GetYBarDB().Talents then GetYBarDB().Talents = {} end
                GetYBarDB().Talents.spacing = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "dropdown",
            label = YBarL["talents.settings.display_mode"] or "Display Mode",
            width = 220,
            options = {
                { text = YBarL["talents.settings.loadout_name"] or "Loadout Name", value = "LOADOUT" },
                { text = YBarL["talents.settings.spec_name"] or "Spec Name", value = "SPEC" }
            },
            default = "LOADOUT",
            get = function()
                return GetYBarDB().Talents and GetYBarDB().Talents.displayMode or "LOADOUT"
            end,
            set = function(val)
                if not GetYBarDB().Talents then GetYBarDB().Talents = {} end
                GetYBarDB().Talents.displayMode = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
                -- Force update the module content immediately
                if Module.UpdateTalents then Module:UpdateTalents() end
            end
        },
        {
            type = "checkbox",
            label = YBarL["talents.settings.enable_loot_spec"] or "Enable Loot Specialization",
            default = true,
            get = function()
                if GetYBarDB().Talents and GetYBarDB().Talents.enableLootSpec ~= nil then
                    return GetYBarDB().Talents.enableLootSpec
                end
                return true
            end,
            set = function(val)
                if not GetYBarDB().Talents then GetYBarDB().Talents = {} end
                GetYBarDB().Talents.enableLootSpec = val
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        }
    }
    return options
end

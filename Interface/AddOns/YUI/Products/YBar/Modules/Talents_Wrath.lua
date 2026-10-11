local YUI = _G.YUI
local function GetYBarDB()
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
local GUI2 = YUI.GUI2
local YBar = YUI.YBar
local L = YUI.Locale and YUI.Locale:Get("YBar") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}
local LegacyAPI = YUI.WOW_API
local API = (YUI.API and YUI.API.Talent) or LegacyAPI
local FrameAPI = (YUI.API and YUI.API.Frame) or LegacyAPI
local SecurityAPI = (YUI.API and YUI.API.Security) or LegacyAPI
local F = YUI.F

local function T(key, fallback, ...)
    local value = L[key] or fallback or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(format, value, ...)
        return ok and formatted or value
    end
    return value
end

local Module = YBar.Module:New("Talents")

function Module:OnInitialize()
    self.db = GetYBarDB().Talents or {}
    self.frame = nil
    self.buttons = {}
    
    GetYBarDB().Talents = self.db
end

function Module:AttachRuntime()
    if self.callbacksAttached then return end
    YUI.Event:On("CHARACTER_POINTS_CHANGED", "Refresh", self)
    YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", "Refresh", self)
    YUI.Event:On("YUI_WORLD_READY", "Refresh", self)
    self.callbacksAttached = true
end

function Module:DetachRuntime()
    YUI.Event:OffOwner(self)
    self.callbacksAttached = false

    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner == self.frame or owner == self.btn then
            YUI.HideGameTooltip()
        end
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
    
    -- 只创建一个天赋按钮
    local btn = YBar:CreateBarItem(container, {
        variant = "bare",
        width = 80,
        height = 20,
        showIcon = true,
        iconSize = 14,
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
    btn:SetHeight(20)
    btn:SetPoint("LEFT", container, "LEFT", 0, 0)
    -- btn:RegisterForClicks("AnyUp", "AnyDown")
    
    if btn.iconSlot then
        btn.iconSlot:SetPoint("LEFT", btn, "LEFT", 0, 0)
    else
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
    end
    
    local text = btn.text
    text:SetFont(STANDARD_TEXT_FONT, 12, "")
    text:ClearAllPoints()
    text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", 4, 0)
    text:SetJustifyH("LEFT")
    
    btn:SetScript("OnEnter", function(self)
        if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(self:GetParent()) end
        if self.text then YBar:SetThemedTextAccent(self.text) end
        if self.tooltipFunc then
            local anchor, yOffset = F:GetTooltipAnchor(self)
            GameTooltip:SetOwner(self, anchor, 0, yOffset)
            self.tooltipFunc()
            GameTooltip:Show()
        end
    end)
    
    btn:SetScript("OnLeave", function(self)
        if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(self:GetParent()) end
        YUI.HideGameTooltip()
        if self.text then YBar:RestoreThemedTextColor(self.text, "color.ybar.text") end
    end)
    
    -- 点击行为说明
    -- 左键：打开天赋面板
    -- Alt + 左键：打开模块设置
    -- 右键：在双天赋之间切换
    btn.ybarOnClick = function(self, button)
        if button == "LeftButton" then
            if FrameAPI.IsAltKeyDown() then
                YUI:OpenYBarModuleSettings("Talents")
                return
            end
            if SecurityAPI.InCombatLockdown() then return end
            API.ToggleTalentFrame()
        elseif button == "RightButton" then
            local numGroups = API.GetNumSpecializations()
            if numGroups == 2 and not SecurityAPI.InCombatLockdown() then
                local activeGroup = API.GetSpecialization() or 1
                local targetGroup = activeGroup == 1 and 2 or 1
                API.SetSpecialization(targetGroup)
            end
        end
    end

    YBar:CreateActionHost(btn, {
        secure = false,
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if btn.actionHost then
        btn.actionHost:SetActions({
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
    
    self.btn = btn
    self.frame = container
    
    self:UpdateBarItem()
    
    return container
end

function Module:UpdateBarItem(skipLayout)
    if not self.btn or not self.frame then return end
    
    local db = self.db
    local fontSize = db.fontSize or 12
    local iconSize = db.iconSize or 14
    local iconSpacing = db.iconSpacing or 4
    
    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontOutline and "OUTLINE" or ""
    
    local btn = self.btn
    
    btn.text:SetFont(STANDARD_TEXT_FONT, fontSize, fontFlag)
    
    if globalDB.fontShadow then
        btn.text:SetShadowColor(0, 0, 0, 1)
        btn.text:SetShadowOffset(1, -1)
    else
        btn.text:SetShadowOffset(0, 0)
    end
    
    if btn.iconSlot then
        btn.iconSlot:SetSize(iconSize, iconSize)
        btn.iconSlot:ClearAllPoints()
        btn.iconSlot:SetPoint("LEFT", btn, "LEFT", 0, 0)
    else
        btn.icon:SetSize(iconSize, iconSize)
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
    end
    btn.text:ClearAllPoints()
    btn.text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", iconSpacing, 0)
    
    local shouldSkip = true
    if skipLayout == false then
        shouldSkip = false
    end
    
    self:UpdateTalents(shouldSkip)
end

function Module:UpdateTalents(skipLayout)
    if not self.btn then return end
    
    local btn = self.btn
    
    -- 获取天赋组信息
    local numGroups = API.GetNumSpecializations()
    local activeGroup = API.GetSpecialization() or 1
    
    local activeName, activeIcon = T("talents.tooltip.unlearned", "未激活天赋"), 134400
    local classIcon = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
    local _, classFilename = UnitClass("player")
    
    -- 尝试获取主天赋信息
    local activeID, aName, aDesc, aIcon = API.GetSpecializationInfo(activeGroup)
    if aName and aName ~= "未激活天赋" then
        activeName = aName
        activeIcon = aIcon
    else
        -- 没有加点，使用职业图标
        activeIcon = classIcon
        local classCoords = CLASS_ICON_TCOORDS[classFilename]
        if classCoords then
            btn.icon:SetTexCoord(unpack(classCoords))
        end
    end
    
    -- 恢复非职业图标的 TexCoord
    if activeIcon ~= classIcon then
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    
    btn.icon:SetTexture(activeIcon)
    -- btn.text:SetText(YUI.F:GetGradientText(activeName, {r=1, g=1, b=0}, {r=1, g=0.27, b=0}))
    btn.text:SetText(activeName)
    
    -- 调整宽度
    local width = (btn.iconSlot and btn.iconSlot:GetWidth() or btn.icon:GetWidth()) + (self.db.iconSpacing or 4) + btn.text:GetStringWidth()
    btn:SetWidth(width)
    self.frame:SetWidth(width)
    
    -- 构建 Tooltip 逻辑（静态化以减少闭包开销）
    if not btn.tooltipFunc then
        btn.tooltipFunc = function()
            GameTooltip:AddLine(T("talents.tooltip.title", "天赋与专精"))
            GameTooltip:AddLine(" ")
            
            -- 主天赋与副天赋固定顺序显示
            local colorActive = "|c" .. GUI2.Colors_Hex.class
            local colorInactive = "|cff808080"
            
            local numGroups = API.GetNumSpecializations()
            local activeGroup = API.GetSpecialization() or 1
            
            -- 主天赋 (Group 1)
            local _, name1 = API.GetSpecializationInfo(1)
            local display1 = (name1 and name1 ~= "未激活天赋") and name1 or T("talents.tooltip.unlearned", "未学习")
            if activeGroup == 1 then
                GameTooltip:AddDoubleLine(colorActive .. T("talents.tooltip.primary_talent", "主天赋:") .. "|r", colorActive .. display1 .. "|r")
            else
                GameTooltip:AddDoubleLine(colorInactive .. T("talents.tooltip.primary_talent", "主天赋:") .. "|r", colorInactive .. display1 .. "|r")
            end
            
            -- 副天赋 (Group 2)
            if numGroups == 2 then
                local _, name2 = API.GetSpecializationInfo(2)
                local display2 = (name2 and name2 ~= "未激活天赋") and name2 or T("talents.tooltip.unlearned", "未学习")
                if activeGroup == 2 then
                    GameTooltip:AddDoubleLine(colorActive .. T("talents.tooltip.secondary_talent", "副天赋:") .. "|r", colorActive .. display2 .. "|r")
                else
                    GameTooltip:AddDoubleLine(colorInactive .. T("talents.tooltip.secondary_talent", "副天赋:") .. "|r", colorInactive .. display2 .. "|r")
                end
            end
            
            GameTooltip:AddLine(" ")
            local white = "|cffffffff"
            local gold = "|c" .. CreateColor(1, 0.82, 0):GenerateHexColor()
            GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, T("talents.action.open_talents", "打开天赋面板")))
            
            if numGroups == 2 then
                GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("talents.action.switch_dual_spec", "切换双天赋")))
            end
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
        end
    end
    
    if not skipLayout and YBar and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
end

function Module:Refresh()
    if self.frame then
        self:UpdateBarItem(false)
    end
end

function Module:GetOptions()
    local Locale = YUI.Locale
    local YBarL = Locale and Locale:Get("YBar") or {}
    local CoreL = Locale and Locale:Get("Core") or {}

    return {
        { type = "header", label = YBarL["ybar.settings.section.appearance"] or "Appearance" },
        {
            type = "slider",
            label = CoreL["common.font_size"] or "Font Size",
            key = "fontSize",
            min = 10, max = 24, step = 1,
            default = 12,
            onChange = function(self, value)
                Module.db.fontSize = value
                Module:Refresh()
            end
        },
        {
            type = "slider",
            label = YBarL["ybar.settings.option.icon_size"] or "Icon Size",
            key = "iconSize",
            min = 10, max = 32, step = 1,
            default = 14,
            onChange = function(self, value)
                Module.db.iconSize = value
                Module:Refresh()
            end
        },
        {
            type = "slider",
            label = YBarL["ybar.settings.option.icon_spacing"] or "Icon Spacing",
            key = "iconSpacing",
            min = 0, max = 20, step = 1,
            default = 4,
            onChange = function(self, value)
                Module.db.iconSpacing = value
                Module:Refresh()
            end
        }
    }
end

YBar:RegisterModule(Module, {
    id = "ybar.talents",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.event", "core.api"},
    defaultEnabled = true,
})

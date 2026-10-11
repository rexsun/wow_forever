local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("MeetingStone") end
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
local API = YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or API
local UnitAPI = YUI.API and YUI.API.Unit or API
local KeystoneAPI = YUI.API and YUI.API.Keystone
local Module = YBar.Module:New("MeetingStone")
local L = YUI.Locale and YUI.Locale:Get("YBar") or {}
local LC = YUI.Locale and YUI.Locale:Get("Core") or {}

-- SharedMedia
local LSM = LibStub("LibSharedMedia-3.0")

-- 常量
local DEFAULT_ICON_SIZE = 14
local DEFAULT_FONT = STANDARD_TEXT_FONT
-- local MODULE_ICON_TEXT = YUI.F:GetAtlasString("DungeonStoneCheckpointDeactivated", DEFAULT_ICON_SIZE + 2)
local MODULE_ICON_TEXT = YUI.F:GetAtlasString("RaidFrame-Icon-SummonPending", DEFAULT_ICON_SIZE + 4)
local MODULE_NAME_CN = "集合石"

local function T(key, fallback, ...)
    local value = L and L[key]
    if not value or value == "" or value == key then value = fallback or key end
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

local function GetModuleName()
    return T("meetingstone.tooltip.title", MODULE_NAME_CN)
end

local function IsMeetingStoneFrameReady(frame)
    return not Module._hasError and frame and not frame.ybarErrorPlaceholder and
        not frame.errorText and frame.text
end

if YUI.IsWrath then
    MODULE_ICON_TEXT = YUI.F:GetAtlasString("Dungeon", DEFAULT_ICON_SIZE + 4)
end

function Module:OnInitialize()
    self.db = GetYBarDB().MeetingStone or {}

    -- 默认设置
    if not self.db.font then self.db.font = DEFAULT_FONT end
    if not self.db.size then self.db.size = DEFAULT_ICON_SIZE end
    if self.db.showIcon == nil then self.db.showIcon = true end

    -- 大秘境钥石功能开关
    if self.db.showKeystone == nil then self.db.showKeystone = true end

    -- Bar Appearance: "BOTH", "TEXT", "ICON", "NONE"
    if not self.db.barAppearance then self.db.barAppearance = "BOTH" end
    
    GetYBarDB().MeetingStone = self.db
    
end

function Module:CreateBarItem(parent)
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 50,
        height = 20,
        clickable = true,
        showIcon = false,
        text = GetModuleName(),
        value = false,
        textColorKey = "color.ybar.text",
        textLeftPadding = 0,
        textRightPadding = 0,
    })
    frame:SetHeight(20)

    -- 文本
    local fontName = self.db.font or DEFAULT_FONT
    local fontPath = YBar:ResolveFontPath(fontName, DEFAULT_FONT, LSM)
    frame.text:SetFont(fontPath, self.db.size or 14, "")
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.text:SetJustifyH("CENTER")
    
    -- 点击事件
    frame.ybarOnClick = function(_, button)
        if button == "LeftButton" then
            if FrameAPI.IsShiftKeyDown() and YUI.IsRetail and KeystoneAPI and Module.db and Module.db.showKeystone and IsInGroup() then
                KeystoneAPI.ReportPartyKeystones()
                return
            end

            if FrameAPI.IsAltKeyDown() then
                if YUI.OpenYBarModuleSettings then
                    YUI:OpenYBarModuleSettings("MeetingStone")
                end
            else
                if not (YBar and YBar.OpenMeetingHorn and YBar:OpenMeetingHorn()) then
                    FrameAPI.TogglePVEFrame()
                end
            end
        elseif button == "RightButton" then
            -- 右键打开原生 PVE 面板 (队伍查找器)
            FrameAPI.TogglePVEFrame()
        end
    end
    
    -- 鼠标悬停
    frame:SetScript("OnEnter", function(self)
        if Module._hasError or self.ybarErrorPlaceholder or self.errorText then return end

        -- 高亮效果
        if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(self) end
        
        -- Tooltip
        local screenHeight = GetScreenHeight()
        local anchorY = self:GetBottom()
        local anchor = "ANCHOR_BOTTOM"
        local yOffset = -5
        
        if anchorY < screenHeight / 2 then
            anchor = "ANCHOR_TOP"
            yOffset = 5
        end
        
        GameTooltip:SetOwner(self, anchor, 0, yOffset)
        
        -- 标题颜色 (金色)
        local r, g, b = 1, 0.82, 0
        GameTooltip:AddLine(GetModuleName(), r, g, b)
        GameTooltip:AddLine(" ")
        
        -- 大秘境钥石 (仅正式服且开启)
        if YUI.IsRetail and KeystoneAPI and Module.db and Module.db.showKeystone then
            local function AddKeystoneLine(row)
                local mapName = row.mapName
                    or (row.mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo(row.mapID))
                    or T("meetingstone.unknown_dungeon", "未知副本")
                local class = select(2, UnitClass(row.unit or row.name))
                local colorHex = "ffffffff"
                if class then
                    local color = UnitAPI.GetClassColor(class)
                    if color then colorHex = color:GenerateHexColor() end
                end
                
                local nameStr = string.format("|c%s%s|r", colorHex, row.name or "")
                local keyStr = string.format("%s (%d)", mapName, row.level or 0)
                GameTooltip:AddDoubleLine(nameStr, keyStr)
            end

            GameTooltip:AddLine(T("meetingstone.tooltip.mythic_keystone", "大秘境钥石"), 0.84, 0.41, 1)

            for _, row in ipairs(KeystoneAPI.GetPartyKeystoneRows()) do
                if row.status == "ready" then
                    AddKeystoneLine(row)
                else
                    local class = select(2, UnitClass(row.unit or row.name))
                    local colorHex = "ffffffff"
                    if class then
                        local color = UnitAPI.GetClassColor(class)
                        if color then colorHex = color:GenerateHexColor() end
                    end
                    local statusText = row.isPlayer and T("meetingstone.tooltip.no_keystone", "暂无钥石") or T("meetingstone.tooltip.loading", "获取中...")
                    GameTooltip:AddDoubleLine(string.format("|c%s%s|r", colorHex, row.name or ""), "|cff808080" .. statusText .. "|r")
                end
            end

            if IsInGroup() then
                KeystoneAPI.RequestPartyKeystones()
            end
            
            GameTooltip:AddLine(" ")
        end
        
        local white = "|cffffffff"
        local gold = "|cffFFD100"
        
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, T("meetingstone.action.open_meeting_stone", "打开集合石")))
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, T("meetingstone.action.open_group_finder", "打开队伍查找器")))
        if YUI.IsRetail and Module.db and Module.db.showKeystone and IsInGroup() then
            GameTooltip:AddLine(format("%sShift + %s: |r%s%s|r", white, LC["common.left_click"], gold, T("meetingstone.action.report_party_keystones", "通报队伍钥石")))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
        
        GameTooltip:Show()
    end)
    
    -- 鼠标离开
    frame:SetScript("OnLeave", function(self)
        if Module._hasError or self.ybarErrorPlaceholder or self.errorText then return end

        -- 恢复颜色
        if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(self) end
        YUI.HideGameTooltip()
    end)

    YBar:CreateActionHost(frame, {
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
    if frame.actionHost then
        frame.actionHost:SetActions({
            left = {
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
            shiftLeft = {
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
        })
    end
    
    self.frame = frame
    self:UpdateBarItem(frame)
    
    return frame
end

function Module:UpdateBarItem(frame)
    if not IsMeetingStoneFrameReady(frame) then return end
    
    local size = self.db.size or DEFAULT_ICON_SIZE
    local font = self.db.font or DEFAULT_FONT
    
    local showIcon = (self.db.barAppearance == "BOTH" or self.db.barAppearance == "ICON")
    local showText = (self.db.barAppearance == "BOTH" or self.db.barAppearance == "TEXT")
    
    if self.db.barAppearance == "NONE" then
        frame:Hide()
        return
    else
        frame:Show()
    end

    -- Update Text Style First
    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")
    
    -- Ensure font is valid
    if not font or font == "" then
        font = DEFAULT_FONT
    else
        -- Try to resolve font name to path via LSM
        font = YBar:ResolveFontPath(font, DEFAULT_FONT, LSM)
    end
    
    frame.text:SetFont(font, size, fontFlag)
    
    if globalDB.fontShadow then
        frame.text:SetShadowColor(0, 0, 0, 1)
        frame.text:SetShadowOffset(1, -1)
    else
        frame.text:SetShadowOffset(0, 0)
    end
    
    -- Construct Display Text & Layout
    local text = GetModuleName()
    local displayText = ""
    
    if showIcon then
        displayText = MODULE_ICON_TEXT
        if showText then
            displayText = displayText .. " " .. text
        end
    else
        -- Text Only
        if showText then
            displayText = text
        end
    end
    
    -- Fallback if text is empty but frame is shown
    if displayText == "" and self.db.barAppearance ~= "NONE" then
        displayText = text
    end
    
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    
    frame.text:SetText(displayText)
    
    -- Update Dimensions
    local textWidth = frame.text:GetStringWidth()
    if textWidth < 10 then textWidth = 30 end -- Minimum width protection
    frame:SetWidth(textWidth + 5)
    frame:SetHeight(size + 4)
end

function Module:GetWidth()
    if self.frame then
        return self.frame:GetWidth()
    end
    return 10
end

function Module:GetOptions()
    local Locale = YUI.Locale
    local YBarL = Locale and Locale:Get("YBar") or {}
    local CoreL = Locale and Locale:Get("Core") or {}

    local function GetDB()
        return self.db
    end
    
    local options = {
        {
            type = "header",
            label = YBarL["ybar.settings.section.dual_bar_display"] or "InfoBar Display"
        },
        {
            type = "dropdown",
            label = YBarL["ybar.settings.option.appearance"] or "Appearance",
            width = 220,
            options = {
                { text = YBarL["ybar.settings.option.icon_text"] or "Icon + Text", value = "BOTH" },
                { text = YBarL["ybar.settings.option.text_only"] or "Text Only", value = "TEXT" },
                { text = YBarL["ybar.settings.option.icon_only"] or "Icon Only", value = "ICON" },
                { text = YBarL["ybar.settings.option.hidden"] or "Hidden", value = "NONE" },
            },
            get = function() return GetDB().barAppearance end,
            set = function(val)
                GetDB().barAppearance = val
                self:UpdateBarItem(self.frame)
            end
        },
        {
            type = "font",
            label = CoreL["common.font"] or "Font",
            width = 220,
            get = function() return GetDB().font end,
            set = function(val)
                GetDB().font = val
                self:UpdateBarItem(self.frame)
            end
        },
        {
            type = "slider",
            label = CoreL["common.font_size"] or "Font Size",
            inline = true,
            inputWidth = 56,
            width = 220,
            min = 8, max = 32, step = 1,
            get = function() return GetDB().size end,
            set = function(val)
                GetDB().size = val
                self:UpdateBarItem(self.frame)
            end
        },
        (YUI.IsRetail and {
            type = "checkbox",
            label = YBarL["meetingstone.settings.display_mythic_key_tooltip"] or "Show Mythic Keystone in tooltip",
            width = 220,
            get = function() return GetDB().showKeystone end,
            set = function(val)
                GetDB().showKeystone = val
                if self.RefreshKeystoneRuntime then
                    self:RefreshKeystoneRuntime()
                end
            end
        } or nil),
    }
    return options
end

function Module:OnKeystoneUpdated()
    if IsMeetingStoneFrameReady(self.frame) and GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self.frame then
        local onEnter = self.frame:GetScript("OnEnter")
        if onEnter then onEnter(self.frame) end
    end
end

function Module:RefreshKeystoneRuntime()
    if not (YUI.IsRetail and KeystoneAPI and YUI.Event and YUI.Event.On) then return end
    if YUI.Event.OffOwner then
        YUI.Event:OffOwner(self)
    end

    if self.db and self.db.showKeystone then
        KeystoneAPI.Activate(self)
        YUI.Event:On("YUI_KEYSTONE_PARTY_UPDATED", "OnKeystoneUpdated", self)
    else
        KeystoneAPI.Deactivate(self)
    end
end

function Module:AttachRuntime()
    if self._hasError then return end

    self:RefreshKeystoneRuntime()
end

function Module:DetachRuntime()
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(self)
    end
    if KeystoneAPI then
        KeystoneAPI.Deactivate(self)
    end
    if GameTooltip and GameTooltip.GetOwner and self.frame and GameTooltip:GetOwner() == self.frame then
        YUI.HideGameTooltip()
    end
    if self.frame then
        self.frame:Hide()
    end
end

YBar:RegisterModule(Module, {
    id = "ybar.meetingstone",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api"},
    defaultEnabled = true,
})

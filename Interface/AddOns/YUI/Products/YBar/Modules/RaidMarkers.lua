local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("RaidMarkers") end
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
local API = YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or API
local SecurityAPI = YUI.API and YUI.API.Security or API
local SystemAPI = YUI.API and YUI.API.System or API
local Module = YBar.Module:New("RaidMarkers")
local ResetInstances = ResetInstances
local StaticPopup_Show = StaticPopup_Show
local StaticPopupDialogs = StaticPopupDialogs
local RESET_INSTANCES_CONFIRMATION = RESET_INSTANCES_CONFIRMATION
local YES = YES
local NO = NO

-- SharedMedia
local LSM = LibStub("LibSharedMedia-3.0")

local function T(key, fallback, ...)
    local value = L[key] or fallback or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(format, value, ...)
        return ok and formatted or value
    end
    return value
end

-- Texture Definitions
local TEXTURES = {
    CLEAR       = "",       -- Fallback: Interface\Buttons\UI-GroupLoot-Pass-Up
    READYCHECK  = "readycheck-ready",       -- Fallback: Interface\RaidFrame\ReadyCheck-Ready
    -- COUNTDOWN   = "icon-clock",             -- Fallback: Interface\Icons\Spell_Holy_BorrowedTime
    -- COUNTDOWN   = "minimap-genericevent-hornicon-small",             -- Fallback: Interface\Icons\Spell_Holy_BorrowedTime
    COUNTDOWN   = "minimap-genericevent-hornicon-small",             -- Fallback: Interface\Icons\Spell_Holy_BorrowedTime
    LOG_OFF     = "Perks-PreviewOff-Hover",       -- Fallback: Interface\Buttons\UI-SpellbookIcon-PrevPage-Up
    LOG_ON      = "Perks-PreviewOn",       -- Fallback: Interface\Buttons\UI-S
    RESET       = "BattleBar-SwapPetIcon",   -- Fallback: Interface\Icons\Spell_Holy_Resurrection
    HANDLE      = "Interface\\Buttons\\UI-Listbox-Highlight2",
}

if YUI.IsWrath then
    TEXTURES.COUNTDOWN = "auctionhouse-icon-clock"
end

-- 常量
local DEFAULT_ICON_SIZE = 14
local DEFAULT_FONT = STANDARD_TEXT_FONT
local MODULE_ICON_TEXT = YUI.F:GetAtlasString("CrossedFlags", DEFAULT_ICON_SIZE + 2)

local function GetBarItemName()
    return T("ybar.settings.section.marker_bar", "Marker Bar")
end

local function IsBarItemFrameReady(frame)
    return not Module._hasError and frame and not frame.ybarErrorPlaceholder and
        not frame.errorText and frame.text
end

-- World Marker Mapping (Target Marker ID -> World Marker ID)
-- 1: Star (Yellow) -> 5 (Star)
-- 2: Circle (Orange) -> 6 (Circle)
-- 3: Diamond (Purple) -> 3 (Diamond)
-- 4: Triangle (Green) -> 2 (Triangle)
-- 5: Moon (Silver) -> 7 (Moon)
-- 6: Square (Blue) -> 1 (Square)
-- 7: Cross (Red) -> 4 (Cross)
-- 8: Skull (White) -> 8 (Skull)
local TargetToWorld = {
    [1] = 5, [2] = 6, [3] = 3, [4] = 2,
    [5] = 7, [6] = 1, [7] = 4, [8] = 8
}

function Module:OnInitialize()
    self.db = GetYBarDB().RaidMarkers or {}

    -- 默认设置
    if self.db.enable == nil then self.db.enable = true end
    if not self.db.font then self.db.font = DEFAULT_FONT end
    if not self.db.size then self.db.size = 14 end -- Bar item text size
    if not self.db.iconSize then self.db.iconSize = 20 end -- Marker button size
    if not self.db.spacing then self.db.spacing = 5 end
    -- Display Mode: "MANUAL", "AUTO", "MOUSEOVER"
    if not self.db.displayMode then self.db.displayMode = "AUTO" end
    if self.db.showTooltip == nil then self.db.showTooltip = true end
    if self.db.lockPosition == nil then self.db.lockPosition = false end
    if self.db.isVisible == nil then self.db.isVisible = false end

    -- Bar Appearance: "BOTH", "TEXT", "ICON", "NONE"
    if not self.db.barAppearance then self.db.barAppearance = "BOTH" end

    -- Button Toggles
    if self.db.showMarkers == nil then self.db.showMarkers = true end
    if self.db.showReadyCheck == nil then self.db.showReadyCheck = true end
    if self.db.showCountdown == nil then self.db.showCountdown = true end
    if self.db.showCombatLog == nil then self.db.showCombatLog = true end
    if self.db.showReset == nil then self.db.showReset = true end
    if self.db.countdownTime == nil then self.db.countdownTime = 7 end
    if self.db.showRoleCount == nil then self.db.showRoleCount = false end

    GetYBarDB().RaidMarkers = self.db

    self.eventFrame = true
end

function Module:RegisterRuntimeEvents()
    YUI.Event:OffOwner(self)
    YUI.Event:On("GROUP_ROSTER_UPDATE", "OnRuntimeEvent", self, {
        moduleId = "product:YBar:RaidMarkers",
        traceName = "YBar:RaidMarkers:GROUP_ROSTER_UPDATE",
        throttle = 0.1,
    })
    YUI.Event:On("YUI_WORLD_READY", "OnRuntimeEvent", self)
end

function Module:QueuePostCombatUpdate(updateBarItem, updateYBarLayout, updateMarkerLayout)
    self._pendingBarItemUpdate = self._pendingBarItemUpdate or updateBarItem
    self._pendingYBarLayoutUpdate = self._pendingYBarLayoutUpdate or updateYBarLayout
    self._pendingMarkerLayoutUpdate = self._pendingMarkerLayoutUpdate or updateMarkerLayout

    if self._postCombatUpdateHandle then return end

    self._postCombatUpdateHandle = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
        self._postCombatUpdateHandle = nil
        local pendingBarItem = self._pendingBarItemUpdate
        local pendingYBarLayout = self._pendingYBarLayoutUpdate
        local pendingMarkerLayout = self._pendingMarkerLayoutUpdate
        self._pendingBarItemUpdate = false
        self._pendingYBarLayoutUpdate = false
        self._pendingMarkerLayoutUpdate = false

        if not self._runtimeAttached then return end
        if pendingMarkerLayout then
            self:UpdateLayout()
        end
        if pendingBarItem then
            self:UpdateBarItem(self.frame, pendingYBarLayout)
        elseif pendingYBarLayout then
            YBar:UpdateLayout()
        end
    end)
end

function Module:OnRuntimeEvent(event)
    if event == "PLAYER_REGEN_ENABLED" and self._pendingDetach then
        self._pendingDetach = false
        self:DetachRuntime()
        return
    end

    if not self._runtimeAttached then
        return
    end

    if self.frame and self.db.showRoleCount then
        self:UpdateBarItem(self.frame, true)
    end
end

function Module:RegisterButtonEvents()
    if not self.buttons then
        return
    end

    local btnCD = self.buttons[11]
    if btnCD then
        YUI.Event:OffOwner(btnCD)
        YUI.Event:On("PLAYER_REGEN_ENABLED", "UpdateCDMacro", btnCD)
        YUI.Event:On("ADDON_LOADED", "UpdateCDMacro", btnCD)
    end

    local btnLog = self.buttons[12]
    if btnLog then
        YUI.Event:OffOwner(btnLog)
        YUI.Event:On("YUI_WORLD_READY", "UpdateLogIcon", btnLog)
    end
end

function Module:UnregisterButtonEvents()
    if not self.buttons then
        return
    end

    for _, btn in ipairs(self.buttons) do
        YUI.Event:OffOwner(btn)
    end
end

function Module:AttachRuntime()
    if self._hasError then return end

    self._runtimeAttached = true
    self._pendingDetach = false

    self:RegisterRuntimeEvents()

    self:RegisterButtonEvents()

    if self.frame then
        self.frame:Show()
    end
    self:Update()
end

function Module:DetachRuntime()
    self._runtimeAttached = false

    if SecurityAPI.InCombatLockdown() then
        self._pendingDetach = true
        YUI.Event:OffOwner(self)
        YUI.Event:On("PLAYER_REGEN_ENABLED", "OnRuntimeEvent", self)
        return
    end

    self._pendingDetach = false

    YUI.Event:OffOwner(self)

    self:UnregisterButtonEvents()

    if self.bar then
        UnregisterStateDriver(self.bar, "visibility")
        if self.visibilityHandle then
            YUI.Event:Off(self.visibilityHandle)
            self.visibilityHandle = nil
        end
        self.bar:Hide()
    end

    if self.handle then
        self.handle:Hide()
    end

    if GameTooltip then
        YUI.HideGameTooltip()
    end

    if self.frame then
        self.frame:Hide()
    end
end

function Module:Update()
    if self._hasError then return end
    if not self.db then return end

    local isOnBar = YBar:IsModuleOnBar(self.name)

    -- 如果 YBar 被禁用，则强制视为不在 Bar 上
    local ybarEnabled = true
    if GetYBarDB() and GetYBarDB().enable == false then
        ybarEnabled = false
    end

    if not ybarEnabled then
        isOnBar = false
    end

    if isOnBar then
        if not self.bar then
            self:CreateMarkerBar()
        end
        self:UpdateVisibility()
    else
        if self.bar then
            UnregisterStateDriver(self.bar, "visibility")
            self.bar:Hide()
        end
    end
end

function Module:UpdateVisibility()
    if self._hasError then return end
    if not self.bar then return end

    -- Ensure module is active on YBar
    if not YBar:IsSubModuleEnabled(self.name) then
        UnregisterStateDriver(self.bar, "visibility")
        self.bar:Hide()
        return
    end

    if SecurityAPI.InCombatLockdown() then
        if not self.visibilityHandle then
            self.visibilityHandle = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
                self.visibilityHandle = nil
                Module:UpdateVisibility()
            end)
        end
        return
    end

    local driver = "hide"
    if self.db.displayMode == "AUTO" then
        if self.tempState == "show" then
            driver = "show"
        elseif self.tempState == "hide" then
            driver = "hide"
        else
            driver = "[group] show; hide"
        end
    elseif self.db.displayMode == "MANUAL" then
        if self.db.isVisible then
            driver = "show"
        else
            driver = "hide"
        end
    elseif self.db.displayMode == "MOUSEOVER" then
        driver = "show"
    end

    RegisterStateDriver(self.bar, "visibility", driver)

    -- Handle Alpha for MouseOver
    if self.db.displayMode == "MOUSEOVER" then
        self.bar:SetAlpha(0)
    else
        self.bar:SetAlpha(1)
    end
end

-- Deprecated: Handled by RegisterStateDriver
function Module:CheckAutoShow()
    self:UpdateVisibility()
end

function Module:CreateBarItem(parent)
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        clickable = true,
        showIcon = false,
        text = GetBarItemName(),
        value = false,
        textColorKey = "color.ybar.text",
        textLeftPadding = 0,
        textRightPadding = 0,
    })

    -- 文本
    -- 确保初始字体设置，避免 SetText 报错
    local font = self.db.font or DEFAULT_FONT
    local fontPath = YBar:ResolveFontPath(font, DEFAULT_FONT, LSM)
    local size = self.db.size or 14
    local globalDB = GetYBarDB() or {}
    local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")

    frame.text:SetFont(fontPath, size, fontFlag)
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)
    frame.text:ClearAllPoints()
    frame.text:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetText(GetBarItemName())

    -- 鼠标悬停
    frame:SetScript("OnEnter", function(self)
        if Module._hasError or self.ybarErrorPlaceholder or self.errorText then return end

        if YBar and YBar.OnModuleEnter then YBar:OnModuleEnter(self) end
        if not Module.db.showTooltip then return end

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
        GameTooltip:AddLine(T("raidmarkers.tooltip.title", "团队标记"), r, g, b)
        GameTooltip:AddLine(" ")

        local white = "|cffffffff"
        local gold = "|cffFFD100"

        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, T("raidmarkers.action.click", "点击"), gold, T("raidmarkers.tooltip.toggle_marker_bar", "显示/隐藏标记条")))

        local modeNames = {
            MANUAL = L["ybar.settings.option.manual"] or "手动切换",
            AUTO = L["ybar.settings.option.group_auto"] or "组队自动显示",
            MOUSEOVER = L["ybar.settings.option.mouseover"] or "鼠标滑过显示"
        }
        local currentModeName = modeNames[Module.db.displayMode] or "Unknown"
        GameTooltip:AddLine(T("raidmarkers.tooltip.display_mode", "显示模式: %s", gold .. currentModeName .. "|r"), 1, 1, 1)

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]), 0.6, 0.6, 0.6)

        GameTooltip:Show()
    end)

    -- 鼠标离开
    frame:SetScript("OnLeave", function(self)
        if Module._hasError or self.ybarErrorPlaceholder or self.errorText then return end

        -- 恢复颜色
        if YBar and YBar.OnModuleLeave then YBar:OnModuleLeave(self) end
        YUI.HideGameTooltip()
    end)

    -- 点击由 ActionHost 覆盖，保留 frame 的 hover 脚本作为视觉/tooltip 逻辑。
    local actionHost = YBar:CreateActionHost(frame, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if actionHost then
        actionHost:SetActions({
            left = {
                kind = "custom",
                onClick = function()
                    self:ToggleMarkerBar()
                end,
            },
            altLeft = {
                kind = "custom",
                onClick = function()
                    YUI:OpenYBarModuleSettings("RaidMarkers")
                end,
            },
            altRight = {
                kind = "custom",
                onClick = function()
                    YUI:OpenYBarModuleSettings("RaidMarkers")
                end,
            },
        })
    end

    self.frame = frame
    self:UpdateBarItem(frame)

    -- Create the Marker Bar here or lazily
    -- Handled by Update()
    -- self:CreateMarkerBar()

    return frame
end

function Module:GetRoleCountString()
    if not self.db.showRoleCount or not IsInRaid() then return "" end

    local tank, healer, dps = 0, 0, 0

    -- 在团队中，GetGroupMemberCounts 是准确的（不包含AI追随者）
    local counts = GetGroupMemberCounts()
    if counts then
        tank = counts.TANK or 0
        healer = counts.HEALER or 0
        dps = (counts.DAMAGER or 0) + (counts.NOROLE or 0)
    end

    local size = self.db.size or 14
    local iconSize = size - 4

    local tankStr = CreateAtlasMarkup("UI-LFG-RoleIcon-Tank-Micro-Raid", iconSize, iconSize, 0, 0) .. " " .. tank .. "  "
    local healerStr = CreateAtlasMarkup("UI-LFG-RoleIcon-Healer-Micro-Raid", iconSize, iconSize, 0, 0) .. " " .. healer .. "  "
    local dpsStr = CreateAtlasMarkup("UI-LFG-RoleIcon-DPS-Micro-Raid", iconSize, iconSize, 0, 0) .. " " .. dps

    -- Trim trailing spaces
    return string.trim(tankStr .. healerStr .. dpsStr)
end

function Module:UpdateBarItem(frame, updateLayout)
    if not IsBarItemFrameReady(frame) then return false end

    -- YBar RenderRow passes the parent bar frame as arg2; only literal true requests a layout refresh.
    local shouldUpdateYBarLayout = updateLayout == true

    if SecurityAPI.InCombatLockdown() then
        self:QueuePostCombatUpdate(true, shouldUpdateYBarLayout)
        return false
    end

    local size = self.db.size or DEFAULT_ICON_SIZE
    local font = self.db.font or DEFAULT_FONT

    local showIcon = (self.db.barAppearance == "BOTH" or self.db.barAppearance == "ICON")
    local showText = (self.db.barAppearance == "BOTH" or self.db.barAppearance == "TEXT")


    if self.db.barAppearance == "NONE" then
        frame:Hide()
        if shouldUpdateYBarLayout then
            YBar:UpdateLayout()
        end
        return true
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
    local text = GetBarItemName()
    local displayText = ""
    local roleCountStr = self:GetRoleCountString()

    if roleCountStr ~= "" then
        displayText = roleCountStr
    else
        if showIcon then
            displayText = MODULE_ICON_TEXT or ""
            if showText then
                displayText = displayText .. " " .. text
            end
        else
            -- Text Only
            if showText then
                displayText = text
            end
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

    -- Update Frame Size
    local textWidth = frame.text:GetStringWidth()
    if textWidth < 10 then textWidth = 30 end -- Minimum width protection
    frame:SetWidth(textWidth + 10)
    frame:SetHeight(size + 4)
    if shouldUpdateYBarLayout then
        YBar:UpdateLayout()
    end
    return true
end

function Module:ShowHandle()
    if self.db.lockPosition then return end
    if not self.bar or not self.handle then return end

    -- Cancel pending hide
    if self.hideHandleTimer then
        self.hideHandleTimer:Cancel()
        self.hideHandleTimer = nil
    end

    local x, y = self.bar:GetCenter()
    if not x then return end

    local screenWidth = GetScreenWidth()
    self.handle:ClearAllPoints()
    self.handle:SetPoint("TOP", self.bar, "TOP")
    self.handle:SetPoint("BOTTOM", self.bar, "BOTTOM")

    if x < screenWidth / 2 then
        -- Left side, handle on Right
        self.handle:SetPoint("LEFT", self.bar, "RIGHT", 0, 0)
    else
        -- Right side, handle on Left
        self.handle:SetPoint("RIGHT", self.bar, "LEFT", 0, 0)
    end

    self.handle:Show()
end

function Module:HideHandle()
    if not self.handle then return end

    -- 延迟检测，防止快速移动时消失
    -- 如果正在拖拽，不隐藏
    if self.isDragging then return end

    if self.hideHandleTimer then
        self.hideHandleTimer:Cancel()
    end

    self.hideHandleTimer = C_Timer.NewTimer(0.2, function() -- 增加延迟到 0.2
        if self.isDragging then return end -- 再次检测
        if self.handle:IsMouseOver() or self.bar:IsMouseOver() then return end
        self.handle:Hide()
    end)
end

function Module:CreateMarkerBar()
    if self.bar then return end

    -- Create Secure Handler State Frame
    -- SecureHandlerStateTemplate must stay on native CreateFrame.
    local bar = CreateFrame("Frame", "YUI_RaidMarkersBar", UIParent, "SecureHandlerStateTemplate")
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:SetSize(200, 30) -- Initial size
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    bar:Hide()

    -- Drag Handle
    local handle = GUI2:CreateFrame(bar)
    handle:SetWidth(15)
    handle:SetPoint("TOP", bar, "TOP")
    handle:SetPoint("BOTTOM", bar, "BOTTOM")
    handle:SetPoint("RIGHT", bar, "LEFT", 0, 0)

    local handleTex = YBar:CreateThemedTexture(handle, {
        layer = "OVERLAY",
        texture = TEXTURES.HANDLE,
        colorKey = "color.ybar.raidmarkers.handle",
        fallback = { 0.6, 0.6, 0.6, 0.8 },
        colorMode = "vertex",
    })
    handleTex:SetAllPoints()

    handle:SetScript("OnEnter", function()
        if not self.db.lockPosition then
            GameTooltip:SetOwner(handle, "ANCHOR_TOP")
            GameTooltip:AddLine(T("raidmarkers.tooltip.drag_hint", "按住拖动"))
            GameTooltip:Show()
        end
        self:ShowHandle()
    end)
    handle:SetScript("OnLeave", function()
        YUI.HideGameTooltip()
        self:HideHandle()
    end)

    -- Frame type does not have RegisterForClicks, it's for Button.
    -- RegisterForDrag is sufficient for dragging.
    handle:RegisterForDrag("LeftButton")

    handle:SetScript("OnDragStart", function()
        if not self.db.lockPosition then
            self.isDragging = true
            bar:StartMoving()
        end
    end)

    handle:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        self.isDragging = false

        -- Save position manually to DB because SetUserPlaced only works for layout-cache.txt
        local point, relativeTo, relativePoint, xOfs, yOfs = bar:GetPoint()
        self.db.position = { point, relativePoint, xOfs, yOfs }

        if not handle:IsMouseOver() and not bar:IsMouseOver() then
            self:HideHandle()
        end
    end)

    -- Restore Position
    if self.db.position then
        bar:ClearAllPoints()
        local point, relativePoint, xOfs, yOfs = unpack(self.db.position)
        bar:SetPoint(point, UIParent, relativePoint, xOfs, yOfs)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    handle:Hide()
    self.bar = bar
    self.handle = handle

    self:CreateButtons()

    -- Initial State handled by UpdateVisibility
    -- Remove manual show/hide logic here

    self:UpdateLayout()
    self:UpdateMouseOver()

end

function Module:AddHoverEffect(btn, tooltipTitle, tooltipText)
    btn:SetScript("OnEnter", function(self)
        if self.icon then
            self.icon:SetScale(1.2)
        end
        -- MouseOver logic
        if Module.db.displayMode == "MOUSEOVER" and Module.bar then
            Module.bar:SetAlpha(1)
        end
        -- Drag handle
        if Module.ShowHandle then
             Module:ShowHandle()
        end

        -- Tooltip
        if Module.db.showTooltip and tooltipText then
            local anchor = "ANCHOR_BOTTOM"
            local screenHeight = GetScreenHeight()
            local y = self:GetBottom()
            if y < screenHeight / 2 then
                anchor = "ANCHOR_TOP"
            end

            GameTooltip:SetOwner(self, anchor)
            GameTooltip:ClearLines()

            if tooltipTitle then
                GameTooltip:AddLine(tooltipTitle, 1, 0.82, 0) -- Gold title
                GameTooltip:AddLine(" ")
            end

            local white = "|cffffffff"
            local gold = "|cffFFD100"

            -- Simple parsing for our custom format: "Label: Desc" -> Gold Label, White Desc
            for line in string.gmatch(tooltipText, "[^\r\n]+") do
                local label, desc = string.match(line, "^(.-):%s*(.+)$")
                if label and desc then
                    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, label, gold, desc))
                else
                    GameTooltip:AddLine(line, 1, 1, 1)
                end
            end

            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.icon then
            self.icon:SetScale(1.0)
        end
        -- MouseOver logic
        if Module.db.displayMode == "MOUSEOVER" and Module.bar then
             C_Timer.After(0.1, function()
                if not Module._runtimeAttached or not Module.bar then
                    return
                end
                if not Module.bar:IsMouseOver() then
                    Module.bar:SetAlpha(0)
                end
            end)
        end
        -- Drag handle
        if Module.HideHandle then
             Module:HideHandle()
        end

        YUI.HideGameTooltip()
    end)
end

local function AttachMarkerActionHost(btn, actions)
    local host = YBar:CreateActionHost(btn, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if host then
        host:SetActions(actions)
    end
    return host
end

local function SetButtonIcon(btn, texture, atlas)
    if btn.iconSlot then
        YBar:SetIconSlotTexture(btn.iconSlot, texture, atlas)
    elseif btn.icon then
        if atlas then
            btn.icon:SetTexture(nil)
            btn.icon:SetAtlas(atlas)
        else
            btn.icon:SetTexture(texture)
        end
    end
end

local function CreateButtonIcon(btn, size, texture, atlas)
    btn.iconSlot, btn.icon = YBar:CreateIconSlot(btn, {
        size = size,
        icon = texture,
        variant = "bare",
        shape = "square",
        padding = 0,
    })
    local iconFrame = btn.iconSlot or btn.icon
    iconFrame:SetPoint("CENTER")
    iconFrame:SetSize(size, size)
    SetButtonIcon(btn, texture, atlas)
end

function Module:CreateButtons()
    self.buttons = {}
    local size = self.db.iconSize

    -- 1-8 Markers
    for i = 1, 8 do
        local btn = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtn" .. i })
        btn:SetSize(size, size)

        -- Texture
        CreateButtonIcon(btn, size, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"..i)

        local actions
        if YUI.IsRetail then
            local wmID = TargetToWorld[i]
            actions = {
                left = { kind = "raidtarget", marker = i, action = "set" },
                right = { kind = "raidtarget", marker = i, action = "clear" },
            }
            if wmID then
                actions.shiftLeft = { kind = "worldmarker", marker = wmID, action = "set" }
                actions.shiftRight = { kind = "worldmarker", marker = wmID, action = "clear" }
            end
        elseif YUI.IsForever then
            actions = {
                left = { kind = "raidtarget", marker = i, action = "set" },
                right = { kind = "raidtarget", marker = i, action = "clear" },
                shiftLeft = { kind = "noop" },
                shiftRight = { kind = "noop" },
            }
        else
            actions = {
                left = {
                    kind = "custom",
                    onClick = function()
                        SetRaidTarget("target", i)
                    end,
                },
                right = {
                    kind = "custom",
                    onClick = function()
                        SetRaidTarget("target", 0)
                    end,
                },
                shiftLeft = { kind = "noop" },
                shiftRight = { kind = "noop" },
            }
        end

        AttachMarkerActionHost(btn, actions)

        local tooltip = format("%s: %s\n%s: %s", LC["common.left_click"], T("raidmarkers.action.mark_target", "标记目标"), LC["common.right_click"], T("raidmarkers.action.clear_marker", "清除标记"))
        if YUI.IsRetail then
            tooltip = tooltip .. format("\nShift + %s: %s\nShift + %s: %s", LC["common.left_click"], T("raidmarkers.action.place_world_marker", "放置光柱"), LC["common.right_click"], T("raidmarkers.action.clear_world_marker", "清除光柱"))
        end
        local iconStr = YUI.F:GetTextureString("Interface\\TargetingFrame\\UI-RaidTargetingIcon_"..i, 16)
        self:AddHoverEffect(btn, T("raidmarkers.tooltip.target_marker", "团队标记 %s", iconStr), tooltip)
        tinsert(self.buttons, btn)
    end

    -- 9: Clear
    local btnClear = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnClear" })
    btnClear:SetSize(size, size)
    if C_Texture.GetAtlasInfo(TEXTURES.CLEAR) then
        CreateButtonIcon(btnClear, size, nil, TEXTURES.CLEAR)
    else
        CreateButtonIcon(btnClear, size, "Interface\\BUTTONS\\UI-GroupLoot-Pass-Up")
    end

    local clearActions
    if YUI.IsRetail then
        clearActions = {
            left = { kind = "raidtarget", action = "clear" },
            shiftLeft = {
                kind = "secure",
                rawAttributes = {
                    ["shift-type*"] = "worldmarker",
                    ["shift-action*"] = "clear",
                },
            },
            shiftRight = {
                kind = "secure",
                rawAttributes = {
                    ["shift-type*"] = "worldmarker",
                    ["shift-action*"] = "clear",
                },
            },
        }
    elseif YUI.IsForever then
        clearActions = {
            left = { kind = "raidtarget", action = "clear" },
            shiftLeft = { kind = "noop" },
            shiftRight = { kind = "noop" },
        }
    else
        clearActions = {
            left = {
                kind = "custom",
                onClick = function()
                    SetRaidTarget("target", 0)
                end,
            },
            shiftLeft = { kind = "noop" },
            shiftRight = { kind = "noop" },
        }
    end

    AttachMarkerActionHost(btnClear, clearActions)

    local clearTooltip = format("%s: %s", LC["common.left_click"], T("raidmarkers.tooltip.clear_target_marker", "清除目标标记"))
    if YUI.IsRetail then
        clearTooltip = clearTooltip .. format("\nShift + %s: %s", LC["common.left_click"], T("raidmarkers.action.clear_all_world_markers", "清除所有光柱"))
    end
    self:AddHoverEffect(btnClear, T("raidmarkers.tooltip.clear_target_marker", "清除目标标记"), clearTooltip)
    tinsert(self.buttons, btnClear)

    -- 10: Ready Check
    local btnRC = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnRC" })
    btnRC:SetSize(size, size)
    if C_Texture.GetAtlasInfo(TEXTURES.READYCHECK) then
        CreateButtonIcon(btnRC, size, nil, TEXTURES.READYCHECK)
    else
        CreateButtonIcon(btnRC, size, "Interface\\RaidFrame\\ReadyCheck-Ready")
    end

    AttachMarkerActionHost(btnRC, {
        left = { kind = "macro", macrotext = "/readycheck" },
    })

    self:AddHoverEffect(btnRC, T("raidmarkers.tooltip.ready_check", "就位确认"), format("%s: %s", LC["common.left_click"], T("raidmarkers.action.ready_check", "发起就位确认")))
    tinsert(self.buttons, btnRC)

    -- 11: Countdown
    local btnCD = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnCD" })
    btnCD:SetSize(size, size)
    if C_Texture.GetAtlasInfo(TEXTURES.COUNTDOWN) then
        CreateButtonIcon(btnCD, size, nil, TEXTURES.COUNTDOWN)
    else
        CreateButtonIcon(btnCD, size, "Interface\\Icons\\Spell_Holy_BorrowedTime")
    end

    AttachMarkerActionHost(btnCD, {})

    local function UpdateCDMacro()
        if SecurityAPI.InCombatLockdown() then return end
        local time = self.db.countdownTime or 7
        local macroText = "/countdown " .. time
        local cancelText = "/countdown 0"
        if SystemAPI.IsAddOnLoaded("BigWigs") or SystemAPI.IsAddOnLoaded("DBM-Core") then
            macroText = "/pull " .. time
            cancelText = "/pull 0"
        end
        if btnCD.actionHost then
            btnCD.actionHost:SetActions({
                left = { kind = "macro", macrotext = macroText },
                right = { kind = "macro", macrotext = cancelText },
            })
        end
    end
    self.UpdateCDMacro = UpdateCDMacro -- Expose for settings update
    btnCD.UpdateCDMacro = UpdateCDMacro
    UpdateCDMacro()
    if self._runtimeAttached then
        YUI.Event:OffOwner(btnCD)
        YUI.Event:On("PLAYER_REGEN_ENABLED", "UpdateCDMacro", btnCD)
        YUI.Event:On("ADDON_LOADED", "UpdateCDMacro", btnCD)
    end

    local function UpdateTooltip()
        local time = self.db.countdownTime or 7
        self:AddHoverEffect(btnCD, T("raidmarkers.tooltip.countdown", "倒数"), format("%s: %s\n%s: %s", LC["common.left_click"], T("raidmarkers.action.start_countdown", "开始 %ds 倒数", time), LC["common.right_click"], T("raidmarkers.action.cancel_countdown", "取消倒数")))
    end
    self.UpdateCDTooltip = UpdateTooltip
    UpdateTooltip()
    tinsert(self.buttons, btnCD)

    -- 12: Combat Log
    local btnLog = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnLog" })
    btnLog:SetSize(size, size)
    if C_Texture.GetAtlasInfo(TEXTURES.LOG_OFF) then
        CreateButtonIcon(btnLog, size, nil, TEXTURES.LOG_OFF)
    else
        CreateButtonIcon(btnLog, size, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    end

    local function UpdateLogIcon()
        local state = LoggingCombat()
        if state then
            if C_Texture.GetAtlasInfo(TEXTURES.LOG_ON) then
                SetButtonIcon(btnLog, nil, TEXTURES.LOG_ON)
            else
                SetButtonIcon(btnLog, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            end
        else
             if C_Texture.GetAtlasInfo(TEXTURES.LOG_OFF) then
                SetButtonIcon(btnLog, nil, TEXTURES.LOG_OFF)
            else
                SetButtonIcon(btnLog, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
            end
        end
    end
    btnLog.UpdateLogIcon = UpdateLogIcon
    AttachMarkerActionHost(btnLog, {
        left = {
            kind = "macro",
            macrotext = "/combatlog",
            afterClick = function()
                C_Timer.After(0.2, function()
                    if self._runtimeAttached then
                        UpdateLogIcon()
                    end
                end)
            end,
        },
    })
    if self._runtimeAttached then
        YUI.Event:OffOwner(btnLog)
        YUI.Event:On("YUI_WORLD_READY", "UpdateLogIcon", btnLog)
    end

    self:AddHoverEffect(btnLog, T("raidmarkers.tooltip.advanced_combat_log", "高级战斗日志"), format("%s: %s", LC["common.left_click"], T("raidmarkers.action.toggle_combat_log", "切换 开启/关闭")))
    tinsert(self.buttons, btnLog)

    -- 13: Reset Instances (Standard Button)
    local btnReset = GUI2:CreateButtonFrame(self.bar, { name = "YUI_RaidMarkerBtnReset" })
    btnReset:SetSize(size, size)
    if C_Texture.GetAtlasInfo(TEXTURES.RESET) then
        CreateButtonIcon(btnReset, size, nil, TEXTURES.RESET)
    else
        CreateButtonIcon(btnReset, size, "Interface\\Icons\\Spell_Holy_Resurrection")
    end

    AttachMarkerActionHost(btnReset, {
        left = {
            kind = "custom",
            onClick = function()
                if StaticPopupDialogs["CONFIRM_RESET_INSTANCES"] then
                    StaticPopup_Show("CONFIRM_RESET_INSTANCES")
                else
                    local Settings = YUI.Settings
                    if Settings and Settings.ShowConfirmPopup then
                        Settings:ShowConfirmPopup(
                            _G.RESET_INSTANCES_CONFIRMATION or "Do you really want to reset all instances?",
                            ResetInstances,
                            {
                                titleText = T("raidmarkers.tooltip.reset_instances", "重置副本"),
                                acceptTone = "danger",
                            }
                        )
                    end
                end
            end,
        },
    })

    self:AddHoverEffect(btnReset, T("raidmarkers.tooltip.reset_instances", "重置副本"), format("%s: %s", T("raidmarkers.action.click", "点击"), T("raidmarkers.action.confirm_reset_instances", "弹出确认框")))
    tinsert(self.buttons, btnReset)
end

function Module:UpdateLayout()
    if not self.buttons or not self.bar then return end
    if SecurityAPI.InCombatLockdown() then
        self:QueuePostCombatUpdate(false, false, true)
        return
    end

    local spacing = self.db.spacing
    local size = self.db.iconSize

    local visibleButtons = {}

    -- Filter visible buttons based on settings
    -- 1-8 Markers + 9 Clear
    if self.db.showMarkers then
        for i = 1, 9 do
            tinsert(visibleButtons, self.buttons[i])
        end
    end

    -- 10 ReadyCheck
    if self.db.showReadyCheck then
        tinsert(visibleButtons, self.buttons[10])
    end

    -- 11 Countdown
    if self.db.showCountdown then
        tinsert(visibleButtons, self.buttons[11])
    end

    -- 12 CombatLog
    if self.db.showCombatLog then
        tinsert(visibleButtons, self.buttons[12])
    end

    -- 13 Reset
    if self.db.showReset then
        tinsert(visibleButtons, self.buttons[13])
    end

    -- Hide all first
    for _, btn in ipairs(self.buttons) do
        btn:Hide()
        btn:ClearAllPoints()
    end

    local numButtons = #visibleButtons
    if numButtons == 0 then
        self.bar:SetSize(10, size + 10)
        return
    end

    local width = (size * numButtons) + (spacing * (numButtons - 1)) + 10
    self.bar:SetSize(width, size + 10)

    for i, btn in ipairs(visibleButtons) do
        btn:Show()
        btn:SetSize(size, size)
        if i == 1 then
            btn:SetPoint("LEFT", self.bar, "LEFT", 5, 0)
        else
            btn:SetPoint("LEFT", visibleButtons[i-1], "RIGHT", spacing, 0)
        end

        -- Update texture size if needed (for scaling)
        if btn.icon then
            btn.icon:SetSize(size, size)
        end
    end
end

function Module:ToggleMarkerBar()
    if not self.bar then return end

    if SecurityAPI.InCombatLockdown() then
        YUI:Print("|cffff0000战斗中无法切换标记条|r")
        return
    end

    -- If display mode is MOUSEOVER, manual toggle is disabled to avoid conflict
    -- If AUTO, toggle switches to MANUAL mode to allow hiding/showing
    if self.db.displayMode == "MOUSEOVER" then
        return
    end

    if self.db.displayMode == "AUTO" then
        -- 自动模式下，切换为临时状态，不修改配置
        local isShown = self.bar:IsShown()
        local shouldShowAuto = IsInGroup()

        if isShown then
            -- 当前显示，用户想隐藏
            if not shouldShowAuto then
                -- 自动本来就是隐藏的（说明当前是强制显示），所以恢复自动即可
                self.tempState = nil
                YUI:Debug("恢复自动模式（隐藏）")
            else
                -- 自动本来是显示的，用户想强制隐藏
                self.tempState = "hide"
                YUI:Debug("已临时隐藏标记条")
            end
        else
            -- 当前隐藏，用户想显示
            if shouldShowAuto then
                -- 自动本来就是显示的（说明当前是强制隐藏），所以恢复自动即可
                self.tempState = nil
                YUI:Debug("恢复自动模式（显示）")
            else
                -- 自动本来是隐藏的，用户想强制显示
                self.tempState = "show"
                YUI:Debug("已临时显示标记条")
            end
        end
    else
        -- MANUAL mode
        self.db.isVisible = not self.db.isVisible
    end

    self:UpdateVisibility()
    self:UpdateLayout()
end

function Module:OnClick()
    self:ToggleMarkerBar()
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
        { type = "divider", width = 400, label = YBarL["ybar.settings.section.info_bar"] or "Info Bar", alignLeft = true },
        {
            type = "row",
            children = {
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
                        self:UpdateBarItem(self.frame, true)
                    end
                },
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.show_role_counts"] or "Show role counts",
                    width = 220,
                    get = function() return GetDB().showRoleCount end,
                    set = function(val)
                        GetDB().showRoleCount = val
                        self:UpdateBarItem(self.frame, true)
                    end
                }
            }
        },
        {
            type = "row",
            children = {
                {
                    type = "font",
                    label = CoreL["common.font"] or "Font",
                    width = 220,
                    get = function() return GetDB().font end,
                    set = function(val)
                        GetDB().font = val
                        self:UpdateBarItem(self.frame, true)
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
                        self:UpdateBarItem(self.frame, true)
                    end
                }
            }
        },
        { type = "divider", width = 400, label = YBarL["ybar.settings.section.marker_bar"] or "Marker Bar", alignLeft = true },
        {
            type = "row",
            children = {
                {
                    type = "slider",
                    label = YBarL["ybar.settings.option.button_size"] or "Button Size",
                    inline = true,
                    inputWidth = 56,
                    width = 220,
                    min = 10, max = 50, step = 1,
                    get = function() return GetDB().iconSize end,
                    set = function(val)
                        GetDB().iconSize = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "slider",
                    label = YBarL["ybar.settings.option.button_spacing"] or "Button Spacing",
                    inline = true,
                    inputWidth = 56,
                    width = 220,
                    min = 0, max = 20, step = 1,
                    get = function() return GetDB().spacing end,
                    set = function(val)
                        GetDB().spacing = val
                        self:UpdateSettings()
                    end
                },
            }
        },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.lock_position"] or "Lock Position",
                    width = 130,
                    get = function() return GetDB().lockPosition end,
                    set = function(val)
                        GetDB().lockPosition = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.mouse_tooltip"] or "Mouse Tooltip",
                    width = 130,
                    get = function() return GetDB().showTooltip end,
                    set = function(val)
                        GetDB().showTooltip = val
                    end
                },
            }
        },
        {
            type = "row",
            children = {
                {
                    type = "dropdown",
                    label = CoreL["common.display_mode"] or "Display Mode",
                    width = 220,
                    options = {
                        { text = YBarL["ybar.settings.option.manual"] or "Manual", value = "MANUAL" },
                        { text = YBarL["ybar.settings.option.group_auto"] or "Auto in Group", value = "AUTO" },
                        { text = YBarL["ybar.settings.option.mouseover"] or "Mouseover", value = "MOUSEOVER" },
                    },
                    get = function() return GetDB().displayMode end,
                    set = function(val)
                        GetDB().displayMode = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "slider",
                    label = YBarL["raidmarkers.settings.countdown_time"] or "Countdown Time",
                    inline = true,
                    inputWidth = 56,
                    width = 220,
                    min = 5, max = 60, step = 1,
                    get = function() return GetDB().countdownTime or 7 end,
                    set = function(val)
                        GetDB().countdownTime = val
                        self:UpdateSettings()
                    end
                }
            }
        },
        { type = "divider", width = 400, label = YBarL["ybar.settings.section.button_toggles"] or "Button Toggles", alignLeft = true },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.raid_marker"] or "Raid Markers",
                    width = 150,
                    get = function() return GetDB().showMarkers end,
                    set = function(val)
                        GetDB().showMarkers = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.ready_check"] or "Ready Check",
                    width = 150,
                    get = function() return GetDB().showReadyCheck end,
                    set = function(val)
                        GetDB().showReadyCheck = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.countdown"] or "Countdown",
                    width = 150,
                    get = function() return GetDB().showCountdown end,
                    set = function(val)
                        GetDB().showCountdown = val
                        self:UpdateSettings()
                    end
                },
            }
        },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.combat_log"] or "Combat Log",
                    width = 150,
                    get = function() return GetDB().showCombatLog end,
                    set = function(val)
                        GetDB().showCombatLog = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.reset_instances"] or "Reset Instances",
                    width = 170,
                    get = function() return GetDB().showReset end,
                    set = function(val)
                        GetDB().showReset = val
                        self:UpdateSettings()
                    end
                },
            }
        }
    }
    return options
end

function Module:UpdateSettings()
    if not self.bar then return end

    -- Update Layout (Size, Spacing)
    self:UpdateLayout()
    self:UpdateBarItem(self.frame, true) -- Force update bar item text/appearance

    -- Update Lock
    if self.handle then
        if self.db.lockPosition then
             -- Hide tooltip if shown
             YUI.HideGameTooltip()
             self.handle:Hide()
        end
    end

    -- Update MouseOver
    self:UpdateMouseOver()

    -- Update AutoShow
    self:UpdateVisibility()

    -- Update CD Macro & Tooltip
    if self.UpdateCDMacro then self.UpdateCDMacro() end
    if self.UpdateCDTooltip then self.UpdateCDTooltip() end
end

function Module:UpdateMouseOver()
    if not self.bar then return end

    local function OnEnter()
        if self.db.displayMode == "MOUSEOVER" then
             self.bar:SetAlpha(1)
        end
        self:ShowHandle()
    end

    local function OnLeave()
        if self.db.displayMode == "MOUSEOVER" then
             C_Timer.After(0.1, function()
                if not self._runtimeAttached or not self.bar then
                    return
                end
                if not self.bar:IsMouseOver() then
                    self.bar:SetAlpha(0)
                end
             end)
        end
        self:HideHandle()
    end

    self.bar:SetScript("OnEnter", OnEnter)
    self.bar:SetScript("OnLeave", OnLeave)

    if self.db.displayMode == "MOUSEOVER" then
        self.bar:SetAlpha(0)
        -- self.bar:Show() -- Handled by Driver
    else
        self.bar:SetAlpha(1)
    end
end

YBar:RegisterModule(Module, {
    id = "ybar.raidmarkers",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api", "gui"},
    defaultEnabled = true,
})

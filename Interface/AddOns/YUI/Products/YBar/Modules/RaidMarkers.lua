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
local SocialAPI = YUI.API and YUI.API.Social or API.Social
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

local MARKER_ICONS = {"star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull"}
local TOOL_ICONS = {[9]="circle-slash", [10]="check", [11]="timer", [12]="file-text", [13]="rotate-ccw", [14]="users"}
local NATIVE_TOOL_ICONS = {
    ["circle-slash"]={texture="Interface\\Buttons\\UI-GroupLoot-Pass-Up"},
    check={atlas="readycheck-ready", texture="Interface\\RaidFrame\\ReadyCheck-Ready"},
    timer={atlas=YUI.IsWrath and "auctionhouse-icon-clock" or "minimap-genericevent-hornicon-small",
        texture="Interface\\Icons\\Spell_Holy_BorrowedTime"},
    ["file-slash"]={atlas="Perks-PreviewOff-Hover", texture="Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"},
    ["file-text"]={atlas="Perks-PreviewOn", texture="Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"},
    ["rotate-ccw"]={atlas="BattleBar-SwapPetIcon", texture="Interface\\Icons\\Spell_Holy_Resurrection"},
    users={atlas="GM-icon-roles", scale=1.25},
}
-- Semantic icon colors are local to this toolbar; shared artwork remains tintable.
local MARKER_COLORS = {
    {1,216/255,76/255}, {1,148/255,49/255}, {211/255,125/255,244/255}, {74/255,225/255,116/255},
    {243/255,248/255,1}, {73/255,205/255,251/255}, {1,117/255,117/255}, {1,1,1},
}
local TOOL_COLORS = {
    ["circle-slash"]={1,147/255,153/255},
    check={177/255,230/255,133/255}, users={157/255,211/255,251/255},
    timer={1,213/255,82/255}, ["rotate-ccw"]={204/255,169/255,244/255},
    record={1, .35, .35},
}
local STRIP_STYLES = {NONE=true, PLAIN=true, BACKGROUND=true, GROUPED=true, BUTTONS=true, PANEL=true}
local DEFAULT_BACKGROUND_TRANSPARENCY = 40
local AUTO_LOG_COLOR = {0.35, 0.78, 1}
local MARKER_LAYOUT_ID = "ybar.raidmarkers.toolbar"

-- Bounded decoration owned by the toolbar, separate from secure click hosts.
local function CreatePlate(parent, padding)
    local plate = { fill=GUI2:CreateTexture(parent, {layer="BACKGROUND"}), edges={} }
    plate.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", -(padding or 0), padding or 0)
    plate.fill:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", padding or 0, -(padding or 0))
    for i=1,4 do plate.edges[i]=GUI2:CreateTexture(parent, {layer="BORDER"}) end
    local top, bottom, left, right = unpack(plate.edges)
    top:SetPoint("TOPLEFT", plate.fill, "TOPLEFT"); top:SetPoint("TOPRIGHT", plate.fill, "TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT", plate.fill, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", plate.fill, "BOTTOMRIGHT")
    left:SetPoint("TOPLEFT", plate.fill, "TOPLEFT"); left:SetPoint("BOTTOMLEFT", plate.fill, "BOTTOMLEFT")
    right:SetPoint("TOPRIGHT", plate.fill, "TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", plate.fill, "BOTTOMRIGHT")
    return plate
end

local function PaintPlate(plate, fillShown, edgeShown, fillKey, borderKey, alpha)
    local r,g,b,a=GUI2:GetColor(fillKey or "color.surface.panel")
    plate.fill:SetColorTexture(r,g,b,1)
    plate.fill:SetAlpha(alpha or a or 1)
    plate.fill:SetShown(fillShown)
    for i,edge in ipairs(plate.edges) do
        edge:SetColorTexture(GUI2:GetColor(borderKey or "color.border.subtle"))
        if i<=2 then edge:SetHeight(GUI2.mult or 1) else edge:SetWidth(GUI2.mult or 1) end
        edge:SetShown(edgeShown)
    end
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
    if not self.db.iconSize then self.db.iconSize = 20 end -- Shared button size
    if not self.db.markerIconSize then self.db.markerIconSize = self.db.iconSize end
    if not self.db.toolIconSize then self.db.toolIconSize = self.db.iconSize end
    if not self.db.spacing then self.db.spacing = 5 end
    if not self.db.markerStyle then self.db.markerStyle = "COLOR" end
    if not self.db.toolColorStyle then self.db.toolColorStyle = "COLOR" end
    if self.db.stripStyle == "BORDER" then self.db.stripStyle = "PANEL" end
    if not STRIP_STYLES[self.db.stripStyle] then self.db.stripStyle = "NONE" end
    if self.db.backgroundTransparency == nil then self.db.backgroundTransparency = DEFAULT_BACKGROUND_TRANSPARENCY end
    if self.db.autoLogEnabled == nil then self.db.autoLogEnabled = false end
    if type(self.db.autoLogScenes) ~= "table" then self.db.autoLogScenes = {} end
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
    if self.db.showRoleCheck == nil then self.db.showRoleCheck = true end
    if self.db.showCountdown == nil then self.db.showCountdown = true end
    if self.db.showCombatLog == nil then self.db.showCombatLog = true end
    if self.db.showReset == nil then self.db.showReset = true end
    if self.db.countdownTime == nil then self.db.countdownTime = 7 end
    if self.db.showRoleCount == nil then self.db.showRoleCount = false end

    GetYBarDB().RaidMarkers = self.db

    if not self.logging then
        self.logging = YBar.RaidMarkerLogging.New(function() self:UpdateCombatLog() end,
            function() YUI:Print(T("raidmarkers.log.failed")) end)
    end
    if self._runtimeAttached then self.logging:Start(self.db) else self.logging.db = self.db end

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

function Module:QueuePostCombatUpdate(updateBarItem, updateYBarLayout, updateMarkerLayout, updateMarkerRuntime)
    self._pendingBarItemUpdate = self._pendingBarItemUpdate or updateBarItem
    self._pendingYBarLayoutUpdate = self._pendingYBarLayoutUpdate or updateYBarLayout
    self._pendingMarkerLayoutUpdate = self._pendingMarkerLayoutUpdate or updateMarkerLayout
    self._pendingMarkerRuntimeUpdate = self._pendingMarkerRuntimeUpdate or updateMarkerRuntime

    if self._postCombatUpdateHandle then return end

    self._postCombatUpdateHandle = YUI.Event:Once("PLAYER_REGEN_ENABLED", function()
        self._postCombatUpdateHandle = nil
        local pendingBarItem = self._pendingBarItemUpdate
        local pendingYBarLayout = self._pendingYBarLayoutUpdate
        local pendingMarkerLayout = self._pendingMarkerLayoutUpdate
        local pendingMarkerRuntime = self._pendingMarkerRuntimeUpdate
        self._pendingBarItemUpdate = false
        self._pendingYBarLayoutUpdate = false
        self._pendingMarkerLayoutUpdate = false
        self._pendingMarkerRuntimeUpdate = false

        if not self._runtimeAttached then return end
        if self._pendingDragStop then self:FinishMarkerDrag() end
        if pendingMarkerRuntime then self:Update() end
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
    self.logging:Start(self.db)

    if self.frame then
        self.frame:Show()
    end
    self:Update()
end

function Module:DetachRuntime()
    self._runtimeAttached = false
    if self.isDragging then self:FinishMarkerDrag() end
    self:ResetButtonFeedback()
    if self.logging then self.logging:Stop() end
    self:CancelMouseOverHide()
    if self._postCombatUpdateHandle then
        YUI.Event:Off(self._postCombatUpdateHandle)
        self._postCombatUpdateHandle = nil
    end
    self._pendingBarItemUpdate, self._pendingYBarLayoutUpdate, self._pendingMarkerLayoutUpdate = false, false, false
    self._pendingMarkerRuntimeUpdate = false

    if SecurityAPI.InCombatLockdown() then
        self._pendingDetach = true
        YUI.Event:OffOwner(self)
        YUI.Event:On("PLAYER_REGEN_ENABLED", "OnRuntimeEvent", self)
        return
    end

    self._pendingDetach = false

    YUI.Event:OffOwner(self)

    if self._layoutRegistered then
        YUI.Layout:UnregisterFrame(MARKER_LAYOUT_ID)
        self._layoutRegistered = nil
    end
    self._layoutPreview = nil

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
    if SecurityAPI.InCombatLockdown() then
        self:QueuePostCombatUpdate(false, false, false, true)
        return
    end

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
        self:RegisterMarkerLayout()
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
    if SecurityAPI.InCombatLockdown() then
        self:QueuePostCombatUpdate(false, false, false, true)
        return
    end

    -- Ensure module is active on YBar
    if not YBar:IsSubModuleEnabled(self.name) then
        UnregisterStateDriver(self.bar, "visibility")
        self.bar:Hide()
        return
    end

    local driver = "hide"
    if self._layoutPreview then
        -- A combat transition must not leave the edit-only preview visible.
        driver = "[combat] hide; show"
    elseif self.db.displayMode == "AUTO" then
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
    if self.db.displayMode == "MOUSEOVER" and not self._layoutPreview then
        self.bar:SetAlpha((self.isDragging or self.bar:IsMouseOver()) and 1 or 0)
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
        local yOffset = -12

        if anchorY < screenHeight / 2 then
            anchor = "ANCHOR_TOP"
            yOffset = 12
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
    if not self.bar or not self.handle then return end
    if not self.db.lockPosition and (self._visibleButtonCount or 0)>0 then self.handle:SetAlpha(1) end
end

function Module:CancelMouseOverHide()
    if self._mouseOverTimer then
        self._mouseOverTimer:Cancel()
        self._mouseOverTimer = nil
    end
end

function Module:ShowMouseOverBar()
    self:CancelMouseOverHide()
    if self.bar and self.db.displayMode=="MOUSEOVER" then self.bar:SetAlpha(1) end
end

function Module:QueueMouseOverHide()
    if self._mouseOverTimer or not self._runtimeAttached or self._layoutPreview then return end
    if self.db.displayMode~="MOUSEOVER" and self.db.lockPosition then return end
    if not self._hideMouseOverBar then
        self._hideMouseOverBar = function()
            self._mouseOverTimer = nil
            if self._runtimeAttached and not self._layoutPreview and self.bar and not self.isDragging and not self.bar:IsMouseOver()
                and not (self.handle and self.handle:IsMouseOver()) then
                if self.db.displayMode=="MOUSEOVER" then self.bar:SetAlpha(0) end
                if self.handle then self.handle:SetAlpha(0) end
            end
        end
    end
    self._mouseOverTimer = C_Timer.NewTimer(0.1,self._hideMouseOverBar)
end

function Module:HideHandle()
    self:QueueMouseOverHide()
end

function Module:AnchorMarkerTooltip(owner)
    local bar = self.bar or owner
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if (bar:GetBottom() or 0) < GetScreenHeight()/2 then
        GameTooltip:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 12)
    else
        GameTooltip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
    end
end

function Module:FinishMarkerDrag()
    if not self.isDragging then return end
    if SecurityAPI.InCombatLockdown() then
        self._pendingDragStop = true
        self:QueuePostCombatUpdate(false, false, true)
        return
    end
    self.bar:StopMovingOrSizing()
    self.isDragging, self._pendingDragStop = false, nil
    if self._layoutRegistered then
        YUI.Layout:CommitFramePosition(MARKER_LAYOUT_ID, self.bar, "marker-grip-drag")
    else
        local point, _, relativePoint, xOfs, yOfs = self.bar:GetPoint()
        self.db.position = {point, relativePoint, xOfs, yOfs}
    end
    if self.handle then
        self.handle.feedbackPressed = false
        self:UpdateButtonFeedback(self.handle)
    end
    self:UpdateStripChrome()
    self:QueueMouseOverHide()
end

function Module:RegisterMarkerLayout()
    if not self.bar or not self._runtimeAttached
        or not (YUI.IsRetail or YUI.IsForever) or not YUI.Layout
        or not YUI.Layout.RegisterFrame or SecurityAPI.InCombatLockdown() then return end

    -- Import the legacy screen anchor once; future moves have one placement owner.
    if not self.db.layoutPlacement and self.db.position then
        local point, relativePoint, x, y = unpack(self.db.position)
        self.db.layoutPlacement = {
            anchor={point=point, relative="UIParent", relativePoint=relativePoint},
            offset={x=x, y=y},
        }
    end
    if self._layoutRegistered then
        YUI.Layout:RefreshFrame(MARKER_LAYOUT_ID)
        return
    end
    local entry = YUI.Layout:RegisterFrame(MARKER_LAYOUT_ID, {
        frame=self.bar, title=GetBarItemName(), editModeCategory="information",
        movable=true, snap=true, combatProtected=true,
        defaultPlacement={anchor={point="CENTER", relative="UIParent", relativePoint="CENTER"}, offset={x=0,y=0}},
        placementStorage={
            identity=function() return self.db end,
            get=function() return self.db.layoutPlacement end,
            set=function(_, _, placement) self.db.layoutPlacement=placement; return true end,
            clear=function() self.db.layoutPlacement=nil; self.db.position=nil; return true end,
        },
        isEnabled=function()
            return self._runtimeAttached and YBar:IsSubModuleEnabled(self.name)
                and (self._visibleButtonCount or 0)>0
        end,
        openPluginSettings=function() YUI:OpenYBarModuleSettings("RaidMarkers") end,
        onEnterEditMode=function()
            if self.isDragging then self:FinishMarkerDrag() end
            self:CancelMouseOverHide()
            self._layoutPreview=true
            self:UpdateVisibility()
        end,
        onExitEditMode=function()
            self._layoutPreview=nil
            if self._runtimeAttached then self:UpdateVisibility() end
        end,
    })
    self._layoutRegistered = entry and true or nil
    if entry then YUI.Layout:RefreshFrame(MARKER_LAYOUT_ID) end
end

function Module:CreateMarkerBar()
    if self.bar then return end
    if SecurityAPI.InCombatLockdown() then
        self:QueuePostCombatUpdate(false, false, false, true)
        return
    end

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
    local handle = GUI2:CreateFrame(bar, {mouse=true, width=18})
    handle.isGrip = true
    handle.icon = GUI2:CreateIcon(handle, {icon=GUI2:GetUIIcon("grip-vertical",16), size=16, crop=false})
    handle.icon:SetPoint("CENTER")
    handle.feedbackPlate = CreatePlate(handle, 1)
    handle:SetPoint("LEFT", bar, "LEFT", 5, 0)

    handle:SetScript("OnEnter", function()
        self:ShowMouseOverBar()
        handle.feedbackHovered = true
        self:UpdateButtonFeedback(handle)
        if self.db.showTooltip and not self.db.lockPosition then
            self:AnchorMarkerTooltip(handle)
            GameTooltip:AddLine(T("raidmarkers.tooltip.drag_hint", "按住拖动"))
            GameTooltip:Show()
        end
        self:ShowHandle()
    end)
    handle:SetScript("OnLeave", function()
        handle.feedbackHovered = false
        if not self.isDragging then handle.feedbackPressed = false end
        self:UpdateButtonFeedback(handle)
        YUI.HideGameTooltip()
        self:QueueMouseOverHide()
        self:HideHandle()
    end)
    handle:SetScript("OnMouseDown", function(_,button)
        if button=="LeftButton" then handle.feedbackPressed=true; self:UpdateButtonFeedback(handle) end
    end)
    handle:SetScript("OnMouseUp", function()
        if not self.isDragging then handle.feedbackPressed=false; self:UpdateButtonFeedback(handle) end
    end)
    handle:SetScript("OnHide", function()
        handle.feedbackHovered, handle.feedbackPressed = false, false
        self:UpdateButtonFeedback(handle)
        if GameTooltip and GameTooltip:GetOwner()==handle then YUI.HideGameTooltip() end
    end)

    -- Frame type does not have RegisterForClicks, it's for Button.
    -- RegisterForDrag is sufficient for dragging.
    handle:RegisterForDrag("LeftButton")

    handle:SetScript("OnDragStart", function()
        if not self.db.lockPosition and not self._layoutPreview and not SecurityAPI.InCombatLockdown() then
            self:CancelMouseOverHide()
            self.isDragging = true
            self:ShowHandle()
            bar:StartMoving()
            self:UpdateStripChrome()
        end
    end)

    handle:SetScript("OnDragStop", function()
        self:FinishMarkerDrag()
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
    bar:HookScript("OnHide", function()
        if self.isDragging then self:FinishMarkerDrag() end
        self:CancelMouseOverHide()
        self:ResetButtonFeedback()
        handle:SetAlpha(0)
    end)

    self:CreateButtons()

    -- Initial State handled by UpdateVisibility
    -- Remove manual show/hide logic here

    self:UpdateLayout()
    self:UpdateMouseOver()

end

function Module:AddHoverEffect(btn, tooltipTitle, tooltipText)
    btn:SetScript("OnEnter", function(self)
        self.feedbackHovered = true
        Module:UpdateButtonFeedback(self)
        -- MouseOver logic
        Module:ShowMouseOverBar()
        -- Drag handle
        if Module.ShowHandle then
             Module:ShowHandle()
        end

        -- Tooltip
        if Module.db.showTooltip and tooltipText then
            Module:AnchorMarkerTooltip(self)
            GameTooltip:ClearLines()

            local title = type(tooltipTitle) == "function" and tooltipTitle() or tooltipTitle
            local content = type(tooltipText) == "function" and tooltipText() or tooltipText
            if title then
                GameTooltip:AddLine(title, 1, 0.82, 0) -- Gold title
                GameTooltip:AddLine(" ")
            end

            local white = "|cffffffff"
            local gold = "|cffFFD100"

            -- Simple parsing for our custom format: "Label: Desc" -> Gold Label, White Desc
            for line in string.gmatch(content, "[^\r\n]+") do
                local label, desc = string.match(line, "^(.-):%s*(.+)$")
                if label and desc and not line:find("|c",1,true) then
                    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, label, gold, desc))
                else
                    GameTooltip:AddLine(line, 1, 1, 1)
                end
            end

            GameTooltip:AddLine(T("raidmarkers.tooltip.open_settings"), 0.65, 0.65, 0.65)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.feedbackHovered, self.feedbackPressed = false, false
        Module:UpdateButtonFeedback(self)
        -- MouseOver logic
        Module:QueueMouseOverHide()
        -- Drag handle
        if Module.HideHandle then
             Module:HideHandle()
        end

        YUI.HideGameTooltip()
    end)
    btn:SetScript("OnHide", function(self)
        self.feedbackHovered, self.feedbackPressed = false, false
        Module:UpdateButtonFeedback(self)
        if GameTooltip and GameTooltip:GetOwner()==self then YUI.HideGameTooltip() end
    end)
end

function Module:UpdateButtonFeedback(btn, force)
    if not btn.feedbackPlate then return end
    local mode = btn.feedbackPressed and "pressed" or btn.feedbackHovered and "hover"
        or self.db.stripStyle=="BUTTONS" and "key" or "normal"
    if not force and btn.feedbackMode==mode then return end
    btn.feedbackMode=mode
    local fill, border, alpha = "color.surface.panel", "color.border.subtle",
        1-(self.db.backgroundTransparency or DEFAULT_BACKGROUND_TRANSPARENCY)/100
    if mode=="hover" then
        fill, border, alpha = "color.overlay.highlight", "color.border.strong", 0.28
    elseif mode=="pressed" then
        fill, border, alpha = "color.accent.primary", "color.border.accent", 0.42
    end
    PaintPlate(btn.feedbackPlate, mode~="normal", mode~="normal", fill, border, alpha)
end

function Module:ResetButtonFeedback()
    for _,btn in ipairs(self.buttons or {}) do
        btn.feedbackHovered, btn.feedbackPressed = false, false
        self:UpdateButtonFeedback(btn)
    end
    if self.handle then
        self.handle.feedbackHovered, self.handle.feedbackPressed = false, false
        self:UpdateButtonFeedback(self.handle)
    end
end

local OPEN_MARKER_SETTINGS = {kind="custom", onClick=function() YUI:OpenYBarModuleSettings("RaidMarkers") end}

local function AttachMarkerActionHost(btn, actions)
    actions.altLeft = OPEN_MARKER_SETTINGS
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
        -- These hooks only paint the ordinary owner; native action attributes stay intact.
        host:HookScript("OnMouseDown", function(_,button)
            if button=="LeftButton" or button=="RightButton" then
                btn.feedbackPressed=true
                Module:UpdateButtonFeedback(btn)
            end
        end)
        host:HookScript("OnMouseUp", function()
            btn.feedbackPressed=false
            Module:UpdateButtonFeedback(btn)
        end)
        host:HookScript("OnHide", function()
            btn.feedbackHovered, btn.feedbackPressed = false, false
            Module:UpdateButtonFeedback(btn)
            if GameTooltip and GameTooltip:GetOwner()==btn then YUI.HideGameTooltip() end
        end)
    end
    return host
end

local function SetButtonIcon(btn, texture, atlas)
    btn.iconAtlas = atlas
    if btn.iconSlot then
        YBar:SetIconSlotTexture(btn.iconSlot, texture, atlas, not atlas and {0, 1, 0, 1} or nil)
        GUI2:ApplyUIIconEffect(btn.icon, not atlas and texture or nil)
    elseif btn.icon then
        GUI2:SetIconTexture(btn.icon, atlas and "atlas:" .. atlas or texture)
        if not atlas then btn.icon:SetTexCoord(0, 1, 0, 1) end
    end
end

local function SetToolIcon(btn, size, state)
    local name = btn.recordDot and state==false and "file-slash" or btn.toolIcon
    local native = Module.db.toolColorStyle=="ATLAS" and NATIVE_TOOL_ICONS[name]
    if native then
        if native.atlas and C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, native.atlas)
            if ok and info then
                SetButtonIcon(btn, nil, native.atlas)
                if native.scale then
                    local nativeSize = size * native.scale
                    btn.icon:SetSize(nativeSize, nativeSize)
                end
                return
            end
        end
        if native.texture then
            SetButtonIcon(btn, native.texture)
            return
        end
    end
    SetButtonIcon(btn, GUI2:GetUIIcon(name, size))
end

local function SetLogModeColor(btn, automatic, state)
    local native = Module.db.toolColorStyle=="ATLAS"
    if automatic and not native then btn.icon:SetVertexColor(unpack(AUTO_LOG_COLOR)) else btn.icon:SetVertexColor(1,1,1) end
    if btn.offSlash then btn.offSlash:SetShown(not native and automatic and state==false) end
end

local function CreateButtonIcon(btn, size, texture, atlas)
    -- Markers are complete artwork, not spell icons: no masks, crop or zoom.
    btn.icon = GUI2:CreateIcon(btn, {icon=texture, size=size, crop=false})
    btn.icon:SetPoint("CENTER")
    SetButtonIcon(btn, texture, atlas)
    if not atlas then btn.icon:SetTexCoord(0, 1, 0, 1) end
    btn.feedbackPlate=CreatePlate(btn, 2)
    Module:UpdateButtonFeedback(btn, true)
end

function Module:CreateButtons()
    self.buttons = {}
    local size = self.db.iconSize
    local markerIconSize, toolIconSize = self.db.markerIconSize, self.db.toolIconSize

    -- 1-8 Markers
    for i = 1, 8 do
        local btn = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtn" .. i })
        btn:SetSize(size, size)

        -- Texture
        CreateButtonIcon(btn, markerIconSize, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"..i)
        btn.markerID = i

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
        local markerName = T("raidmarkers.marker." .. MARKER_ICONS[i])
        self:AddHoverEffect(btn, T("raidmarkers.tooltip.target_marker", "团队标记 %s", iconStr .. " " .. markerName), tooltip)
        tinsert(self.buttons, btn)
    end

    -- 9: Clear
    local btnClear = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnClear" })
    btnClear:SetSize(size, size)
    CreateButtonIcon(btnClear, toolIconSize, GUI2:GetUIIcon("circle-slash", toolIconSize))

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
    CreateButtonIcon(btnRC, toolIconSize, GUI2:GetUIIcon("check", toolIconSize))

    AttachMarkerActionHost(btnRC, {
        left = { kind = "macro", macrotext = "/readycheck" },
    })

    self:AddHoverEffect(btnRC, T("raidmarkers.tooltip.ready_check", "就位确认"), format("%s: %s", LC["common.left_click"], T("raidmarkers.action.ready_check", "发起就位确认")))
    tinsert(self.buttons, btnRC)

    -- 11: Countdown
    local btnCD = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnCD" })
    btnCD:SetSize(size, size)
    CreateButtonIcon(btnCD, toolIconSize, GUI2:GetUIIcon("timer", toolIconSize))

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
                altLeft = OPEN_MARKER_SETTINGS,
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
    CreateButtonIcon(btnLog, toolIconSize, GUI2:GetUIIcon("file-text", toolIconSize))
    btnLog.recordDot = GUI2:CreateTexture(btnLog, {layer="OVERLAY"})
    GUI2:SetIconTexture(btnLog.recordDot, GUI2:GetUIIcon("record", 16))
    btnLog.recordDot:SetPoint("BOTTOMRIGHT", btnLog.icon, "BOTTOMRIGHT", -1, 1)
    btnLog.recordDot:SetSize(5, 5)
    btnLog.recordDot:Hide()
    if YUI.IsRetail or YUI.IsForever then
        -- Native Line keeps the off slash white independently of the document tint.
        btnLog.offSlash = btnLog:CreateLine(nil, "OVERLAY")
        btnLog.offSlash:SetColorTexture(1,1,1,1)
        btnLog.offSlash:Hide()
    end
    btnLog.UpdateLogIcon = function() self.logging:ReadState(true); self:UpdateCombatLog() end
    AttachMarkerActionHost(btnLog, {
        left = {
            kind = "custom",
            onClick = function() self.logging:ToggleManual() end,
        },
        right = { kind="custom", onClick=function() self:ToggleAutoLogging() end },
    })
    if self._runtimeAttached then
        YUI.Event:OffOwner(btnLog)
        YUI.Event:On("YUI_WORLD_READY", "UpdateLogIcon", btnLog)
    end

    self:AddHoverEffect(btnLog, T("raidmarkers.settings.combat_log"), function() return self:GetCombatLogTooltip() end)
    tinsert(self.buttons, btnLog)

    -- 13: Reset Instances (Standard Button)
    local btnReset = GUI2:CreateButtonFrame(self.bar, { name = "YUI_RaidMarkerBtnReset" })
    btnReset:SetSize(size, size)
    CreateButtonIcon(btnReset, toolIconSize, GUI2:GetUIIcon("rotate-ccw", toolIconSize))

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

    -- 14: Role Check; preserve the existing countdown/log button indices.
    if YUI.IsRetail or YUI.IsForever then
        local btnRole = GUI2:CreateFrame(self.bar, { name = "YUI_RaidMarkerBtnRole" })
        btnRole:SetSize(size, size)
        CreateButtonIcon(btnRole, toolIconSize, GUI2:GetUIIcon("users", toolIconSize))
        AttachMarkerActionHost(btnRole, {
            left = {
                kind = "custom",
                onClick = function()
                    if not SocialAPI or not SocialAPI.InitiateRolePoll or not SocialAPI.InitiateRolePoll() then
                        YUI:Print(T("raidmarkers.error.role_check_unavailable", "当前无法发起职责确认，请检查队伍权限及组队限制。"))
                    end
                end,
            },
        })
        self:AddHoverEffect(btnRole, T("raidmarkers.tooltip.role_check", "职责确认"), format("%s: %s", LC["common.left_click"], T("raidmarkers.action.role_check", "发起职责确认")))
        tinsert(self.buttons, btnRole)
    end
    for index, button in ipairs(self.buttons) do button.toolIcon = TOOL_ICONS[index] end
end

function Module:UpdateLayout()
    if not self.buttons or not self.bar then return end
    if SecurityAPI.InCombatLockdown() then
        self:QueuePostCombatUpdate(false, false, true)
        return
    end

    local style = self.db.stripStyle
    local spacing = style=="BUTTONS" and math.max(self.db.spacing,5) or self.db.spacing
    local size = self.db.iconSize
    local padding = style=="PANEL" and 8 or 5
    local groupGap = style=="GROUPED" and 12 or 6

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

    if self.db.showRoleCheck and self.buttons[14] then
        tinsert(visibleButtons, self.buttons[14])
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
    self._visibleButtons, self._visibleButtonCount = visibleButtons, numButtons
    self._stripHasDivider = self.db.showMarkers and numButtons > 8
    self.bar:EnableMouse(numButtons>0)
    if numButtons == 0 then
        self.bar:SetSize(10, size + 10)
        if self.handle then self.handle:Hide() end
        self:UpdateStripChrome()
        return
    end

    local hasDivider = self.db.showMarkers and numButtons > 8
    local width = (size * numButtons) + (spacing * (numButtons - 1)) + padding*2
        + (hasDivider and groupGap or 0)
    self.bar:SetSize(width, size + padding*2)
    if self.handle then
        self.handle:ClearAllPoints()
        self.handle:SetPoint("RIGHT", self.bar, "LEFT", -2, 0)
        self.handle:SetSize(18,size)
        self.handle:SetShown(not self.db.lockPosition)
        self.handle:SetAlpha((self.isDragging or self.bar:IsMouseOver() or self.handle:IsMouseOver()) and 1 or 0)
    end

    for i, btn in ipairs(visibleButtons) do
        btn:Show()
        btn:SetSize(size, size)
        if i == 1 then
            btn:SetPoint("LEFT", self.bar, "LEFT", padding, 0)
        else
            local previous = visibleButtons[i-1]
            local gap = previous.markerID and not btn.markerID and groupGap or 0
            btn:SetPoint("LEFT", previous, "RIGHT", spacing + gap, 0)
        end

        -- Update texture size if needed (for scaling)
        if btn.icon then
            local iconSize = btn.markerID and self.db.markerIconSize or self.db.toolIconSize
            btn.icon:SetSize(iconSize, iconSize)
            if btn.markerID then
                local outline = self.db.markerStyle == "WHITE" or self.db.markerStyle == "LINE_COLOR"
                local texture = outline and GUI2:GetUIIcon("raid-" .. MARKER_ICONS[btn.markerID], iconSize)
                    or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. btn.markerID
                SetButtonIcon(btn, texture)
            else
                SetToolIcon(btn, iconSize, self.logging.enabled)
            end
            local color
            if btn.markerID then
                color = self.db.markerStyle == "LINE_COLOR" and MARKER_COLORS[btn.markerID]
            elseif self.db.toolColorStyle == "COLOR" then
                color = TOOL_COLORS[btn.toolIcon]
            end
            -- Explicitly clear tint when returning to native artwork or white icons.
            if color then btn.icon:SetVertexColor(unpack(color)) else btn.icon:SetVertexColor(1,1,1) end
            if btn.recordDot then
                SetLogModeColor(btn, self.db.autoLogEnabled==true, self.logging.enabled)
                if btn.offSlash then
                    local inset=iconSize/8
                    btn.offSlash:SetStartPoint("BOTTOMLEFT",btn.icon,inset,inset)
                    btn.offSlash:SetEndPoint("TOPRIGHT",btn.icon,-inset,-inset)
                    btn.offSlash:SetThickness(iconSize*(iconSize<=18 and 1.75 or 2)/24)
                end
                if self.db.toolColorStyle == "COLOR" then
                    btn.recordDot:SetVertexColor(unpack(TOOL_COLORS.record))
                else
                    btn.recordDot:SetVertexColor(1,1,1)
                end
            end
            if not btn.iconAtlas then btn.icon:SetTexCoord(0, 1, 0, 1) end
            btn.icon:SetAlpha(1)
        end
        self:UpdateButtonFeedback(btn,true)
    end
    self:UpdateStripChrome()
    self:UpdateCombatLog()
    if self._layoutRegistered then YUI.Layout:RefreshFrame(MARKER_LAYOUT_ID) end
end

function Module:UpdateStripChrome()
    if not self.bar then return end
    if not self.stripPlate then
        self.stripPlate=CreatePlate(self.bar)
        self.stripBackground,self.stripEdges=self.stripPlate.fill,self.stripPlate.edges
        self.groupPlates={CreatePlate(self.bar),CreatePlate(self.bar)}
        self.stripDivider = GUI2:CreateTexture(self.bar, {layer="ARTWORK"})
        self.dragOutline=CreatePlate(self.bar,2)
        self.panelShadow=GUI2:CreateFrame(self.bar,{mouse=false})
        self.panelShadow:SetAllPoints(self.bar)
        self.panelShadow:SetFrameLevel(self.bar:GetFrameLevel())
        GUI2:CreateShadow(self.panelShadow)
        self.stripBackground.RefreshTheme = function()
            self:UpdateStripChrome()
            for _,btn in ipairs(self.buttons or {}) do self:UpdateButtonFeedback(btn,true) end
            if self.handle then self:UpdateButtonFeedback(self.handle,true) end
        end
        GUI2:RegisterThemeObject(self.stripBackground)
    end
    -- Profile replacement can refresh theme objects before module initialization,
    -- including parked views whose instance no longer exists. Read defaults only.
    local style, count = self.db.stripStyle or "NONE", self._visibleButtonCount or 0
    local alpha=1-(self.db.backgroundTransparency or DEFAULT_BACKGROUND_TRANSPARENCY)/100
    local visible=count>0
    PaintPlate(self.stripPlate,visible and (style=="PLAIN" or style=="BACKGROUND" or style=="PANEL"),
        visible and (style=="BACKGROUND" or style=="PANEL"),nil,
        style=="PANEL" and "color.border.default" or "color.border.subtle",alpha)
    self.panelShadow:SetShown(visible and style=="PANEL")
    PaintPlate(self.dragOutline,false,visible and self.isDragging==true,nil,"color.border.accent")
    local first=self._visibleButtons and self._visibleButtons[1]
    local last=self._visibleButtons and self._visibleButtons[count]
    for i,plate in ipairs(self.groupPlates) do
        local start, finish
        if visible and style=="GROUPED" then
            if i==1 then
                start=first
                finish=self._stripHasDivider and self.buttons[8] or last
            elseif self._stripHasDivider then
                start,finish=self.buttons[9],last
            end
        end
        if start then
            plate.fill:ClearAllPoints()
            plate.fill:SetPoint("TOPLEFT",start,"TOPLEFT",-3,3)
            plate.fill:SetPoint("BOTTOMRIGHT",finish,"BOTTOMRIGHT",3,-3)
        end
        PaintPlate(plate,start~=nil,start~=nil,nil,"color.border.subtle",alpha)
    end
    self.stripDivider:SetColorTexture(GUI2:GetColor("color.border.subtle"))
    if visible and self._stripHasDivider then
        self.stripDivider:ClearAllPoints()
        self.stripDivider:SetPoint("LEFT",self.buttons[8],"RIGHT",(self.db.spacing or 5)/2+3,0)
        self.stripDivider:SetSize(GUI2.mult or 1,(self.db.iconSize or 20)*.7)
    end
    self.stripDivider:SetShown(visible and self._stripHasDivider and style~="GROUPED" and style~="PLAIN")
    if self.handle then self:UpdateButtonFeedback(self.handle,true) end
end

function Module:UpdateCombatLog()
    local btn = self.buttons and self.buttons[12]
    if not btn or not self.logging then return end
    local state = self.logging.enabled
    local automatic=self.db.autoLogEnabled==true
    local style = self.db.toolColorStyle
    if not btn.logVisualInitialized or btn.logVisualState ~= state or btn.logVisualAuto ~= automatic or btn.logVisualStyle ~= style then
        btn.logVisualInitialized = true
        btn.logVisualState = state
        btn.logVisualAuto = automatic
        btn.logVisualStyle = style
        SetToolIcon(btn, self.db.toolIconSize, state)
        SetLogModeColor(btn, automatic, state)
        btn.icon:SetAlpha(1)
        btn.recordDot:SetShown(state == true and style~="ATLAS")
        self:UpdateButtonFeedback(btn)
    end
    if GameTooltip and GameTooltip:GetOwner() == btn then
        local enter = btn:GetScript("OnEnter")
        if enter then enter(btn) end
    end
end

function Module:ToggleAutoLogging()
    self.logging:SetAutomatic(not self.db.autoLogEnabled)
    self:UpdateCombatLog()
    if YBar.RefreshFeatureSettings then YBar:RefreshFeatureSettings() end
end

function Module:GetCombatLogTooltip()
    -- Read the native state again on hover; no permanent update loop.
    local enabled, advanced = SystemAPI.GetCombatLoggingState()
    local logger = self.logging
    local green, gray, gold = "|cff70e090", "|cffaaaaaa", "|cffffd166"
    local status = enabled == nil and (gold .. T("raidmarkers.log.unknown") .. "|r")
        or ((enabled and green or gray) .. T(enabled and "raidmarkers.log.recording" or "raidmarkers.log.stopped") .. "|r")
    local auto = (self.db.autoLogEnabled and green or gray)
        .. T(self.db.autoLogEnabled and "raidmarkers.log.enabled" or "raidmarkers.log.disabled") .. "|r"
    local lines = {
        T("raidmarkers.log.current", nil, status) .. "  ·  "
            .. T("raidmarkers.log.advanced", nil, (advanced and green or gray)
                .. T(advanced and "raidmarkers.log.enabled" or "raidmarkers.log.disabled") .. "|r"),
        T("raidmarkers.log.automatic", nil, auto),
    }
    if self.db.autoLogEnabled then
        local anyScene = false
        for _,key in ipairs(YBar.RaidMarkerLogging.GetSceneKeys()) do
            if self.db.autoLogScenes[key] then anyScene=true; break end
        end
        local reason = not anyScene and "raidmarkers.log.no_scenes_selected"
            or logger.manual == false and "raidmarkers.log.paused"
            or not logger.matches and "raidmarkers.log.waiting"
        if reason then lines[#lines+1] = gold .. T(reason) .. "|r" end
    end
    lines[#lines+1] = " "
    lines[#lines+1] = T("raidmarkers.log.left", nil, gold .. T(enabled and "raidmarkers.log.stop" or "raidmarkers.log.start") .. "|r")
    if YUI.IsRetail or YUI.IsForever then
        lines[#lines+1] = T("raidmarkers.log.right", nil, gold .. T(self.db.autoLogEnabled and "raidmarkers.log.disable_auto" or "raidmarkers.log.enable_auto") .. "|r")
    end
    return table.concat(lines, "\n")
end

function Module:ToggleMarkerBar()
    if not self.bar then return end
    if self._layoutPreview then return end

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
    local markerLabelWidth = 80
    local markerLabelGap = 10
    local markerControlX = markerLabelWidth + markerLabelGap

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
            type="row", children={
                {type="dropdown", label=T("raidmarkers.settings.marker_style"), width=220,
                    inlineLabel=true, labelWidth=markerLabelWidth, gap=markerLabelGap,
                    options={
                        {text=T("raidmarkers.style.color"),value="COLOR"},
                        {text=T("raidmarkers.style.white"),value="WHITE"},
                        {text=T("raidmarkers.style.line_color"),value="LINE_COLOR"},
                    },
                    get=function() return GetDB().markerStyle end,
                    set=function(value) GetDB().markerStyle=value; self:UpdateSettings() end},
                {type="dropdown", label=T("raidmarkers.settings.tool_colors"), width=220,
                    inlineLabel=true, labelWidth=markerLabelWidth, gap=markerLabelGap,
                    options={
                        {text=T("raidmarkers.style.tool_native"),value="ATLAS"},
                        {text=T("raidmarkers.style.tool_white"),value="WHITE"},
                        {text=T("raidmarkers.style.tool_color"),value="COLOR"},
                    },
                    get=function() return GetDB().toolColorStyle end,
                    set=function(value) GetDB().toolColorStyle=value; self:UpdateSettings() end},
            },
        },
        {
            type="row", children={
                {type="dropdown", label=T("raidmarkers.settings.strip_style"), width=220,
                    inlineLabel=true, labelWidth=markerLabelWidth, gap=markerLabelGap,
                    options={
                        {text=T("raidmarkers.style.none"),value="NONE"},
                        {text=T("raidmarkers.style.plain"),value="PLAIN"},
                        {text=T("raidmarkers.style.background"),value="BACKGROUND"},
                        {text=T("raidmarkers.style.grouped"),value="GROUPED"},
                        {text=T("raidmarkers.style.buttons"),value="BUTTONS"},
                        {text=T("raidmarkers.style.panel"),value="PANEL"},
                    },
                    get=function() return GetDB().stripStyle end,
                    set=function(value) GetDB().stripStyle=value; self:UpdateSettings() end,
                    onChange=function()
                        if YBar.RefreshFeatureSettings then YBar:RefreshFeatureSettings() end
                    end},
                {type="slider", label=T("raidmarkers.settings.background_transparency"), width=220,
                    labelWidth=markerControlX,
                    min=0, max=100, step=1, inline=true, inputWidth=56,
                    hidden=function() return GetDB().stripStyle=="NONE" end,
                    get=function() return GetDB().backgroundTransparency end,
                    set=function(value) GetDB().backgroundTransparency=value; self:UpdateSettings() end},
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "slider",
                    label = YBarL["ybar.settings.option.button_size"] or "Button Size",
                    inline = true,
                    labelWidth = markerControlX,
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
                    labelWidth = markerControlX,
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
                    type = "slider",
                    label = T("raidmarkers.settings.marker_size"),
                    inline = true,
                    labelWidth = markerControlX,
                    inputWidth = 56,
                    width = 220,
                    min = 10, max = 50, step = 1,
                    get = function() return GetDB().markerIconSize end,
                    set = function(val)
                        GetDB().markerIconSize = val
                        self:UpdateSettings()
                    end
                },
                {
                    type = "slider",
                    label = T("raidmarkers.settings.tool_size"),
                    inline = true,
                    labelWidth = markerControlX,
                    inputWidth = 56,
                    width = 220,
                    min = 10, max = 50, step = 1,
                    get = function() return GetDB().toolIconSize end,
                    set = function(val)
                        GetDB().toolIconSize = val
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
                    inlineLabel = true,
                    labelWidth = markerLabelWidth,
                    gap = markerLabelGap,
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
                    labelWidth = markerControlX,
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
        {type="divider", label=T("raidmarkers.settings.auto_log"), width=400, alignLeft=true,
            hidden=function() return not (YUI.IsRetail or YUI.IsForever) end},
        {type="checkbox", label=T("raidmarkers.settings.auto_log"), width=440,
            hidden=function() return not (YUI.IsRetail or YUI.IsForever) end,
            get=function() return GetDB().autoLogEnabled end,
            set=function(value)
                self.logging:SetAutomatic(value)
                self:UpdateCombatLog()
            end,
            onChange=function()
                if YBar.RefreshFeatureSettings then YBar:RefreshFeatureSettings() end
            end},
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
                {
                    type = "checkbox",
                    label = YBarL["raidmarkers.settings.role_check"] or "Role Check",
                    width = 150,
                    hidden = function() return not (YUI.IsRetail or YUI.IsForever) end,
                    get = function() return GetDB().showRoleCheck end,
                    set = function(val)
                        GetDB().showRoleCheck = val
                        self:UpdateSettings()
                    end
                },
            }
        }
    }
    if YUI.IsRetail or YUI.IsForever then
        local insertAt
        for i, option in ipairs(options) do
            if option.type=="divider" and option.label==(YBarL["ybar.settings.section.button_toggles"] or "Button Toggles") then insertAt=i; break end
        end
        local row
        for i, key in ipairs(YBar.RaidMarkerLogging.GetSceneKeys()) do
            if i % 2 == 1 then
                row={type="row", rowGap=4, children={},
                    hidden=function() return not GetDB().autoLogEnabled end}
                table.insert(options, insertAt, row); insertAt=insertAt+1
            end
            row.children[#row.children+1] = {type="checkbox", label=T("raidmarkers.scene." .. key), width=220,
                get=function() return GetDB().autoLogScenes[key] == true end,
                set=function(value)
                    GetDB().autoLogScenes[key]=value==true
                    if self._runtimeAttached then self.logging:Evaluate() end
                end}
        end
    end
    return options
end

function Module:UpdateSettings()
    if not self.bar then return end

    -- Update Layout (Size, Spacing)
    self:UpdateLayout()
    self:UpdateBarItem(self.frame, true) -- Force update bar item text/appearance

    -- Update Lock
    if self.handle and not SecurityAPI.InCombatLockdown() then
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
    self:CancelMouseOverHide()

    local function OnEnter()
        self:ShowMouseOverBar()
        self:ShowHandle()
    end

    local function OnLeave()
        self:QueueMouseOverHide()
        self:HideHandle()
    end

    self.bar:SetScript("OnEnter", OnEnter)
    self.bar:SetScript("OnLeave", OnLeave)

    if self.db.displayMode == "MOUSEOVER" and not self._layoutPreview then
        self.bar:SetAlpha((self.isDragging or self.bar:IsMouseOver()) and 1 or 0)
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

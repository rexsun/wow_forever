local YUI = _G.YUI
local YBar, GUI = YUI.YBar, YUI.GUI2
local Info = YBar.InfoModule
local Item, Spell, Unit = YUI.API.Item, YUI.API.Spell, YUI.API.Unit
local Security, Combat = YUI.API.Security, YUI.API.Combat
local L, LC = YUI.Locale:Get("YBar"), YUI.Locale:Get("Core")
local Module = YBar.Module:New("Teleports")
local HEARTHSTONE = 6948
local TELEPORT_RUNE, PORTAL_RUNE = 17031, 17032
local MAGE_ICON_SIZE, MAGE_PADDING = 32, 4

-- Forever 1.60.1.70450：法师技能线、等级和材料独立于其他客户端。
-- 达拉然只有联盟传送；学习地点尚未确认，不推断训练师。
local MAGE_DESTINATIONS = {
    {city = "stormwind", faction = "Alliance", teleport = 3561, portal = 10059, teleportLevel = 20, portalLevel = 40},
    {city = "ironforge", faction = "Alliance", teleport = 3562, portal = 11416, teleportLevel = 20, portalLevel = 40},
    {city = "darnassus", faction = "Alliance", teleport = 3565, portal = 11419, teleportLevel = 30, portalLevel = 50},
    {city = "orgrimmar", faction = "Horde", teleport = 3567, portal = 11417, teleportLevel = 20, portalLevel = 40},
    {city = "undercity", faction = "Horde", teleport = 3563, portal = 11418, teleportLevel = 20, portalLevel = 40},
    {city = "thunder_bluff", faction = "Horde", teleport = 3566, portal = 11420, teleportLevel = 30, portalLevel = 50},
    {city = "dalaran", faction = "Alliance", teleport = 1297659, teleportLevel = 50},
}
local CLASS_SPELLS = {
    DRUID = {18960},
    SHAMAN = {556},
}

local function Remaining(info, minDuration)
    if not info then return nil end
    local start, duration, enabled = info.startTime, info.duration, info.isEnabled
    if Security.IsSecretValue(start) or Security.IsSecretValue(duration) or Security.IsSecretValue(enabled) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" or enabled == false or enabled == 0 then return nil end
    -- 与其他客户端的炉石显示一致：按总时长过滤公共 CD，保留真实冷却最后几秒。
    if minDuration and duration <= minDuration then return 0 end
    return math.max(0, math.ceil(start + duration - Combat.GetTime()))
end

local function TimeText(seconds)
    if seconds >= 86400 then return string.format("%dd", math.ceil(seconds / 86400)) end
    if seconds >= 3600 then return string.format("%dh", math.ceil(seconds / 3600)) end
    if seconds >= 60 then return string.format("%dm", math.ceil(seconds / 60)) end
    return string.format("%ds", seconds)
end

function Module:OnInitialize()
    self.runtimeAttached = false
    self.menuCleanupOwner = {}
    self.menuCleanupCallback = function() self:FinishMenuCleanup() end
end

function Module:CancelTimers()
    if self.refreshTimer then self.refreshTimer:Cancel(); self.refreshTimer = nil end
    if self.cooldownTimer then self.cooldownTimer:Cancel(); self.cooldownTimer = nil end
end

function Module:RefreshCooldown(forceDisplay)
    if not self.frame then return end
    local active = self.runtimeAttached and self.frame:IsVisible()
    if not active and not forceDisplay then return end
    local count = Item.GetCount(HEARTHSTONE)
    local owned = not Security.IsSecretValue(count) and type(count) == "number" and count > 0
    local seconds = owned and Remaining(Item.GetCooldown(HEARTHSTONE), 2) or nil
    self.remaining, self.hasHearthstone = seconds, owned
    local text = self.bindLocation or L["teleports.action.hearthstone"]
    local cooling = seconds ~= nil and seconds > 0
    if cooling then text = "|cffff0000" .. TimeText(seconds) .. "|r" end
    if self.cooling ~= cooling then
        self.cooling = cooling
        self.frame.text:SetJustifyH(cooling and "CENTER" or "LEFT")
    end
    if self.renderedText ~= text then self.frame.text:SetText(text); self.renderedText = text end
    if self.hovered then self:OnEnter(self.frame.actionHost or self.frame) end
    if active and cooling then
        if not self.cooldownTimer then self.cooldownTimer = C_Timer.NewTimer(1, self.cooldownCallback) end
    elseif self.cooldownTimer then
        self.cooldownTimer:Cancel(); self.cooldownTimer = nil
    end
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end
    if not self.frame then return end
    if Security.InCombatLockdown() then self.needsUpdate = true; self:RefreshCooldown(); return end
    self.needsUpdate = nil
    self.bindLocation = GetBindLocation() or L["teleports.action.hearthstone"]
    -- 以地点名确定稳定宽度，冷却仅替换文字；隐藏视图和设计预览也写入真实状态。
    Info.Display(self, self.bindLocation, Item.GetIcon(HEARTHSTONE) or 134414)
    self.renderedText = nil
    self:RefreshCooldown(true)
end

function Module:Refresh(event)
    if not self.runtimeAttached then return end
    if event == "HEARTHSTONE_BOUND" or event == "YUI_WORLD_READY" or event == "PLAYER_REGEN_ENABLED" then self.needsUpdate = true end
    if event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "YUI_WORLD_READY" then self.menuNeedsRefresh = true end
    if event == "BAG_UPDATE_DELAYED" then self.reagentsNeedRefresh = true end
    if not self.refreshTimer then self.refreshTimer = C_Timer.NewTimer(0, self.refreshCallback) end
end

function Module:HideMenu()
    if self.menu and not Security.InCombatLockdown() then self.menu:Hide() end
end

function Module:EnsureMenu()
    if not self.menu then
        self.menu = GUI:CreateFrame(self.frame, {template = "SecureHandlerStateTemplate"})
        self.menu:SetFrameStrata("FULLSCREEN_DIALOG")
        self.menu:SetClampedToScreen(true)
        GUI:CreateBackdrop(self.menu, {surface = "color.surface.popup", border = "color.popup.border",
            nativeFrameBorder = true, nativeFrameBorderStyle = "tooltip"})
        self.menu.buttons = {}
        self.menu.mageButtons = {}
        self.menu.reagents = {}
        self.menu:SetAttribute("_onstate-visibility", [[if newstate == "hide" then self:Hide() end]])
        self.menu:SetScript("OnHide", function() self.menuTooltipButton = nil; YUI.HideGameTooltip() end)
    end
    if not self.menuDriver then
        RegisterStateDriver(self.menu, "visibility", "[combat] hide; 0")
        self.menuDriver = true
    end
    return self.menu
end

local function HideMageButtons(menu)
    for _, button in pairs(menu.mageButtons) do button:Hide() end
    for _, button in pairs(menu.reagents) do button:Hide() end
end

function Module:PopulateClassMenu(menu, learned)
    HideMageButtons(menu)
    for i, id in ipairs(learned) do
        local button = menu.buttons[i]
        if not button then
            button = YBar:CreateBarItem(menu, {variant = "bare", width = 260, height = 28, showIcon = true,
                iconSize = 20, iconPadding = 0, text = "", value = false, textColorKey = "color.ybar.text"})
            YBar:CreateActionHost(button, {
                onEnter = function(host, owner)
                    GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(owner.spellID)
                    GameTooltip:Show()
                end,
                onLeave = function() YUI.HideGameTooltip() end,
                afterClick = function() self:HideMenu() end,
            })
            menu.buttons[i] = button
        end
        button.spellID = id
        YBar:SetIconSlotTexture(button.iconSlot, Spell.GetTexture(id))
        local seconds = Remaining(Spell.GetCooldown(id))
        button.text:SetText(Spell.GetName(id) .. (seconds and seconds > 0 and ("  " .. TimeText(seconds)) or ""))
        button.actionHost:SetActions({left = {kind = "spell", spellID = id}})
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -8 - (i - 1) * 28)
        button:Show()
    end
    for i = #learned + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetSize(276, #learned * 28 + 16)
end

local function CreateMageIcon(parent)
    local button = GUI:CreateButtonFrame(parent)
    button:SetSize(MAGE_ICON_SIZE, MAGE_ICON_SIZE)
    button.iconSlot, button.icon = YBar:CreateIconSlot(button, {
        size = MAGE_ICON_SIZE, shape = "square", padding = 0,
    })
    local iconFrame = button.iconSlot or button.icon
    iconFrame:SetAllPoints()
    button.text = YBar:CreateThemedText(button.iconSlot or button, {
        fontPath = STANDARD_TEXT_FONT, fontSize = 12, fontFlags = "OUTLINE",
        colorKey = "color.ybar.text", justifyH = "CENTER", shadow = true,
    })
    button.text:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    button.text:SetWidth(MAGE_ICON_SIZE)
    return button
end

function Module:OnMageSpellEnter(host, button)
    if not self.runtimeAttached or Security.InCombatLockdown() then return end
    self.menuTooltipButton = button
    YBar:SetIconSlotState(button.iconSlot, "hover")
    GameTooltip:SetOwner(host, "ANCHOR_RIGHT")
    if button.isKnown then
        GameTooltip:SetSpellByID(button.spellID)
    else
        local city = button.destination.city
        local key = city == "dalaran" and "teleports.forever.trainer_unknown" or ("teleports.forever.trainer_" .. city)
        local r, g, b = GUI:GetColor("color.tooltip.body")
        GameTooltip:SetText(Spell.GetName(button.spellID) or L["teleports.menu.city_" .. city], r, g, b)
        local sr, sg, sb = GUI:GetColor("color.tooltip.secondary")
        local wr, wg, wb = GUI:GetColor("color.tooltip.warning")
        GameTooltip:AddDoubleLine(L["teleports.tooltip.unlearned"],
            string.format(L["teleports.forever.learn_level"], button.requiredLevel), sr, sg, sb, wr, wg, wb)
        GameTooltip:AddLine(L[key], sr, sg, sb, true)
    end
    GameTooltip:Show()
end

function Module:OnMageSpellLeave(button)
    self.menuTooltipButton = nil
    if not Security.InCombatLockdown() then
        YBar:SetIconSlotState(button.iconSlot, "normal")
    end
    YUI.HideGameTooltip()
end

function Module:EnsureMageSpellButton(menu, destination, id, level)
    local button = menu.mageButtons[id]
    if button then return button end
    button = CreateMageIcon(menu)
    button.spellID, button.destination, button.requiredLevel = id, destination, level
    button.text:SetText(L["teleports.menu.city_" .. destination.city])
    YBar:CreateActionHost(button, {
        onEnter = function(host, owner) self:OnMageSpellEnter(host, owner) end,
        onLeave = function(_, owner) self:OnMageSpellLeave(owner) end,
    })
    menu.mageButtons[id] = button
    return button
end

function Module:ApplyMageSpellButton(button, row, column)
    local known = Spell.IsKnown(button.spellID) and Spell.GetName(button.spellID) ~= nil or false
    if button.isKnown ~= known then
        button.isKnown = known
        button.actionHost:SetActions({left = known and {
            kind = "spell", spellID = button.spellID, afterClick = function() self:HideMenu() end,
        } or {kind = "noop"}})
    end
    local texture = Spell.GetTexture(button.spellID) or 134400
    if button.iconSlot then YBar:SetIconSlotTexture(button.iconSlot, texture)
    else button.icon:SetTexture(texture) end
    -- 未学习只去色，避免禁用态的透明度与遮罩叠加压暗。
    YBar:SetIconSlotState(button.iconSlot, "normal")
    button.icon:SetDesaturated(not known)
    button.icon:SetVertexColor(1, 1, 1)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", self.menu, "TOPLEFT", MAGE_PADDING + column * (MAGE_ICON_SIZE + MAGE_PADDING),
        -MAGE_PADDING - row * (MAGE_ICON_SIZE + MAGE_PADDING))
    button:Show()
end

function Module:EnsureReagentButton(menu, id, column, row)
    local button = menu.reagents[id]
    if not button then
        button = CreateMageIcon(menu)
        button.itemID = id
        button.text:ClearAllPoints()
        button.text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        button.text:SetJustifyH("RIGHT")
        button:SetScript("OnEnter", function(owner)
            if not self.runtimeAttached then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(owner.itemID)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() YUI.HideGameTooltip() end)
        menu.reagents[id] = button
    end
    local texture = Item.GetIcon(id) or 134400
    if button.iconSlot then YBar:SetIconSlotTexture(button.iconSlot, texture)
    else button.icon:SetTexture(texture) end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", MAGE_PADDING + column * (MAGE_ICON_SIZE + MAGE_PADDING),
        -MAGE_PADDING - row * (MAGE_ICON_SIZE + MAGE_PADDING))
    button:Show()
end

function Module:UpdateMageReagents()
    if not self.menu or not self.menu.isMage then return end
    for id, button in pairs(self.menu.reagents) do
        local count = Item.GetCount(id)
        if Security.IsSecretValue(count) or type(count) ~= "number" then count = nil end
        if button.count ~= count or not button.countRendered then
            button.count, button.countRendered = count, true
            button.text:SetText(count == nil and "--" or (count == 0 and "|cffff00000|r" or tostring(count)))
            button.icon:SetDesaturated(count == nil or count == 0)
        end
    end
end

function Module:PopulateMageMenu(menu)
    local faction = Unit.UnitFactionGroup("player")
    for _, button in ipairs(menu.buttons) do button:Hide() end
    HideMageButtons(menu)
    local row = 0
    for _, destination in ipairs(MAGE_DESTINATIONS) do
        if destination.faction == faction then
            if destination.portal then
                self:ApplyMageSpellButton(self:EnsureMageSpellButton(menu, destination, destination.portal, destination.portalLevel), row, 0)
            end
            self:ApplyMageSpellButton(self:EnsureMageSpellButton(menu, destination, destination.teleport, destination.teleportLevel), row, 1)
            row = row + 1
        end
    end
    if row == 0 then self:HideMenu(); return false end
    self:EnsureReagentButton(menu, PORTAL_RUNE, 0, row)
    self:EnsureReagentButton(menu, TELEPORT_RUNE, 1, row)
    self:UpdateMageReagents()
    menu:SetSize(MAGE_ICON_SIZE * 2 + MAGE_PADDING * 3, (row + 1) * (MAGE_ICON_SIZE + MAGE_PADDING) + MAGE_PADDING)
    if self.menuTooltipButton and self.menuTooltipButton:IsShown() then
        self:OnMageSpellEnter(self.menuTooltipButton.actionHost, self.menuTooltipButton)
    end
    return true
end

function Module:ShowMenu()
    if not self.runtimeAttached or Security.InCombatLockdown() then return end
    if self.menu and self.menu:IsShown() then self:HideMenu(); return end
    local class = Unit.GetClassToken("player")
    local learned
    if class == "MAGE" then
        local faction = Unit.UnitFactionGroup("player")
        if faction ~= "Alliance" and faction ~= "Horde" then return end
    else
        local spells = CLASS_SPELLS[class]
        if not spells then return end
        learned = {}
        for _, id in ipairs(spells) do
            if Spell.IsKnown(id) and Spell.GetName(id) then learned[#learned + 1] = id end
        end
        if #learned == 0 then return end
    end
    local menu = self:EnsureMenu()
    menu.isMage = class == "MAGE"
    self.menuNeedsRefresh, self.reagentsNeedRefresh = nil, nil
    if menu.isMage then self:PopulateMageMenu(menu) else self:PopulateClassMenu(menu, learned) end
    menu:ClearAllPoints()
    local _, y = self.frame:GetCenter()
    if y and y > UIParent:GetHeight() / 2 then menu:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", 0, -2)
    else menu:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 2) end
    self.hovered = false
    YUI.HideGameTooltip()
    menu:Show()
end

function Module:OnEnter(frame)
    if not self.runtimeAttached then return end
    self.hovered = true
    local anchor, offset = YUI.F:GetTooltipAnchor(frame)
    GameTooltip:SetOwner(frame, anchor, 0, offset)
    GameTooltip:ClearLines()
    GameTooltip:SetText(L["teleports.tooltip.title"])
    GameTooltip:AddLine(" ")
    local status = "|cff00ff00" .. LC["common.ready"] .. "|r"
    if not self.hasHearthstone then status = "|cffff0000" .. L["teleports.forever.missing"] .. "|r"
    elseif self.remaining == nil then status = "|cffff0000" .. L["teleports.tooltip.unavailable"] .. "|r"
    elseif self.remaining > 0 then status = "|cffff0000" .. TimeText(self.remaining) .. "|r" end
    GameTooltip:AddDoubleLine(string.format("|T%s:14|t %s", Item.GetIcon(HEARTHSTONE) or 134414,
        Item.GetNameByID(HEARTHSTONE) or L["teleports.action.hearthstone"]), status, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(self.bindLocation or "", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffffff" .. LC["common.left_click"] .. ": |r|cffffd100" .. L["teleports.action.hearthstone"] .. "|r")
    local class = Unit.GetClassToken("player")
    if class == "MAGE" or CLASS_SPELLS[class] then
        GameTooltip:AddLine("|cffffffff" .. LC["common.right_click"] .. ": |r|cffffd100" .. L["teleports.forever.class_menu"] .. "|r")
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff808080" .. LC["common.alt_left_click"] .. ": " .. LC["common.open_settings"] .. "|r")
    GameTooltip:Show()
end

function Module:OnLeave()
    self.hovered = false
    YUI.HideGameTooltip()
end

function Module:AttachRuntime()
    if not self.frame then return end
    self:CancelTimers()
    self.runtimeAttached = true
    YUI.Event:OffOwner(self.menuCleanupOwner)
    self.cooldownCallback = self.cooldownCallback or function() self.cooldownTimer = nil; self:RefreshCooldown() end
    self.refreshCallback = self.refreshCallback or function()
        self.refreshTimer = nil
        if not self.runtimeAttached then return end
        if self.needsUpdate then self:UpdateBarItem() else self:RefreshCooldown() end
        if self.menu and self.menu.isMage and self.menu:IsVisible() and not Security.InCombatLockdown() then
            if self.menuNeedsRefresh then self:PopulateMageMenu(self.menu)
            elseif self.reagentsNeedRefresh then self:UpdateMageReagents() end
            self.menuNeedsRefresh, self.reagentsNeedRefresh = nil, nil
        end
    end
    YUI.Event:OffOwner(self)
    for _, event in ipairs({"YUI_WORLD_READY", "HEARTHSTONE_BOUND", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP"}) do
        YUI.Event:On(event, "Refresh", self)
    end
    self:UpdateBarItem()
end

function Module:FinishMenuCleanup()
    if Security.InCombatLockdown() then return end
    YUI.Event:OffOwner(self.menuCleanupOwner)
    if self.runtimeAttached then return end
    self:HideMenu()
    if self.menuDriver then UnregisterStateDriver(self.menu, "visibility"); self.menuDriver = nil end
    if self.frame then self.frame:Hide() end
end

function Module:DetachRuntime()
    self.runtimeAttached = false
    YUI.Event:OffOwner(self)
    self:CancelTimers()
    self:OnLeave()
    self:HideMenu()
    if Security.InCombatLockdown() then
        YUI.Event:On("PLAYER_REGEN_ENABLED", self.menuCleanupCallback, self.menuCleanupOwner)
    else
        self:FinishMenuCleanup()
    end
end

function Module:CreateBarItem(parent)
    if Security.InCombatLockdown() then return self.frame end
    self:DetachRuntime()
    self.menu = nil
    self.cooling = nil
    self.text, self.icon, self.font, self.size, self.iconSize, self.width, self.chrome, self.shadow = nil, nil, nil, nil, nil, nil, nil, nil
    local frame = Info.Create(self, parent)
    frame:SetScript("OnClick", nil)
    local host = YBar:CreateActionHost(frame, {
        onEnter = function(h) YBar:OnModuleEnter(frame); self:OnEnter(h) end,
        onLeave = function() YBar:OnModuleLeave(frame); self:OnLeave() end,
    })
    host:SetActions({left = {kind = "item", item = "item:6948"},
        right = {kind = "custom", onClick = function() self:ShowMenu() end},
        altLeft = {kind = "custom", onClick = function()
            if self.runtimeAttached and not Security.InCombatLockdown() then YUI:OpenYBarModuleSettings(self.name) end
        end}})
    frame:HookScript("OnHide", function() self:CancelTimers(); self:OnLeave(); self:HideMenu() end)
    frame:HookScript("OnShow", function() if self.runtimeAttached then self:Refresh("YUI_WORLD_READY") end end)
    return frame
end

function Module:GetWidth() return self.width or 10 end
function Module:GetOptions() return Info.Options(self) end
Info.Register(Module)

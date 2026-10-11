local YUI = _G.YUI
local YBar, GUI = YUI.YBar, YUI.GUI2
local Info = YBar.InfoModule
local Item, Spell = YUI.API.Item, YUI.API.Spell
local Security, Combat = YUI.API.Security, YUI.API.Combat
local L, LC = YUI.Locale:Get("YBar"), YUI.Locale:Get("Core")
local Module = YBar.Module:New("Teleports")
local HEARTHSTONE = 6948

-- Forever 1.60.1.69913：SpellName / SkillLineAbility 联查；只展示实际已学技能。
local CLASS_SPELLS = {
    MAGE = {3561, 3562, 3565, 3567, 3566, 3563, 1297659, 10059, 11416, 11419, 11417, 11420, 11418},
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
    if not self.refreshTimer then self.refreshTimer = C_Timer.NewTimer(0, self.refreshCallback) end
end

function Module:HideMenu()
    if self.menu and not Security.InCombatLockdown() then self.menu:Hide() end
end

function Module:ShowMenu()
    if not self.runtimeAttached or Security.InCombatLockdown() then return end
    if self.menu and self.menu:IsShown() then self:HideMenu(); return end
    local spells = CLASS_SPELLS[YUI.API.Unit.GetClassToken("player")]
    if not spells then return end
    local learned = {}
    for _, id in ipairs(spells) do
        if Spell.IsKnown(id) and Spell.GetName(id) then learned[#learned + 1] = id end
    end
    if #learned == 0 then return end
    if not self.menu then
        self.menu = GUI:CreateFrame(self.frame, {template = "SecureHandlerStateTemplate"})
        self.menu:SetFrameStrata("FULLSCREEN_DIALOG")
        self.menu:SetClampedToScreen(true)
        GUI:CreateBackdrop(self.menu, {surface = "color.surface.popup", border = "color.popup.border",
            nativeFrameBorder = true, nativeFrameBorderStyle = "tooltip"})
        self.menu.buttons = {}
        self.menu:SetAttribute("_onstate-visibility", [[if newstate == "hide" then self:Hide() end]])
        self.menu:SetScript("OnHide", function() YUI.HideGameTooltip() end)
    end
    if not self.menuDriver then
        RegisterStateDriver(self.menu, "visibility", "[combat] hide; 0")
        self.menuDriver = true
    end
    local menu = self.menu
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
    menu:ClearAllPoints()
    local _, y = self.frame:GetCenter()
    if y and y > GetScreenHeight() / 2 then menu:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", 0, -2)
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
    if CLASS_SPELLS[YUI.API.Unit.GetClassToken("player")] then
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
    self.cooldownCallback = self.cooldownCallback or function() self.cooldownTimer = nil; self:RefreshCooldown() end
    self.refreshCallback = self.refreshCallback or function()
        self.refreshTimer = nil
        if not self.runtimeAttached then return end
        if self.needsUpdate then self:UpdateBarItem() else self:RefreshCooldown() end
    end
    YUI.Event:OffOwner(self)
    for _, event in ipairs({"YUI_WORLD_READY", "HEARTHSTONE_BOUND", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED"}) do
        YUI.Event:On(event, "Refresh", self)
    end
    self:UpdateBarItem()
end

function Module:DetachRuntime()
    self.runtimeAttached = false
    YUI.Event:OffOwner(self)
    self:CancelTimers()
    self:OnLeave()
    self:HideMenu()
    if self.menuDriver and not Security.InCombatLockdown() then
        UnregisterStateDriver(self.menu, "visibility"); self.menuDriver = nil
    end
    if self.frame and not Security.InCombatLockdown() then self.frame:Hide() end
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
    frame:HookScript("OnHide", function() self:CancelTimers(); self:OnLeave() end)
    frame:HookScript("OnShow", function() if self.runtimeAttached then self:Refresh("YUI_WORLD_READY") end end)
    return frame
end

function Module:GetWidth() return self.width or 10 end
function Module:GetOptions() return Info.Options(self) end
Info.Register(Module)

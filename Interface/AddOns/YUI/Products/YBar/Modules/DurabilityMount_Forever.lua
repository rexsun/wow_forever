local YUI = _G.YUI
local YBar = YUI.YBar
local Info, Item, Security = YBar.InfoModule, YUI.API.Item, YUI.API.Security
local Display = YBar.DurabilityDisplay
local L, LC = YUI.Locale:Get("YBar"), YUI.Locale:Get("Core")
local Module = YBar.Module:New("DurabilityMount")
local SLOTS = {1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18}
local ICON = "Interface\\Icons\\Trade_BlackSmithing"

local function Percent(value)
    local color = value < 30 and "ff3333" or (value < 60 and "ffcc33" or "ffffff")
    return string.format("|cff%s%d%%|r", color, math.floor(value))
end

function Module:OnInitialize()
    self.runtimeAttached = false
end

function Module:ReadDurability()
    self.slots = self.slots or {}
    local total, maximum, lowest, restricted = 0, 0, 100, false
    for _, slot in ipairs(SLOTS) do
        local current, max = Item.GetInventoryItemDurability(slot)
        if Security.IsSecretValue(current) or Security.IsSecretValue(max) then
            self.slots[slot] = nil
            restricted = true
        elseif type(current) == "number" and type(max) == "number" and max > 0 then
            local percent = math.max(0, math.min(100, current / max * 100))
            self.slots[slot] = percent
            total, maximum = total + current, maximum + max
            lowest = math.min(lowest, percent)
        else
            self.slots[slot] = nil
        end
    end
    -- 缺失/受限读数不伪装成 100%，平均值沿用现有模块的耐久总量加权口径。
    self.average = not restricted and maximum > 0 and total / maximum * 100 or nil
    self.lowest = not restricted and maximum > 0 and lowest or nil
    self.durabilityRestricted = restricted
end

function Module:GetReservedTextWidth(font, size, flags)
    local width, ready = Display.MeasureText(self, font, size, flags, Info.DB(self).displayMode, self.average, self.lowest)
    self.durabilityWidthReady = ready
    return width
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end
    if not self.frame then return end
    self:ReadDurability()
    local mode = Info.DB(self).displayMode or "lowest"
    local text = "--"
    if self.average then
        if mode == "average_lowest" then text = Percent(self.average) .. " " .. Percent(self.lowest)
        else text = Percent(mode == "average" and self.average or self.lowest) end
    end
    Info.Display(self, text, ICON)
    Display.UpdateRetry(self, (not self.average and not self.durabilityRestricted) or self.durabilityWidthReady == false)
    if self.hovered and self.runtimeAttached then self:OnEnter(self.frame) end
end

function Module:Refresh(event)
    if event == "YUI_WORLD_READY" and self.runtimeAttached then Display.BeginRetry(self) end
    if not self.runtimeAttached or self.refreshTimer then return end
    self.refreshTimer = C_Timer.NewTimer(0, self.refreshCallback)
end

function Module:AttachRuntime()
    if not self.frame then return end
    if not self.runtimeAttached then Display.BeginRetry(self) end
    self.runtimeAttached = true
    if not self.refreshCallback then
        local callback
        callback = function()
            if self.refreshCallback ~= callback then return end
            self.refreshTimer = nil
            if self.runtimeAttached then self:UpdateBarItem() end
        end
        self.refreshCallback = callback
    end
    YUI.Event:OffOwner(self)
    YUI.Event:On("YUI_WORLD_READY", "Refresh", self)
    YUI.Event:On("UPDATE_INVENTORY_DURABILITY", "Refresh", self)
    YUI.Event:On("PLAYER_EQUIPMENT_CHANGED", "Refresh", self)
    YUI.Event:On("PLAYER_REGEN_ENABLED", "Refresh", self)
    self:UpdateBarItem()
end

function Module:DetachRuntime()
    self.runtimeAttached = false
    Display.StopRetry(self)
    YUI.Event:OffOwner(self)
    if self.refreshTimer then self.refreshTimer:Cancel(); self.refreshTimer = nil end
    self.refreshCallback = nil
    self:OnLeave()
    if self.frame then self.frame:Hide() end
end

function Module:OnEnter(frame)
    if not self.runtimeAttached then return end
    self.hovered = true
    local anchor, offset = YUI.F:GetTooltipAnchor(frame)
    GameTooltip:SetOwner(frame, anchor, 0, offset)
    GameTooltip:ClearLines()
    GameTooltip:SetText(L["durability.tooltip.title"])
    GameTooltip:AddLine(" ")
    for _, slot in ipairs(SLOTS) do
        local percent = self.slots and self.slots[slot]
        if percent then
            local link = Item.GetInventoryItemLink("player", slot)
            local icon = Item.GetInventoryItemTexture("player", slot) or ICON
            GameTooltip:AddDoubleLine(string.format("|T%s:14|t %s", icon, link or "--"), Percent(percent), 1, 1, 1, 1, 1, 1)
        end
    end
    if self.average then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["durability.display.average"], Percent(self.average), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["durability.display.lowest"], Percent(self.lowest), 1, 1, 1, 1, 1, 1)
    else
        GameTooltip:AddLine("--", 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff808080" .. LC["common.alt_left_click"] .. ": " .. LC["common.open_settings"] .. "|r")
    GameTooltip:Show()
end

function Module:OnLeave()
    self.hovered = false
    if GameTooltip:GetOwner() == self.frame then YUI.HideGameTooltip() end
end

function Module:CreateBarItem(parent)
    self:DetachRuntime()
    self.text, self.icon, self.font, self.size, self.iconSize, self.width, self.chrome, self.shadow = nil, nil, nil, nil, nil, nil, nil, nil
    return Info.Create(self, parent)
end

function Module:GetWidth() return self.width or 10 end
function Module:GetOptions()
    local options = Info.Options(self)
    options[#options + 1] = {type = "dropdown", label = LC["common.display_mode"], width = 220,
        options = {{text=L["durability.display.lowest"],value="lowest"},
            {text=L["durability.display.average"],value="average"},
            {text=L["durability.display.average_lowest"],value="average_lowest"}},
        get = function() return Info.DB(self).displayMode or "lowest" end,
        set = function(value) Info.DB(self).displayMode = value; self:UpdateBarItem() end}
    return options
end
Info.Register(Module)

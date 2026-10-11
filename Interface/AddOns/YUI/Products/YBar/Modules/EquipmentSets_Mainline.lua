local YUI = _G.YUI
local YBar = YUI.YBar
local Info, L = YBar.InfoModule, YUI.Locale:Get("YBar")
local Module = YBar.Module:New("EquipmentSets")
Module.defaultIcon = 135026
Module.CreateBarItem, Module.GetOptions = Info.Create, Info.Options

function Module:Resolve()
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    table.sort(ids)
    local selected
    for _, id in ipairs(ids) do
        local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(id)
        if equipped and (not selected or id == self.lastSuccessful) then selected = id end
    end
    return selected
end

function Module:Select(id)
    if InCombatLockdown() then YUI:Print(L["equipment.combat"]); return end
    local name, _, _, _, _, _, _, lost = C_EquipmentSet.GetEquipmentSetInfo(id)
    if not name or lost > 0 then YUI:Print(L["equipment.missing"]); return end
    YBar.TeleportRestore:Cancel()
    self.pendingID = id
    local ok = C_EquipmentSet.UseEquipmentSet(id)
    if not ok then self.pendingID = nil; YUI:Print(L["equipment.failed"]) end
    self:OnEvent()
end

function Module:OnEvent(event, success, id)
    if self.pendingID then
        local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(self.pendingID)
        if equipped then self.lastSuccessful = self.pendingID; self.pendingID = nil
        elseif event == "EQUIPMENT_SWAP_FINISHED" then
            self.pendingID = nil
            if not success then YUI:Print(L["equipment.failed"]) end
        end
    end
    self:UpdateBarItem()
end
function Module:UpdateBarItem()
    local id = self:Resolve()
    local name, icon
    if id then name, icon = C_EquipmentSet.GetEquipmentSetInfo(id) end
    Info.Display(self, name or L["equipment.custom"], icon or self.defaultIcon)
end
function Module:AttachRuntime()
    if self.active then return end
    self.active = true
    for _, event in ipairs({"EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SWAP_FINISHED", "YUI_WORLD_READY"}) do
        YUI.Event:On(event, "OnEvent", self)
    end
end
function Module:DetachRuntime()
    self.active, self.pendingID, self.lastSuccessful = false, nil, nil
    YUI.Event:OffOwner(self)
    if self.openMenu then
        local _, anchor = self.openMenu:GetPoint(1)
        if anchor == self.frame then self.openMenu:Hide() end
        self.openMenu = nil
    end
    if self.frame and GameTooltip:GetOwner() == self.frame then YUI.HideGameTooltip() end
end
function Module:OnDBReload() self:DetachRuntime(); if YBar:IsSubModuleEnabled(self.name) then self:AttachRuntime() end end
function Module:GetWidth() return self.width or 100 end
function Module:OnEnter() Info.Tooltip(self, L["ybar.module.equipment"], L["equipment.help"]) end
function Module:OnClick(frame, button)
    if button == "RightButton" then
        if InCombatLockdown() then YUI:Print(L["equipment.combat"]); return end
        ToggleCharacter("PaperDollFrame")
        if PaperDollFrame_SetSidebar then PaperDollFrame_SetSidebar(PaperDollFrame, 3) end
        return
    end
    if InCombatLockdown() then YUI:Print(L["equipment.combat"]); return end
    local items = {}
    local ids = C_EquipmentSet.GetEquipmentSetIDs()
    table.sort(ids)
    for _, id in ipairs(ids) do
        local name, icon, _, equipped, _, _, _, lost = C_EquipmentSet.GetEquipmentSetInfo(id)
        local setID = id
        items[#items + 1] = { text = (equipped and "✓ " or "") .. name .. (lost > 0 and (" — " .. L["equipment.missing"]) or ""),
            icon = icon, onClick = function() Module:Select(setID) end }
    end
    if #items == 0 then Info.Tooltip(self, L["ybar.module.equipment"], L["equipment.empty"]); return end
    YBar:CreatePopIconMenu(frame, items, {columns = 1, colWidth = 220, gui2 = true})
    self.openMenu = YBar.GUI2PopIconMenu or YBar.PopIconMenu
end
Info.Register(Module)

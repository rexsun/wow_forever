local ADDON_NAME, addonTable = ...
local state = _G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
if state and not state.productEnabled then return end
local YUI = _G.YUI or addonTable
local A = YUI and YUI.AddonAssistant
if not A then return end
local System = YUI.API.System
local Entry = { buttons=setmetatable({}, {__mode="k"}), hooked=setmetatable({}, {__mode="k"}) }
A.GameMenu = Entry

-- Compatibility policy: an enabled or still-loaded manager retains its native entry.
local competingAddon = "SimpleAddonManager"
local function yieldsToManager()
    if not System.DoesAddOnExist(competingAddon) then return false end
    return System.GetAddOnEnabledState(competingAddon)~=false or System.GetAddOnLoadedState(competingAddon)==true
end

function Entry:HasPriorityManager()
    return yieldsToManager()
end

local function onClick(button, ...)
    local original=Entry.buttons[button]
    if not Entry.active or not A.Runtime.active or InCombatLockdown() or yieldsToManager() then
        if original then return original(button, ...) end
        return
    end
    local menu=button:GetParent()
    if menu and menu.CloseMenu then menu:CloseMenu() end
    A.View:Show()
end

function Entry:Restore()
    if InCombatLockdown() then return end
    for button, original in pairs(self.buttons) do
        if button:GetScript("OnClick")==onClick then button:SetScript("OnClick",original) end
        self.buttons[button]=nil
    end
end

function Entry:Refresh(menu)
    if InCombatLockdown() then return end
    self:Restore()
    if not self.active or yieldsToManager() then return end
    menu=menu or _G.GameMenuFrame
    if not menu or not menu:IsShown() or not menu.buttonPool then return end
    for button in menu.buttonPool:EnumerateActive() do
        if button:GetText()==_G.ADDONS and button:IsEnabled() then
            local original=button:GetScript("OnClick")
            if original and original~=onClick then
                self.buttons[button]=original
                button:SetScript("OnClick",onClick)
            end
        end
    end
end

function Entry:Attach()
    local menu=_G.GameMenuFrame
    if not menu or type(menu.InitButtons)~="function" or type(hooksecurefunc)~="function" then return end
    if not self.hooked[menu] then
        self.hooked[menu]=true
        -- One inert-when-disabled post-hook; rebuilding a pooled menu resets its scripts.
        hooksecurefunc(menu,"InitButtons",function(owner)
            if Entry.active then Entry:Refresh(owner) end
        end)
        menu:HookScript("OnHide",function() Entry:Restore() end)
    end
    self:Refresh(menu)
end

function Entry:Enable()
    if self.active then return end
    self.active=true
    YUI.Event:OffOwner(self)
    YUI.Event:On("ADDON_LOADED",function(_,name)
        if name=="Blizzard_GameMenu" or name==competingAddon then self:Attach() end
        if name==competingAddon then A.Runtime:Evaluate() end
    end,self)
    YUI.Event:On("PLAYER_REGEN_ENABLED",function() self:Attach() end,self)
    self:Attach()
end

function Entry:Disable()
    self.active=false
    YUI.Event:OffOwner(self)
    if InCombatLockdown() and next(self.buttons) then
        YUI.Event:On("PLAYER_REGEN_ENABLED",function()
            self:Restore(); YUI.Event:OffOwner(self)
        end,self)
    else self:Restore() end
end

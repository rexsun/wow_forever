local YUI = _G.YUI
local YBar = YUI and YUI.YBar
if not YBar or not YUI.IsRetail then return end

local Guard = {
    active = false,
    generation = 0,
    repairQueued = false,
    combatPending = false,
    registryRegistered = false,
    hookInstalled = false,
    latestHouseList = nil,
    queueCount = 0,
    repairCount = 0,
    failureCount = 0,
    lastReason = nil,
    lastError = nil,
}

local DASHBOARD_ADDON = "Blizzard_HousingDashboard"
local HOUSE_LIST_EVENT = "HouseDropdown.HouseListUpdated"

local function IsInCombat()
    local security = YUI.API and YUI.API.Security
    local checker = security and security.InCombatLockdown or _G.InCombatLockdown
    if type(checker) ~= "function" then return false end

    local ok, result = pcall(checker)
    return ok and result == true
end

local function IsDashboardLoaded()
    if _G.HousingDashboardFrame then return true end

    local addons = _G.C_AddOns
    if type(addons) == "table" and type(addons.IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(addons.IsAddOnLoaded, DASHBOARD_ADDON)
        return ok and loaded == true
    end

    return false
end

function Guard:InstallOnShowHook()
    if self.hookInstalled then return true end

    local frame = _G.HousingDashboardFrame
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then
        return false
    end

    local ok = pcall(frame.HookScript, frame, "OnShow", function()
        if Guard.active then
            Guard:QueueRepair("dashboard-show")
        end
    end)
    if not ok then return false end

    self.hookInstalled = true
    return true
end

function Guard:GetRepairState()
    local frame = _G.HousingDashboardFrame
    local dropdown = type(frame) == "table" and frame.HouseDropdown or nil
    local houseInfo = type(frame) == "table" and frame.HouseInfoContent or nil
    local content = type(houseInfo) == "table" and houseInfo.ContentFrame or nil
    if type(dropdown) ~= "table" or type(houseInfo) ~= "table" or type(content) ~= "table" then
        return nil, "dashboard-unavailable"
    end

    local dropdownList = dropdown.playerHouseList
    if type(dropdownList) ~= "table" then
        return nil, "waiting-house-list"
    end

    local houseList = self.latestHouseList
    if type(houseList) ~= "table" or houseList ~= dropdownList then
        houseList = dropdownList
    end

    local initiatives = content.InitiativesFrame
    local upgrade = content.HouseUpgradeFrame
    if type(initiatives) ~= "table" or type(upgrade) ~= "table" then
        return nil, "dashboard-structure-changed"
    end

    local hasHouses = #houseList > 0
    local incomplete = initiatives.playerHouseList ~= houseList
        or upgrade.houseList ~= houseList
        or (hasHouses and content.tabsInitialized ~= true)
    if not incomplete then
        return nil, "healthy"
    end

    return {
        dropdown = dropdown,
        houseInfo = houseInfo,
        houseList = houseList,
    }, "incomplete"
end

function Guard:RunRepair(reason)
    if not self.active then return false, "inactive" end
    if IsInCombat() then
        self.combatPending = true
        self.lastReason = "combat-deferred"
        return false, "combat"
    end

    self.combatPending = false
    local state, status = self:GetRepairState()
    self.lastReason = status or reason
    if not state then return false, status end

    local update = state.houseInfo.OnHouseListUpdated
    if type(update) ~= "function" then
        self.failureCount = self.failureCount + 1
        self.lastError = "missing OnHouseListUpdated"
        return false, "unsupported"
    end

    local ok, err = pcall(update, state.houseInfo, state.houseList)
    if not ok then
        self.failureCount = self.failureCount + 1
        self.lastError = tostring(err)
        return false, "update-failed"
    end

    self.repairCount = self.repairCount + 1
    self.lastReason = reason or "repaired"
    self.lastError = nil

    local selectedHouseID = state.dropdown.selectedHouseID
    local selectHouse = state.houseInfo.OnHouseSelected
    if type(selectedHouseID) == "number"
        and state.houseList[selectedHouseID] ~= nil
        and type(selectHouse) == "function"
    then
        local selected, selectError = pcall(selectHouse, state.houseInfo, selectedHouseID)
        if not selected then
            self.failureCount = self.failureCount + 1
            self.lastError = tostring(selectError)
            return true, "selection-failed"
        end
    end

    return true, "repaired"
end

function Guard:QueueRepair(reason)
    if not self.active or self.repairQueued then return false end

    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then
        return false
    end

    self.repairQueued = true
    self.queueCount = self.queueCount + 1
    local generation = self.generation
    timer.After(0, function()
        if Guard.generation ~= generation or not Guard.active then return end
        Guard.repairQueued = false
        Guard:RunRepair(reason)
    end)
    return true
end

function Guard:OnHouseListUpdated(houseList)
    if not self.active or type(houseList) ~= "table" then return end

    self.latestHouseList = houseList
    self:QueueRepair("house-list-updated")
end

function Guard:OnRuntimeEvent(event, ...)
    if not self.active then return end

    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == DASHBOARD_ADDON then
            self:InstallOnShowHook()
            self:QueueRepair("dashboard-loaded")
        end
    elseif event == "PLAYER_REGEN_ENABLED" and self.combatPending then
        self.combatPending = false
        self:QueueRepair("combat-ended")
    end
end

function Guard:RegisterRuntimeCallbacks()
    local registry = _G.EventRegistry
    if not self.registryRegistered
        and type(registry) == "table"
        and type(registry.RegisterCallback) == "function"
    then
        local ok = pcall(registry.RegisterCallback, registry, HOUSE_LIST_EVENT, self.OnHouseListUpdated, self)
        self.registryRegistered = ok
    end

    local event = YUI.Event
    if type(event) == "table" and type(event.On) == "function" then
        if type(event.OffOwner) == "function" then
            event:OffOwner(self)
        end
        event:On("ADDON_LOADED", "OnRuntimeEvent", self, {
            moduleId = "ybar",
            traceName = "YBar:HousingDashboardGuard:ADDON_LOADED",
        })
        event:On("PLAYER_REGEN_ENABLED", "OnRuntimeEvent", self, {
            moduleId = "ybar",
            traceName = "YBar:HousingDashboardGuard:PLAYER_REGEN_ENABLED",
        })
    end
end

function Guard:Enable()
    if self.active then return end

    self.active = true
    self.generation = self.generation + 1
    self.repairQueued = false
    self.combatPending = false
    self:RegisterRuntimeCallbacks()

    if IsDashboardLoaded() then
        self:InstallOnShowHook()
        self:QueueRepair("enable")
    end
end

function Guard:Disable()
    if not self.active and not self.registryRegistered then return end

    self.active = false
    self.generation = self.generation + 1
    self.repairQueued = false
    self.combatPending = false
    self.latestHouseList = nil

    local registry = _G.EventRegistry
    if self.registryRegistered
        and type(registry) == "table"
        and type(registry.UnregisterCallback) == "function"
    then
        pcall(registry.UnregisterCallback, registry, HOUSE_LIST_EVENT, self)
    end
    self.registryRegistered = false

    local event = YUI.Event
    if type(event) == "table" and type(event.OffOwner) == "function" then
        event:OffOwner(self)
    end
end

YBar.HousingDashboardGuard = Guard

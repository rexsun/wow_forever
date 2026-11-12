local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Drivers = {}
YAB.Drivers = Drivers

Drivers.secureQueue = Drivers.secureQueue or {}
Drivers.registered = Drivers.registered or {}
Drivers.visibilityDrivers = Drivers.visibilityDrivers or setmetatable({}, { __mode = "k" })
Drivers.mainPagingHooks = Drivers.mainPagingHooks or setmetatable({}, { __mode = "k" })
Drivers.mainPagingDrivers = Drivers.mainPagingDrivers or setmetatable({}, { __mode = "k" })
Drivers.mainPagingAuraPages = Drivers.mainPagingAuraPages or setmetatable({}, { __mode = "k" })
Drivers.flushExecuted = Drivers.flushExecuted or 0
Drivers.flushErrors = Drivers.flushErrors or 0

local function InCombat()
    return YAB.Adapter and YAB.Adapter:InCombat()
end

local function MainPagingOnAttributeChanged(holder, name)
    if name ~= "state-page" or Drivers.mainPagingHooks[holder] ~= true then return end
    local manager = YAB.BarManager
    if not (manager and manager.runtimeActive == true and manager.QueueMainPageIdentity) then return end
    manager:QueueMainPageIdentity("secure-state-page")
end

function Drivers:Queue(reason, fn, ...)
    if type(fn) ~= "function" then return false end
    local item = { reason = reason or "secure", fn = fn, n = select("#", ...), args = { ... } }
    self.secureQueue[#self.secureQueue + 1] = item
    YAB.lastSecureQueueReason = item.reason
    return true
end

function Drivers:RunOrQueue(reason, fn, ...)
    if InCombat() then
        return self:Queue(reason, fn, ...)
    end
    return fn(...)
end

function Drivers:Flush()
    if InCombat() then return false, 0, 0 end
    local queue = self.secureQueue
    local count = #queue
    if count == 0 then return true, 0, 0 end
    self.secureQueue = {}
    local failed = 0
    for index = 1, count do
        local item = queue[index]
        local ok = pcall(item.fn, unpack(item.args, 1, item.n))
        if not ok then
            failed = failed + 1
        end
    end
    self.flushExecuted = (self.flushExecuted or 0) + count
    self.flushErrors = (self.flushErrors or 0) + failed
    return failed == 0, count, failed
end

function Drivers:RegisterMainPaging(holder, buttons, driver)
    if not holder or not RegisterStateDriver then return false end
    return self:RunOrQueue("main paging", function()
        if InCombat() then return false end
        local hookState = self.mainPagingHooks[holder]
        if hookState == nil then
            if not holder.HookScript then return false end
            holder:HookScript("OnAttributeChanged", MainPagingOnAttributeChanged)
        end
        self.mainPagingHooks[holder] = true
        for i, button in ipairs(buttons or {}) do
            holder:SetFrameRef("button" .. i, button)
        end
        local actionGridRoot = YAB.SecureFactory and YAB.SecureFactory:CreateRoot()
        if actionGridRoot then
            holder:SetFrameRef("actionGridRoot", actionGridRoot)
        end
        holder:SetAttribute("_onstate-page", [[
            local formPage = type(newstate) == "string"
                and tonumber(newstate:match("^form(%d+)$") or newstate:match("^aura(%d+)$")) or nil
            local page = tonumber(newstate) or formPage
            if not page then
                local currentPage = tonumber(GetActionBarPage and GetActionBarPage() or 1) or 1
                page = currentPage
                if HasVehicleActionBar and HasVehicleActionBar() then
                    page = GetVehicleBarIndex and GetVehicleBarIndex() or page
                elseif HasOverrideActionBar and HasOverrideActionBar() then
                    page = GetOverrideBarIndex and GetOverrideBarIndex() or page
                elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                    page = GetTempShapeshiftBarIndex and GetTempShapeshiftBarIndex() or page
                elseif HasBonusActionBar and HasBonusActionBar() and currentPage == 1 then
                    page = GetBonusBarIndex and GetBonusBarIndex() or page
                end
            end
            page = tonumber(page) or 1
            local actionGridRoot = self:GetFrameRef("actionGridRoot")
            local gridActive = actionGridRoot
                and actionGridRoot:GetAttribute("yab-action-grid-active") == true
            local formFallback = formPage and true or nil
            for i = 1, 12 do
                local button = self:GetFrameRef("button" .. i)
                if button then
                    if button:GetAttribute("yab-form-page-fallback") ~= formFallback then
                        button:SetAttribute("yab-form-page-fallback", formFallback)
                    end
                    local slot = ((page - 1) * 12) + i
                    button:SetAttribute("action", slot)
                    button:SetAttribute("action1", slot)
                    button:SetAttribute("action2", slot)
                    button:SetAttribute("actionpage", page)
                    if button:GetAttribute("yab-action-active") == true then
                        local shouldShow = button:GetAttribute("yab-hide-empty") ~= true
                            or gridActive
                            or HasAction(slot)
                        if shouldShow ~= button:IsShown() then
                            if shouldShow then button:Show(true) else button:Hide(true) end
                        end
                    end
                    local pressAndHold = false
                    if GetActionInfo and IsPressHoldReleaseSpell then
                        local actionType, id, subType = GetActionInfo(slot)
                        local spellID = nil
                        if actionType == "spell" then
                            spellID = id
                        elseif actionType == "macro" and subType == "spell" then
                            spellID = id
                        end
                        pressAndHold = spellID and IsPressHoldReleaseSpell(spellID) == true or false
                    end
                    button:SetAttribute("pressAndHoldAction", pressAndHold)
                    button:SetAttribute("typerelease", "actionrelease")
                end
            end
        ]])
        driver = driver or (YAB.Adapter and YAB.Adapter:BuildMainPageDriver() or "1")
        if YAB.Client and YAB.Client.formPagingFallbacks and holder.GetAttribute
            and holder:GetAttribute("state-page") ~= nil then
            -- Native unregister retains the state. Reapply it to new/reused button refs OOC.
            local clearState = holder.SetAttributeNoHandler or holder.SetAttribute
            clearState(holder, "state-page", nil)
        end
        RegisterStateDriver(holder, "page", driver)
        self.mainPagingDrivers[holder] = driver
        self.mainPagingAuraPages[holder] = YAB.Adapter and YAB.Adapter.GetFormAuraFallbackPage
            and YAB.Adapter:GetFormAuraFallbackPage() or nil
        self.mainPagingPolicies = self.mainPagingPolicies or setmetatable({}, { __mode = "k" })
        self.mainPagingPolicies[holder] = YAB.Adapter and YAB.Adapter.IsFormPagingEnabled
            and YAB.Adapter:IsFormPagingEnabled() or false
        self.registered[holder] = self.registered[holder] or {}
        self.registered[holder].page = true
        return true
    end)
end

function Drivers:RegisterVisibility(frame, driver)
    if not frame or not RegisterStateDriver or type(driver) ~= "string" then return false end
    if self.visibilityDrivers and self.visibilityDrivers[frame] == driver then return true end
    return self:RunOrQueue("visibility", function()
        if InCombat() then return false end
        if self.visibilityDrivers and self.visibilityDrivers[frame] == driver then return true end
        RegisterStateDriver(frame, "visibility", driver)
        self.registered[frame] = self.registered[frame] or {}
        self.registered[frame].visibility = true
        self.visibilityDrivers = self.visibilityDrivers or setmetatable({}, { __mode = "k" })
        self.visibilityDrivers[frame] = driver
        return true
    end)
end

function Drivers:ClearFrame(frame)
    if not frame then return false end
    return self:RunOrQueue("clear driver", function()
        if InCombat() then return false end
        local attrs = self.registered[frame]
        if attrs and attrs.page and self.mainPagingHooks[frame] ~= nil then
            self.mainPagingHooks[frame] = false
            self.mainPagingDrivers[frame] = nil
            self.mainPagingAuraPages[frame] = nil
            if self.mainPagingPolicies then self.mainPagingPolicies[frame] = nil end
            for index = 1, 12 do
                local button = frame:GetFrameRef("button" .. index)
                if button and button:GetAttribute("yab-form-page-fallback") then
                    button:SetAttribute("yab-form-page-fallback", nil)
                end
            end
        end
        if attrs and UnregisterStateDriver then
            for attr in pairs(attrs) do
                pcall(UnregisterStateDriver, frame, attr)
            end
        end
        self.registered[frame] = nil
        if self.visibilityDrivers then
            self.visibilityDrivers[frame] = nil
        end
        return true
    end)
end

function Drivers:ClearAll()
    return self:RunOrQueue("clear all drivers", function()
        if InCombat() then return false end
        for frame in pairs(self.registered) do
            self:ClearFrame(frame)
        end
        self.registered = {}
        self.visibilityDrivers = setmetatable({}, { __mode = "k" })
        return true
    end)
end

function Drivers:SetAttribute(frame, attr, value)
    if not frame or not attr then return false end
    return self:RunOrQueue("set attribute", function()
        if InCombat() then return false end
        frame:SetAttribute(attr, value)
        return true
    end)
end

function Drivers:QueueSize()
    return #(self.secureQueue or {})
end

function Drivers:ResetStats()
    self.flushExecuted = 0
    self.flushErrors = 0
end

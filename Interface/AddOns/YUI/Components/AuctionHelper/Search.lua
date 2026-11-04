local _, ns = ...
ns = _G.YUI or ns

local GUI2 = ns.GUI2
local Search = {}
Search.__index = Search
ns.AuctionHelperSearch = Search

local WAIT_SECONDS = 5

function Search:RefreshTooltip(button)
    if button and button:IsVisible() and GameTooltip and GameTooltip:IsOwned(button) then
        local onEnter = button:GetScript("OnEnter")
        if onEnter then onEnter(button) end
    end
end

function Search:StopWaiting()
    self.pending = nil
    if self.timer then self.timer:Cancel(); self.timer = nil end
    ns.Event:OffOwner(self)
    if self.spinner then self.spinner:Hide() end
end

function Search:Cancel()
    local button = self.button
    self:StopWaiting()
    self.button, self.status = nil, nil
    if self.overlay then self.overlay:Hide() end
    self:RefreshTooltip(button)
end

function Search:SetStatus(status)
    self.status = status
    if not self.overlay then
        self.overlay = GUI2:CreateFrame(self.helper, { mouse = false })
        -- 原生模板自行播放/停止动画，避免每个物品常驻 OnUpdate。
        self.spinner = GUI2:CreateFrame(self.overlay, { template = "SpinnerTemplate", mouse = false })
        self.spinner:SetSize(24, 24)
        self.spinner:SetPoint("CENTER")
        self.warning = GUI2:CreateTexture(self.overlay, { layer = "OVERLAY" })
        self.warning:SetAtlas("Professions_Icon_Warning")
        self.warning:SetSize(14, 12)
        self.warning:SetPoint("TOPRIGHT", 1, -1)
    end
    self.overlay:SetParent(self.button)
    self.overlay:ClearAllPoints()
    self.overlay:SetAllPoints(self.button)
    self.overlay:SetFrameLevel(self.button:GetFrameLevel() + 1)
    self.spinner:SetShown(status == "loading")
    self.warning:SetShown(status ~= "loading")
    self.overlay:Show()
    self:RefreshTooltip(self.button)
end

function Search:AddTooltip(button, tooltip)
    if self.button == button and self.status then
        local L = ns.Locale:Get("AuctionHelper")
        tooltip:AddLine(L["search." .. self.status], 1, 0.82, 0, true)
    end
end

function Search:IsAvailable(button)
    local bar = self.auctionHouse.SearchBar
    return self.isEnabled() and self.helper:IsVisible() and self.auctionHouse:IsVisible()
        and button:IsVisible() and bar and bar.SearchBox and bar.SearchButton
end

function Search:Submit(button, name)
    if not self:IsAvailable(button) then self:Cancel(); return end
    self:Cancel()
    self.searching = true
    if self.auctionHouse.SetDisplayMode then
        self.auctionHouse:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    end
    local bar = self.auctionHouse.SearchBar
    bar.SearchBox:SetText(name)
    bar.SearchButton:Click()
    self.searching = false
end

function Search:Resolve(request, failed)
    if self.pending ~= request then return end
    if not self:IsAvailable(request.button) then self:Cancel(); return end
    if GetTime() > request.deadline then
        self:StopWaiting()
        self:SetStatus("timeout")
        return
    end
    local name = ns.API.Item.GetNameByID(request.itemID)
    if type(name) == "string" and name ~= "" then
        self:Submit(request.button, name)
    elseif failed then
        self:StopWaiting()
        self:SetStatus("failed")
    end
end

function Search:Start(button)
    self:Cancel()
    if not self:IsAvailable(button) then return end
    local name = ns.API.Item.GetNameByID(button.primaryID)
    if type(name) == "string" and name ~= "" then
        self:Submit(button, name)
        return
    end

    self.button = button
    local request = { button = button, itemID = button.primaryID, deadline = GetTime() + WAIT_SECONDS }
    self.pending = request
    self:SetStatus("loading")
    ns.Event:On("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
        if itemID == request.itemID then self:Resolve(request, success == false) end
    end, self)
    ns.Event:On("AUCTION_HOUSE_CLOSED", function() self:Cancel() end, self)
    self.timer = C_Timer.NewTimer(WAIT_SECONDS, function()
        -- 超时即终止，避免 timer 延后到下一帧时重新发起过期搜索。
        if self.pending == request then
            self:StopWaiting()
            self:SetStatus("timeout")
        end
    end)
    -- 先建立状态与监听；已缓存的数据可能同步派发加载结果。
    C_Item.RequestLoadItemDataByID(request.itemID)
end

function Search:Create(helper, auctionHouse, isEnabled)
    local controller = setmetatable({ helper = helper, auctionHouse = auctionHouse, isEnabled = isEnabled }, self)
    local function CancelExternalSearch()
        if not controller.searching then controller:Cancel() end
    end
    local bar = auctionHouse.SearchBar
    bar.SearchBox:HookScript("OnTextChanged", CancelExternalSearch)
    bar.SearchBox:HookScript("OnEnterPressed", CancelExternalSearch)
    bar.SearchButton:HookScript("OnClick", CancelExternalSearch)
    -- 分类、收藏及其他入口也可能直接发送搜索，而不点击搜索按钮。
    hooksecurefunc(auctionHouse, "SendBrowseQuery", CancelExternalSearch)
    hooksecurefunc(auctionHouse, "SetDisplayMode", CancelExternalSearch)
    helper:HookScript("OnHide", function() controller:Cancel() end)
    return controller
end

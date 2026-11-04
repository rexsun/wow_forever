local _, ns = ...
ns = _G.YUI or ns
if not ns.IsRetail then return end

local GUI2 = ns.GUI2
local L = ns.Locale:Get("AuctionHelper")
local Tracker = {}
ns.AuctionHelperRecipeTracker = Tracker
local UNKNOWN_ICON = 134400
local CONTENT_TOP = 6

local function CompactQuantity(value, decimals)
    local divisor, suffix = 1, ""
    if value >= 1000000000 then divisor, suffix = 1000000000, "b"
    elseif value >= 1000000 then divisor, suffix = 1000000, "m"
    elseif value >= 1000 then divisor, suffix = 1000, "k" end
    if divisor == 1 then return tostring(value) end
    local result = string.format(decimals and "%.1f" or "%.0f", value / divisor)
    return (result:gsub("%.0$", "")) .. suffix
end

function Tracker:PaintQuantity(button)
    local text = button.quantityText
    self.config.applyQuantityFont(text)
    text:SetTextColor(button.complete and 0.2 or 1, 1, button.complete and 0.2 or 1)
    local brightness = button.complete and 1 or 0.3
    button.icon:SetVertexColor(brightness, brightness, brightness)
    text:SetScale(1)
    if not button.quantity then return end
    local available = self.config.itemSize - 2
    text:SetText(button.quantity)
    if text:GetStringWidth() <= available then return end
    local owned, required
    for precision = 1, 0, -1 do
        local decimals = precision == 1
        owned = button.quantityUnknown and "?" or CompactQuantity(button.owned, decimals)
        required = button.required:gsub("%d+", function(value) return CompactQuantity(tonumber(value), decimals) end)
        text:SetText(owned .. "/" .. required)
        if text:GetStringWidth() <= available then return end
    end
    -- 极端字号/范围仍放不下一行时分行，保持用户选择的字号。
    text:SetText(owned .. "\n/" .. required)
end

local function StyleRecipeText(text)
    local font, size = text:GetFont()
    text:SetFont(font or GUI2.Fonts.normal, size or 12, "OUTLINE")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    local color = text.recipeQuality and ITEM_QUALITY_COLORS[text.recipeQuality]
    text:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
end

local function BindRecipeText(text)
    text.RefreshTheme = StyleRecipeText
    -- 主面板应用外观字体后，重新应用业务文字样式。
    text.yuiAuctionAfterFont = StyleRecipeText
    StyleRecipeText(text)
end

function Tracker:UpdateRecipeText(text, recipe)
    local quality
    if recipe.itemID then
        local name, _, itemQuality = C_Item.GetItemInfo(recipe.itemID)
        quality = itemQuality
        if not name then self:RequestItem(recipe.itemID) end
    end
    if text.recipeQuality ~= quality then
        text.recipeQuality = quality
        text:RefreshTheme()
    end
end

function Tracker:ShowRecipeTooltip(owner, recipe)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if recipe.itemID and C_Item.GetItemInfo(recipe.itemID) then
        GameTooltip:SetItemByID(recipe.itemID)
    else
        local link = not recipe.itemID and C_TradeSkillUI.GetRecipeLink(recipe.id)
        if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(recipe.name) end
    end
    GameTooltip:Show()
end

-- 只在追踪列表变化或重新打开时读取结构；背包事件只更新数量。
function Tracker:ReadRecipes()
    self:ClearSearch()
    wipe(self.materials)
    self.layoutDirty = true
    self.totalsDirty = true
    local recipes = {}
    local present = {}
    for _, isRecraft in ipairs({ true, false }) do
        for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}) do
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
            local recipe = {
                id = recipeID, isRecraft = isRecraft,
                key = tostring(recipeID) .. (isRecraft and ":recraft" or ":craft"),
                name = schematic and schematic.name or L["tracker.loading"],
                icon = schematic and schematic.icon or UNKNOWN_ICON,
                itemID = schematic and schematic.outputItemID,
                slots = {},
            }
            if isRecraft then recipe.name = L["tracker.recraft"]:format(recipe.name) end
            for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
                if ProfessionsUtil.IsReagentSlotRequired(slot) then
                    if ProfessionsUtil.IsReagentSlotModifyingRequired(slot) then
                        table.insert(recipe.slots, 1, slot)
                    else
                        recipe.slots[#recipe.slots + 1] = slot
                    end
                end
            end
            recipes[#recipes + 1] = recipe
            present[recipe.key] = true
        end
    end
    for key in pairs(self.excluded) do
        if not present[key] then self.excluded[key] = nil end
    end
    return recipes
end

local function RequiredRange(slot)
    local quantities = slot.variableQuantities
    if quantities and #quantities > 0 then
        local minimum, maximum = math.huge, 0
        for _, entry in ipairs(quantities) do
            minimum = math.min(minimum, entry.quantity)
            maximum = math.max(maximum, entry.quantity)
        end
        return minimum, maximum, true
    end
    local quantity = slot.quantityRequired or 0
    return quantity, quantity, false
end

-- 以可替代材料的完整 ID 集合为单位合并，不按可能重名的本地化名称合并。
function Tracker:BuildTotals()
    local slots, byKey = {}, {}
    for _, recipe in ipairs(self.recipes) do
        if not self.excluded[recipe.key] then
            for slotIndex, slot in ipairs(recipe.slots) do
                local identities, seen, reagents = {}, {}, {}
                for _, reagent in ipairs(slot.reagents) do
                    local identity = reagent.itemID and ("item:" .. reagent.itemID)
                        or reagent.currencyID and ("currency:" .. reagent.currencyID)
                    if identity and not seen[identity] then
                        seen[identity] = true
                        identities[#identities + 1] = identity
                        reagents[#reagents + 1] = reagent
                    end
                end
                table.sort(identities)
                local key = #identities > 0 and table.concat(identities, ";") or recipe.key .. ":" .. slotIndex
                local total = byKey[key]
                if not total then
                    total = { reagents = reagents, slotInfo = slot.slotInfo, aggregateMin = 0, aggregateMax = 0 }
                    byKey[key] = total
                    slots[#slots + 1] = total
                end
                local minimum, maximum, variable = RequiredRange(slot)
                total.aggregateMin = total.aggregateMin + minimum
                total.aggregateMax = total.aggregateMax + maximum
                total.aggregateVariable = total.aggregateVariable or variable
            end
        end
    end
    self.totalSlots, self.totalsDirty = slots, false
end

function Tracker:SetIncluded(key, included)
    self:ClearSearch()
    self.excluded[key] = not included or nil
    self.totalsDirty, self.layoutDirty = true, true
    self:Schedule()
end

function Tracker:SetMode(mode)
    if self.mode == mode then return end
    self.mode = mode
    self:ClearSearch()
    self.layoutDirty = true
    self.scroll:SetVerticalScroll(0)
    ns.HideGameTooltip()
    self:Schedule()
end

function Tracker:ClearSearch()
    self.pendingSearch, self.pendingSearchSlot, self.pendingPurchase = nil, nil, nil
end

function Tracker:SetHighestOnly(value)
    value = value == true
    if self.highestOnly == value then return end
    self.highestOnly = value
    if self.config.setHighestOnly then self.config.setHighestOnly(value) end
    self:ClearSearch()
    ns.HideGameTooltip()
    self:Schedule()
end

-- 品质结构只在配方/物品数据变化时生成；库存刷新复用分组与单材料列表。
function Tracker:GetMaterial(slot)
    local data = self.materials[slot]
    if data then return data end
    data = { entries = {}, qualities = {}, byQuality = {}, itemIDs = {}, ready = true, maxQuality = 0 }
    local seen = {}
    for _, reagent in ipairs(slot.reagents) do
        local identity = reagent.itemID and ("item:" .. reagent.itemID) or ("currency:" .. reagent.currencyID)
        if not seen[identity] then
            seen[identity] = true
            local quality = 0
            if reagent.itemID then
                data.itemIDs[reagent.itemID] = true
                if not C_Item.GetItemInfo(reagent.itemID) then
                    data.ready = false
                    self:RequestItem(reagent.itemID)
                elseif C_TradeSkillUI.GetItemReagentQualityInfo then
                    local ok, info = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, reagent.itemID)
                    if ok then quality = info and info.quality or 0 else data.ready = false end
                end
            end
            local group = data.byQuality[quality]
            if not group then
                group = { quality = quality, itemIDs = {}, owned = 0, pending = 0 }
                data.byQuality[quality] = group
                data.qualities[#data.qualities + 1] = group
            end
            if reagent.itemID then group.itemIDs[reagent.itemID] = true end
            data.entries[#data.entries + 1] = { reagent = reagent, singleton = { reagent }, group = group }
            data.maxQuality = math.max(data.maxQuality, quality)
        end
    end
    table.sort(data.qualities, function(a, b) return a.quality < b.quality end)
    self.materials[slot] = data
    return data
end

function Tracker:CountMaterial(data)
    local total, pending = 0, 0
    for _, group in ipairs(data.qualities) do group.owned, group.pending = 0, 0 end
    for _, entry in ipairs(data.entries) do
        local count = ProfessionsUtil.AccumulateReagentsInPossession(entry.singleton)
        local purchased = entry.reagent.itemID and self.purchased[entry.reagent.itemID]
        local outstanding = 0
        if purchased then
            -- 已购材料进入持有统计时扣除待领取量，避免库存和购买记录重复计数。
            purchased.quantity = math.max(0, purchased.quantity - math.max(0, count - purchased.observed))
            purchased.observed = count
            outstanding = purchased.quantity
        end
        entry.group.owned = entry.group.owned + count
        entry.group.pending = entry.group.pending + outstanding
        total, pending = total + count, pending + outstanding
    end
    data.totalOwned, data.totalPending = total, pending
    local group = self.highestOnly and data.ready and data.maxQuality > 0 and data.byQuality[data.maxQuality]
    if self.highestOnly and not data.ready then
        data.owned, data.pending = 0, 0
    else
        data.owned, data.pending = group and group.owned or total, group and group.pending or pending
    end
end

function Tracker:GetSlotCount(slot)
    local data = self:GetMaterial(slot)
    self:CountMaterial(data)
    local owned = data.owned
    local minimum, maximum, variable
    if slot.aggregateMin then
        minimum, maximum, variable = slot.aggregateMin, slot.aggregateMax, slot.aggregateVariable
    else
        minimum, maximum, variable = RequiredRange(slot)
    end
    if variable then
        return owned, tostring(minimum) .. "–" .. tostring(maximum), false
    end
    local required = minimum
    return owned, tostring(required), owned >= required and (not self.highestOnly or data.ready)
end

function Tracker:GetMissing(slot)
    local owned = self:GetSlotCount(slot)
    local minimum, _, variable
    if slot.aggregateMin then
        minimum, variable = slot.aggregateMin, slot.aggregateVariable
    else
        minimum, _, variable = RequiredRange(slot)
    end
    local data = self:GetMaterial(slot)
    if variable or not data.ready then return nil end
    return math.max(0, minimum - owned - data.pending)
end

function Tracker:AppendMaterialTooltip(slot)
    local owned, required = self:GetSlotCount(slot)
    local data = self:GetMaterial(slot)
    if data.maxQuality > 0 then
        GameTooltip:AddLine(L["tracker.owned_total"]:format(data.totalOwned), 1, 1, 1)
        for _, group in ipairs(data.qualities) do
            local text
            if group.quality == 0 then
                text = L["tracker.unranked_count"]:format(group.owned)
            else
                local key = data.ready and group.quality == data.maxQuality and "tracker.quality_max_count" or "tracker.quality_count"
                text = L[key]:format(group.quality, group.owned)
            end
            GameTooltip:AddLine(text, 1, 1, 1)
        end
        GameTooltip:AddLine(L["tracker.required"]:format(required), 1, 1, 1)
    else
        GameTooltip:AddLine(L["tracker.quantity"]:format(tostring(owned) .. "/" .. required), 1, 1, 1)
    end
    if not data.ready then
        GameTooltip:AddLine(L["tracker.quality_loading"], 1, 1, 1)
        return
    end
    if data.pending > 0 then
        GameTooltip:AddLine(L["tracker.purchased_pending"]:format(data.pending), 1, 1, 1)
    end
    local missing = self:GetMissing(slot)
    if missing then
        local key = self.highestOnly and data.maxQuality > 0 and "tracker.missing_highest" or "tracker.missing"
        GameTooltip:AddLine(L[key]:format(missing), 1, 1, 1)
    end
end

function Tracker:TryFillPurchase()
    local pending = self.pendingPurchase
    if not pending or not pending.fillPending or not self.active or not self.panel:IsShown() then return end
    local house = self.config.auctionHouse
    local display = house.CommoditiesBuyFrame and house.CommoditiesBuyFrame.BuyDisplay
    if not display or not display:IsVisible() or not display.resultsLoaded then return end
    local itemID = display:GetItemID()
    if not pending.itemIDs[itemID] then self:ClearSearch(); return end
    if not C_AuctionHouse or not C_AuctionHouse.MakeItemKey or not C_AuctionHouse.HasSearchResults
        or not C_AuctionHouse.HasSearchResults(C_AuctionHouse.MakeItemKey(itemID)) then return end
    local event = AuctionHouseFrameMixin and AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged
    if not event or not house.TriggerEvent then return end
    local missing = self:GetMissing(pending.slot)
    if missing == nil then return end
    -- 只预填一次；同时通知原生数量框和价格列表，让原生逻辑处理库存与报价。
    pending.fillPending = false
    house:TriggerEvent(event, missing)
end

function Tracker:RecordPurchase()
    local attempt = self.purchaseAttempt
    self.purchaseAttempt = nil
    if not attempt then return end
    local observed = ProfessionsUtil.AccumulateReagentsInPossession(attempt.singleton)
    local record = self.purchased[attempt.itemID]
    if not record then
        record = { quantity = 0, observed = attempt.observed }
        self.purchased[attempt.itemID] = record
    end
    record.quantity = math.max(0, record.quantity + attempt.quantity - math.max(0, observed - record.observed))
    record.observed = observed
    self:Schedule()
end

function Tracker:InstallPurchaseHooks()
    if self.purchaseHooksInstalled or not hooksecurefunc then return end
    self.purchaseHooksInstalled = true
    local house = self.config.auctionHouse
    local frame = house.CommoditiesBuyFrame
    if frame and frame.SetItemIDAndPrice then
        hooksecurefunc(frame, "SetItemIDAndPrice", function(_, itemID)
            local pending = self.pendingPurchase
            if not self.active or not pending then return end
            if not pending.itemIDs[itemID] or (pending.selectedItemID and pending.selectedItemID ~= itemID) then
                self:ClearSearch()
            else
                pending.selectedItemID = itemID
                self:Schedule()
            end
        end)
        local list = frame.ItemList
        if list and list.SetSelectedEntry then
            -- 原生 selectionCallback 在 OnLoad 时捕获函数；Hook 实际行选择入口。
            hooksecurefunc(list, "SetSelectedEntry", function(_, rowData)
                if rowData and self.pendingPurchase and list:GetSelectedEntry() == rowData then
                    self.pendingPurchase.fillPending = false
                end
            end)
        end
        local input = frame.BuyDisplay and frame.BuyDisplay.QuantityInput and frame.BuyDisplay.QuantityInput.InputBox
        if input then
            input:HookScript("OnTextChanged", function(_, userInput)
                if userInput and self.pendingPurchase then self.pendingPurchase.fillPending = false end
            end)
        end
    end
    if house.ItemBuyFrame and house.ItemBuyFrame.SetItemKey then
        hooksecurefunc(house.ItemBuyFrame, "SetItemKey", function() self:ClearSearch() end)
    end
    local dialog = house.BuyDialog
    if dialog and dialog.BuyNow then
        hooksecurefunc(dialog, "BuyNow", function()
            self.purchaseAttempt = nil
            local pending = self.pendingPurchase
            if not self.active or not pending or not pending.itemIDs[dialog.itemID] then return end
            local singleton = { { itemID = dialog.itemID } }
            self.purchaseAttempt = {
                itemID = dialog.itemID, quantity = dialog.quantity, singleton = singleton,
                observed = ProfessionsUtil.AccumulateReagentsInPossession(singleton),
            }
        end)
        if dialog.Cancel then hooksecurefunc(dialog, "Cancel", function() self.purchaseAttempt = nil end) end
    end
    local bar = house.SearchBar
    if bar and bar.SearchButton then
        bar.SearchButton:HookScript("OnClick", function() if not self.searching then self:ClearSearch() end end)
    end
    if bar and bar.SearchBox then
        bar.SearchBox:HookScript("OnTextChanged", function(_, userInput)
            if userInput and not self.searching then self:ClearSearch() end
        end)
    end
end

function Tracker:Create(config)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked or not ProfessionsUtil then return end
    local self = setmetatable({
        config = config, recipes = {}, blocks = {}, awaiting = {},
        structureDirty = true, dirty = true, active = false, dismissed = false,
        mode = "individual", excluded = {}, totalsDirty = true, totalSlots = {},
        materials = setmetatable({}, { __mode = "k" }), purchased = {},
        highestOnly = config.getHighestOnly and config.getHighestOnly() == true or false,
    }, { __index = Tracker })
    local helper, settings = config.helper, config.settings
    local appearance = ns.AuctionHelperAppearance
    local panel = GUI2:CreateFrame(helper)
    panel:Hide()
    panel:SetWidth(260)
    panel:SetPoint("TOPLEFT", helper, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", helper, "BOTTOMRIGHT", 2, 0)
    panel:SetFrameLevel(helper:GetFrameLevel() + 5)
    self.panel = panel
    local title = config.createText(panel, L["tracker.title"], 14)
    title:SetPoint("TOP", 0, -5)
    appearance:Register(panel, {
        blizzardWindow = "auctionhouse",
        themeProvider = config.themeProvider, heading = title,
        headingColorKey = "color.text.accent", role = "settings",
    })

    local function SmallButton(parent, text, tooltip, onClick)
        local button = GUI2:CreateButtonFrame(parent)
        button:SetSize(16, 16)
        button.text = config.createText(button, text, 14)
        button.text:SetPoint("CENTER")
        button.ResetColor = function()
            button.text:SetTextColor(0.7, 0.7, 0.7)
        end
        button.text.RefreshTheme = button.ResetColor
        button.ResetColor()
        button:HookScript("OnShow", button.ResetColor)
        button:SetScript("OnClick", function()
            ns.HideGameTooltip()
            onClick(button)
        end)
        button:SetScript("OnEnter", function()
            button.text:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            button.ResetColor()
            ns.HideGameTooltip()
        end)
        return button
    end
    local close = SmallButton(panel, "×", L["tracker.close"], function()
        self.dismissed = true
        self:SyncVisibility()
    end)
    close:SetPoint("TOPRIGHT", -4, -4)
    self.toggle = SmallButton(helper, "", L["tracker.title"], function()
        if self.panel:IsShown() then
            self.dismissed = true
            self:SyncVisibility()
            return
        end
        self.dismissed = false
        settings:Hide()
        self:SyncVisibility()
    end)
    self.toggle:SetPoint("RIGHT", config.settingsButton, "LEFT", -4, 0)
    local toggleIcon = GUI2:CreateTexture(self.toggle, { layer = "ARTWORK" })
    toggleIcon:SetAllPoints()
    toggleIcon:SetAtlas("poi-workorders")
    self.toggle:Hide()

    local scroll = GUI2:CreateScrollFrame(panel, { child = false })
    scroll:SetPoint("TOPLEFT", 18, -88)
    scroll:SetPoint("BOTTOMRIGHT", -32, 8)
    local content = GUI2:CreateFrame(scroll)
    content:SetSize(210, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content

    local tabContext = appearance:Resolve(config.themeProvider(), { blizzardWindow = "auctionhouse" })
    local accent = tabContext.accent
    self.tabs = GUI2.Form:CreateUnderlineTabs(panel, {
        width = 210, height = 24,
        items = {
            { text = L["tracker.tab_individual"], value = "individual" },
            { text = L["tracker.tab_total"], value = "total" },
        },
        value = self.mode, overflow = "scroll", contentAlignment = "CENTER", gap = 4,
        itemPaddingX = 8, minItemWidth = 54, indicatorOffsetY = -2, indicatorHeight = 3,
        indicatorColor = accent, selectedColor = accent, hoverColor = accent,
        onChange = function(_, value) self:SetMode(value) end,
    })
    self.tabs:SetPoint("TOP", panel, "TOP", 0, -30)
    for _, button in ipairs(self.tabs.buttons) do appearance:ApplyFont(button.text, tabContext) end
    self.tabs:Relayout()

    self.highestToggle = GUI2.Form:CreateCheckbox(panel, {
        autoWidth = true, height = 22, text = L["tracker.highest_only"], checked = self.highestOnly,
        onChange = function(_, checked) self:SetHighestOnly(checked) end,
    })
    self.highestToggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, -61)
    self.highestToggle:HookScript("OnEnter", function()
        GameTooltip:SetOwner(self.highestToggle, "ANCHOR_TOP")
        GameTooltip:SetText(L["tracker.highest_only"])
        GameTooltip:AddLine(L["tracker.highest_only_hint"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.highestToggle:HookScript("OnLeave", ns.HideGameTooltip)

    function self:NewBlock()
        local block = GUI2:CreateFrame(content)
        block:SetWidth(210)
        block.buttons = {}
        block.header = GUI2:CreateFrame(block)
        block.header:SetSize(190, 20)
        block.header:SetPoint("TOPLEFT")
        block.iconSlot = GUI2:CreateIconSlot(block.header, { size = 20, shape = "square", animate = false })
        block.iconSlot:SetPoint("LEFT", block.header, "LEFT", 0, 0)
        block.icon = block.iconSlot.icon
        block.name = config.createText(block.header, "", 14)
        block.name:SetPoint("LEFT", block.header, "LEFT", 24, 0)
        block.name:SetHeight(20)
        block.name:SetJustifyV("MIDDLE")
        block.name:SetWidth(166)
        block.name:SetWordWrap(false)
        block.name:SetJustifyH("LEFT")
        BindRecipeText(block.name)
        block.header:EnableMouse(true)
        block.header:SetScript("OnEnter", function()
            self:ShowRecipeTooltip(block.header, block.recipe)
        end)
        block.header:SetScript("OnLeave", ns.HideGameTooltip)
        block.close = SmallButton(block, "×", L["tracker.untrack"], function()
            local recipe = block.recipe
            C_TradeSkillUI.SetRecipeTracked(recipe.id, false, recipe.isRecraft)
            self.structureDirty = true
            self:Schedule()
        end)
        block.close:SetPoint("LEFT", block.header, "RIGHT", 4, 0)
        return block
    end

    function self:NewMaterial(block)
        local button = GUI2:CreateIconSlot(block, {
            size = config.itemSize, shape = "square", animate = false,
            onClick = function(slot) if slot.itemID then self:Search(slot.itemID, false, slot.materialSlot) end end,
        })
        -- IconSlot.count 属于 GUI2 状态着色；需求数量独立管理，避免 hover 覆盖。
        button.quantityText = config.createText(button, "", 11)
        button.quantityText:SetPoint("BOTTOMRIGHT", -1, 1)
        button.quantityText:SetJustifyH("RIGHT")
        button.quantityText.RefreshTheme = function(text)
            self:PaintQuantity(button)
        end
        button.quantityText.yuiAuctionAfterFont = button.quantityText.RefreshTheme
        local refresh = button.RefreshTheme
        if refresh then
            button.RefreshTheme = function(widget, ...)
                refresh(widget, ...)
                self:PaintQuantity(widget)
            end
        end
        button:HookScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if button.itemID then
                GameTooltip:SetItemByID(button.itemID)
            elseif button.currencyID then
                GameTooltip:SetCurrencyByID(button.currencyID)
            else
                GameTooltip:SetText(button.label or L["tracker.loading"])
            end
            self:AppendMaterialTooltip(button.materialSlot)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function()
            ns.HideGameTooltip()
        end)
        button:SetScript("OnClick", function()
            if button.itemID then self:Search(button.itemID, false, button.materialSlot) end
        end)
        return button
    end

    self.flush = function()
        self.timer = nil
        if not self.active then return end
        if self.structureDirty then
            self.recipes = self:ReadRecipes()
            self.structureDirty = false
        end
        self:SyncVisibility()
        self:TryFillPurchase()
    end
    self.onEvent = function(event, itemID, success)
        if event == "ITEM_DATA_LOAD_RESULT" then
            if not self.awaiting[itemID] then return end
            -- 完成或失败均保留标记，避免失败物品触发请求/刷新循环。
            self.awaiting[itemID] = false
            wipe(self.materials)
            if self.pendingSearchSlot then
                local pendingID, slot = self.pendingSearch, self.pendingSearchSlot
                if not success then
                    for _, reagent in ipairs(slot.reagents) do
                        if reagent.itemID == itemID then self:ClearSearch(); break end
                    end
                elseif self.panel:IsShown() then
                    self:Search(pendingID, true, slot)
                end
            elseif self.pendingSearch == itemID then
                self.pendingSearch = nil
                if success and self.panel:IsShown() then self:Search(itemID, true) end
            end
        elseif event == "TRACKED_RECIPE_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE" then
            self.structureDirty = true
            self:ClearSearch()
        elseif event == "COMMODITY_SEARCH_RESULTS_RECEIVED" then
            -- RECEIVED 不携带 itemID；下一帧由 TryFillPurchase 核对原生购买页和结果。
            if not self.pendingPurchase then return end
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
            if not self.purchaseAttempt then return end
            self:RecordPurchase()
        elseif event == "COMMODITY_PURCHASE_FAILED" or event == "COMMODITY_PRICE_UNAVAILABLE" then
            self.purchaseAttempt = nil
            return
        end
        self:Schedule()
    end
    panel:HookScript("OnHide", function()
        self:ClearSearch()
        ns.HideGameTooltip()
    end)
    settings:HookScript("OnShow", function() self:SyncVisibility() end)
    settings:HookScript("OnHide", function()
        if helper:IsVisible() and config.isEnabled() then
            self.dismissed = false
            self:SyncVisibility()
        end
    end)
    helper:HookScript("OnShow", function() self:Start() end)
    helper:HookScript("OnHide", function() self:Stop() end)
    config.auctionHouse:HookScript("OnShow", function()
        self.dismissed = false
        self:Start()
        self:SyncVisibility()
    end)
    config.auctionHouse:HookScript("OnHide", function()
        wipe(self.purchased)
        self.purchaseAttempt = nil
    end)
    self:InstallPurchaseHooks()
    config.auctionHouse:HookScript("OnHide", function() self:Stop() end)
    self:Start()
    return self
end

function Tracker:Schedule()
    self.dirty = true
    if not self.active or self.timer then return end
    -- 手动关闭和设置期间只处理追踪结构，不刷新隐藏图标。
    if not self.structureDirty and not self.panel:IsShown() then return end
    self.timer = C_Timer.NewTimer(0, self.flush)
end

function Tracker:Start()
    if self.active or not self.config.isEnabled() or not self.config.helper:IsVisible() then return end
    self.active = true
    if self.config.getHighestOnly then self.highestOnly = self.config.getHighestOnly() == true end
    self.highestToggle:SetChecked(self.highestOnly, true)
    self.structureDirty, self.dirty = true, true
    ns.Event:On("TRACKED_RECIPE_UPDATE", self.onEvent, self)
    ns.Event:On("TRADE_SKILL_LIST_UPDATE", self.onEvent, self)
    ns.Event:On("BAG_UPDATE_DELAYED", self.onEvent, self)
    ns.Event:On("CURRENCY_DISPLAY_UPDATE", self.onEvent, self)
    ns.Event:On("ITEM_DATA_LOAD_RESULT", self.onEvent, self)
    ns.Event:On("COMMODITY_SEARCH_RESULTS_RECEIVED", self.onEvent, self)
    ns.Event:On("COMMODITY_PURCHASE_SUCCEEDED", self.onEvent, self)
    ns.Event:On("COMMODITY_PURCHASE_FAILED", self.onEvent, self)
    ns.Event:On("COMMODITY_PRICE_UNAVAILABLE", self.onEvent, self)
    self.flush()
end

function Tracker:RefreshEnabled()
    if not self.config.isEnabled() then
        self:Stop()
        return
    end
    self.dismissed = false
    self:Start()
    self:SyncVisibility()
end

function Tracker:Stop()
    self.active = false
    ns.Event:OffOwner(self)
    if self.timer then self.timer:Cancel(); self.timer = nil end
    self:ClearSearch()
    self.purchaseAttempt = nil
    wipe(self.materials)
    wipe(self.awaiting)
    self.panel:Hide()
    self.toggle:Hide()
end

function Tracker:SyncVisibility()
    if self.active and self.structureDirty and not self.config.settings:IsShown() and not self.dismissed then
        self.recipes = self:ReadRecipes()
        self.structureDirty = false
    end
    local hasRecipes = self.active and #self.recipes > 0
    self.toggle:SetShown(hasRecipes)
    local visible = hasRecipes and not self.dismissed and not self.config.settings:IsShown()
    self.panel:SetShown(visible)
    if visible then
        if self.dirty then self:Render() end
    else
        if self.timer then self.timer:Cancel(); self.timer = nil end
        self:ClearSearch()
    end
end

function Tracker:RequestItem(itemID)
    if self.awaiting[itemID] == nil then
        self.awaiting[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

function Tracker:Search(itemID, loaded, slot)
    if not self.active or not self.panel:IsShown() then return end
    local house = self.config.auctionHouse
    local bar = house.SearchBar
    if not house:IsVisible() or not bar or not bar.SearchBox or not bar.SearchButton then return end
    self:ClearSearch()
    local data = slot and self:GetMaterial(slot)
    if data and not data.ready then
        self.pendingSearch, self.pendingSearchSlot = itemID, slot
        return
    end
    if data and self.highestOnly and data.maxQuality > 0 then
        for _, entry in ipairs(data.entries) do
            if entry.group.quality == data.maxQuality then itemID = entry.reagent.itemID; break end
        end
    end
    local name = C_Item.GetItemInfo(itemID)
    if not name then
        if not loaded then
            self.pendingSearch = itemID
            self.pendingSearchSlot = slot
            self:RequestItem(itemID)
        end
        return
    end
    if slot and self:GetMissing(slot) ~= nil then
        local group = self.highestOnly and data.maxQuality > 0 and data.byQuality[data.maxQuality]
        self.pendingPurchase = { slot = slot, itemIDs = group and group.itemIDs or data.itemIDs, fillPending = true }
    end
    self.searching = true
    if house.SetDisplayMode then house:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    bar.SearchBox:SetText(name)
    bar.SearchButton:Click()
    self.searching = false
end

function Tracker:UpdateMaterial(button, slot, slotIndex, layout, startY)
    button.materialSlot = slot
    local data = self:GetMaterial(slot)
    local reagent = slot.reagents[1] or {}
    if self.highestOnly and data.ready and data.maxQuality > 0 then
        for _, entry in ipairs(data.entries) do
            if entry.group.quality == data.maxQuality then reagent = entry.reagent; break end
        end
    end
    button.itemID, button.currencyID = reagent.itemID, reagent.currencyID
    button.label = slot.slotInfo and slot.slotInfo.slotText or nil
    local texture
    if reagent.itemID then
        texture = C_Item.GetItemIconByID(reagent.itemID)
        if not C_Item.GetItemInfo(reagent.itemID) then self:RequestItem(reagent.itemID) end
    elseif reagent.currencyID then
        local currency = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
        texture = currency and currency.iconFileID
    end
    texture = texture or UNKNOWN_ICON
    if button.texture ~= texture then
        button.texture = texture
        button.icon:SetTexture(texture)
    end
    local owned, required, complete = self:GetSlotCount(slot)
    button.quantityUnknown = self.highestOnly and not data.ready
    local quantity = (button.quantityUnknown and "?" or tostring(owned)) .. "/" .. required
    local fontChanged = self.config.applyQuantityFont(button.quantityText)
    if button.quantity ~= quantity or button.complete ~= complete or fontChanged then
        button.quantity, button.complete = quantity, complete
        button.owned, button.required = owned, required
        self:PaintQuantity(button)
    end
    if layout then
        button:ClearAllPoints()
        local stride = self.config.itemSize + self.config.itemSpacing
        button:SetPoint("TOPLEFT", ((slotIndex - 1) % 5) * stride, -startY - math.floor((slotIndex - 1) / 5) * stride)
        button:Show()
    end
end

function Tracker:Render()
    self.dirty = false
    local layout = self.layoutDirty
    self.layoutDirty = false
    if self.mode == "total" then
        self:RenderTotal(layout)
        return
    end
    if self.totalBlock then self.totalBlock:Hide() end
    local y = CONTENT_TOP
    for index, recipe in ipairs(self.recipes) do
        local block = self.blocks[index]
        if not block then block = self:NewBlock(); self.blocks[index] = block end
        if layout then
            block.recipe = recipe
            block:ClearAllPoints()
            block:SetPoint("TOPLEFT", 0, -y)
            block.name:SetText(recipe.name)
            block.close.ResetColor()
            block:Show()
        end
        self:UpdateRecipeText(block.name, recipe)
        local outputIcon = recipe.itemID and C_Item.GetItemIconByID(recipe.itemID) or recipe.icon
        if block.outputIcon ~= outputIcon then
            block.outputIcon = outputIcon
            block.iconSlot:SetIcon(outputIcon)
        end
        for slotIndex, slot in ipairs(recipe.slots) do
            local button = block.buttons[slotIndex]
            if not button then button = self:NewMaterial(block); block.buttons[slotIndex] = button end
            self:UpdateMaterial(button, slot, slotIndex, layout, 26)
        end
        local height = 26 + math.ceil(#recipe.slots / 5) * (self.config.itemSize + self.config.itemSpacing) + 12
        if layout then
            for i = #recipe.slots + 1, #block.buttons do block.buttons[i]:Hide() end
            block:SetHeight(height)
        end
        y = y + height
    end
    if layout then
        for i = #self.recipes + 1, #self.blocks do self.blocks[i]:Hide() end
        self.content:SetHeight(math.max(1, y))
    end
    local maximum = math.max(0, y - self.scroll:GetHeight())
    if self.scroll:GetVerticalScroll() > maximum then self.scroll:SetVerticalScroll(maximum) end
end

function Tracker:RenderTotal(layout)
    for _, block in ipairs(self.blocks) do block:Hide() end
    if self.totalsDirty then self:BuildTotals(); layout = true end
    local block = self.totalBlock
    if not block then
        block = GUI2:CreateFrame(self.content)
        block:SetWidth(210)
        block:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
        block.buttons, block.checks = {}, {}
        block.title = self.config.createText(block, L["tracker.total_materials"], 12)
        block.title:SetPoint("TOPLEFT")
        block.title:SetHeight(20)
        block.title:SetJustifyV("MIDDLE")
        BindRecipeText(block.title)
        block.sources = self.config.createText(block, L["tracker.sources"], 12)
        block.sources:SetHeight(20)
        block.sources:SetJustifyV("MIDDLE")
        BindRecipeText(block.sources)
        block.empty = self.config.createText(block, L["tracker.none_selected"], 12)
        block.empty:SetPoint("TOPLEFT", 0, -26)
        self.totalBlock = block
    end
    block:Show()
    for index, slot in ipairs(self.totalSlots) do
        local button = block.buttons[index]
        if not button then button = self:NewMaterial(block); block.buttons[index] = button end
        self:UpdateMaterial(button, slot, index, layout, 26)
    end
    if not layout then
        for index, recipe in ipairs(self.recipes) do self:UpdateRecipeText(block.checks[index].text, recipe) end
        return
    end
    for i = #self.totalSlots + 1, #block.buttons do block.buttons[i]:Hide() end
    block.empty:SetShown(#self.totalSlots == 0)
    local rows = math.max(1, math.ceil(#self.totalSlots / 5))
    local y = 26 + rows * (self.config.itemSize + self.config.itemSpacing) + 12
    block.sources:ClearAllPoints()
    block.sources:SetPoint("TOPLEFT", 0, -y)
    y = y + 24
    for index, recipe in ipairs(self.recipes) do
        local checkbox = block.checks[index]
        if not checkbox then
            checkbox = GUI2.Form:CreateCheckbox(block, {
                width = 210, height = 26, text = "", checked = true,
                onChange = function(widget, checked) self:SetIncluded(widget.recipeKey, checked) end,
            })
            checkbox:HookScript("OnEnter", ns.HideGameTooltip)
            checkbox:HookScript("OnLeave", ns.HideGameTooltip)
            -- 名称单独承接提示，复选框区域只负责勾选。
            local nameHit = GUI2:CreateButtonFrame(checkbox)
            nameHit:SetAllPoints(checkbox.text)
            nameHit:SetScript("OnEnter", function()
                self:ShowRecipeTooltip(nameHit, checkbox.recipe)
            end)
            nameHit:SetScript("OnLeave", ns.HideGameTooltip)
            nameHit:SetScript("OnClick", function() checkbox:Click() end)
            checkbox.nameHit = nameHit
            BindRecipeText(checkbox.text)
            local refresh = checkbox.RefreshTheme
            if refresh then
                checkbox.RefreshTheme = function(widget, ...)
                    refresh(widget, ...)
                    widget.text:RefreshTheme()
                end
            end
            block.checks[index] = checkbox
        end
        checkbox.recipeKey, checkbox.recipeName = recipe.key, recipe.name
        checkbox.recipe = recipe
        checkbox.text:SetText(recipe.name)
        checkbox:SetChecked(not self.excluded[recipe.key], true)
        self:UpdateRecipeText(checkbox.text, recipe)
        checkbox.text:RefreshTheme()
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", 0, -y)
        checkbox:Show()
        y = y + 26
    end
    for i = #self.recipes + 1, #block.checks do block.checks[i]:Hide() end
    block:SetHeight(y + 8)
    self.content:SetHeight(y + 8 + CONTENT_TOP)
    local maximum = math.max(0, y + 8 + CONTENT_TOP - self.scroll:GetHeight())
    if self.scroll:GetVerticalScroll() > maximum then self.scroll:SetVerticalScroll(maximum) end
end

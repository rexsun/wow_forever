local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end

local I = {}
B.GuildInventory = I
local rowsPerColumn, capacity = 7, 98
local Item,Security=YUI.API.Item,YUI.API.Security

function I:LinkLevel(link,info)
    local level
    if Item.GetLevel then
        local ok,value=pcall(Item.GetLevel,link)
        level=ok and Security.SafeNumber(value)
    end
    if level and level>0 then return level end
    level=info and Security.SafeNumber(info.level)
    if level and level>0 then return level end
end

-- Old snapshots may predate the level/bindType fields. Resolve only link
-- metadata here; instance facts always come from the actual stored record.
function I:BadgeFields(item,data,revision)
    local class,level,loc,bind=item.classID,item.level,item.equipLoc,item.bindType
    local gear=class==2 or class==4
    if level and level<=0 then level=nil end
    local needsInfo=not class or gear and (not level or not loc) or item.bound==false and bind==nil
    if item.empty or not needsInfo or not Security.SafeString(item.link) or not item.itemID then return class,level,loc,bind end
    if data.guildBadgeLink~=item.link or data.guildBadgeID~=item.itemID or data.guildBadgeRevision~=revision then
        data.guildBadgeLink,data.guildBadgeID,data.guildBadgeRevision=item.link,item.itemID,revision
        data.guildBadgeInfo,data.guildLinkLevel=nil,nil
        local payload=item.link:match("|H(item:[^|]+)|h") or item.link:match("^(item:[^|]+)$")
        if payload and tonumber(payload:match("^item:(%d+):") or payload:match("^item:(%d+)$"))==item.itemID then
            local info=Item.GetInfo(item.link)
            data.guildBadgeInfo=info
            local resolved=class or info and Security.SafeNumber(info.classID)
            if resolved==2 or resolved==4 then data.guildLinkLevel=self:LinkLevel(item.link,info) end
            if not info or (resolved==2 or resolved==4) and not data.guildLinkLevel then
                B.View.waitingEquipment[item.itemID]=true
            end
        end
    end
    local info=data.guildBadgeInfo
    return class or info and Security.SafeNumber(info.classID),level or data.guildLinkLevel,
        loc or info and Security.SafeString(info.equipLoc),bind or info and Security.SafeNumber(info.bindType)
end

local function VisibleTab(w, id)
    for _, tab in ipairs(w.tabs or {}) do
        if tab.id == id and tab.view then return tab end
    end
end

local function TabName(tab)
    return tab.name and tab.name ~= "" and tab.name:gsub("|", "||")
        or string.format(B:T("bank.page"), tab.id)
end

local function OverviewSourceVisible(id)
    return not B.Deposit.guildRequests[id] or B.Deposit:GetGuildOverviewPage(id) ~= nil
end

local function TabLabel(tab, cached, name)
    name = name or TabName(tab)
    if cached then name = name .. " (" .. B:T("bank.cached") .. ")"
    elseif B.Deposit.guildRequests[tab.id] then name = name .. " (" .. B:T("bank.loading") .. ")" end
    return name
end

-- Strip only hyperlink presentation. Keep the complete item payload, including
-- gems, enchantments, random suffixes and trailing version-specific fields.
local function Variant(item)
    if item.empty or not item.itemID or type(item.link) ~= "string" then return end
    local payload = item.link:match("|H(item:[^|]+)|h") or item.link:match("^(item:[^|]+)$")
    local id = payload and (payload:match("^item:(%d+):") or payload:match("^item:(%d+)$"))
    if tonumber(id) ~= item.itemID then return end
    return payload .. "\031" .. tostring(item.bound) .. "\031" .. tostring(item.charges)
        .. "\031" .. tostring(item.quality)
end

local function Current(w, state)
    return state and w.guildInventory == state and w.open ~= false
        and (not w.guildMode or w.guildMode == "items") and state.page == w.page
        and state.guild == B.Cache.guildKey
end

local function CloseMenu(state)
    local popup = state.popup
    state.popup = nil
    local menu = B.View.menu
    if popup and menu and menu.owner == popup.owner and menu.rows[1]
        and menu.rows[1].action == popup.rows[1].action then menu:Hide() end
end

function I:ReleaseHighlight(button)
    local marker = button.ybagsGuildLocate
    if not marker or not marker.state then return end
    if marker.skin == "native" then
        if marker.pulse then marker.pulse:Stop(); marker.burst:Stop() end
        marker.glow:Hide()
        marker.flash:Hide()
    else
        button:UnlockHighlight()
    end
    marker.state.painted[button] = nil
    marker.state, marker.slot, marker.skin, marker.quality = nil, nil, nil, nil
    marker:Hide()
end

local function HideHighlights(state)
    for button in pairs(state.painted) do I:ReleaseHighlight(button) end
end

function I:Clear(w)
    local menu = B.View.menu
    if menu and menu.owner and menu.owner.guildDepositWindow == w then menu:Hide() end
    local state = w.guildInventory
    if state then
        CloseMenu(state)
        HideHighlights(state)
        if state.tipOwner and GameTooltip:IsOwned(state.tipOwner) then GameTooltip:Hide() end
        w.guildInventory = nil
    end
    w.crossPageCount = nil
end

-- A refresh consumes neither hovered slots nor newly arrived items. Once
-- resolved, a locate request can only lose marks, never acquire new ones.
local function Resolve(w, state)
    local locate = state.locate
    if not locate then return end
    if not VisibleTab(w, state.page) then state.locate = nil; return end
    if not state.ready then return end
    if not locate.slots then
        locate.slots = {}
        for slot, item in pairs(state.bySlot) do
            if Variant(item) == locate.variant then locate.slots[slot] = item.guid or true end
        end
    else
        for slot, guid in pairs(locate.slots) do
            local item = state.bySlot[slot]
            if not item or Variant(item) ~= locate.variant or guid ~= true and item.guid ~= guid then
                locate.slots[slot] = nil
            end
        end
    end
    if not next(locate.slots) then state.locate = nil end
end

-- Actions owns the recovery offer and validates the actual drop. Painting reads
-- only the current display snapshot, including the original partial stack.
local function Highlighted(w, state, item)
    if not item or not state or not state.ready then return false end
    local locate = state.locate
    local marked = not item.empty and locate and locate.slots and locate.slots[item.slot]
    local actions = B.Actions
    local waiting = actions.waiting
    local op = waiting and waiting.guildManual and waiting.operation
    local target = op and op.target
    local manual = target and target.kind == "guild" and target.bag == w.page and target.slot == item.slot
    if not (marked or manual) then return false end
    if not Current(w, state) or B.Deposit.guildRequests[w.page]
        or state.bySlot[item.slot] ~= item or item.guildCached then return false end
    local tab = VisibleTab(w, w.page)
    if not tab then return false end
    if marked then return true end
    if not tab.deposit or item.guildManual or not actions.queue
        or actions.queue[actions.index] ~= op or op.guildOwner ~= state.guild
        or target.choiceSession and target.choiceSession ~= w.cachedGuildPages then return false end
    if not waiting.target then return item.empty end
    return not item.empty and not item.locked and waiting.target.count == item.count
        and B.Deposit:GuildStackMatches(waiting.source, item)
end

local function Fixed(w, state, items, empties, config)
    local bySlot, nodes = {}, {}
    state.bySlot = bySlot
    state.ready = w.pagesComplete == true and not w.hasCache and not B.Deposit.guildRequests[w.page]
    if not VisibleTab(w, w.page) then
        state.locate, state.ready = nil, false
        HideHighlights(state)
        return nodes, 0
    end
    for _, item in ipairs(items) do
        if item.bag == w.page then
            bySlot[item.slot] = item
            if item.guildCached then state.ready = false end
        end
    end
    -- The reader can supply manual-deposit targets on an as-yet unconfirmed
    -- page. Their presence never confirms the page or resolves a locate.
    for _, item in ipairs(empties) do
        if (state.ready or item.guildManual or item.guildCached) and item.bag == w.page and item.empty
            and not bySlot[item.slot] then
            bySlot[item.slot] = item
        end
    end
    Resolve(w, state)
    for button, slot in pairs(state.painted) do
        if not Highlighted(w, state, bySlot[slot]) then I:ReleaseHighlight(button) end
    end
    local step = config.slotSize + 3
    for slot = 1, capacity do
        local item = bySlot[slot]
        if item then
            nodes[#nodes + 1] = {kind="item", item=item, h=step,
                x=math.floor((slot-1)/rowsPerColumn)*step, y=((slot-1)%rowsPerColumn)*step}
        end
    end
    return nodes, #nodes > 0 and rowsPerColumn*step or 0
end

local function Overview(w, state, items, config, cols)
    local visible, groups, projection = {}, {}, {}
    for _, tab in ipairs(w.tabs or {}) do visible[tab.id] = tab.view and OverviewSourceVisible(tab.id) end
    for _, item in ipairs(items) do
        if visible[item.bag] and not item.empty and not item.guildCached then
            local variant = Variant(item)
            local key = variant or ("slot:" .. item.bag .. ":" .. item.slot .. ":" .. tostring(item.itemID))
            local group = groups[key]
            if not group then
                group = {guildKey=key, guildVariant=variant, guildSources={}, displayCount=0}
                groups[key] = group
            end
            -- Matching live stacks may finish loading their names separately.
            local matches = B.Classification:Matches(item, w.query)
            local named = item.name and item.name ~= ""
            local rank = (matches and 2 or 0) + (named and 1 or 0)
            if not group.rank or rank > group.rank then
                group.representative = item
                group.matches, group.rank = matches, rank
            end
            local source = group.guildSources[item.bag]
            if not source then
                source = {count=0}
                group.guildSources[item.bag] = source
            end
            source.count = source.count + item.count
            group.displayCount = group.displayCount + item.count
        end
    end
    local matches = {}
    for key, group in pairs(groups) do
        local item = group.representative
        if group.matches then
            for field, value in pairs(item) do group[field] = value end
            group.uid = "guild-group:" .. key
            group.representative, group.matches, group.rank = nil, nil, nil
            group.name = item.name or ""
            group.section, group.group, group.groupOrder = B.Classification:Classify(group, config, B.Model.compiled)
            projection[#projection + 1] = group
            matches[key] = group
        end
    end
    state.groups = matches
    w.crossPageCount = w.query and w.query:find("%S") and #projection or nil
    -- Personal flat-layout and split placements have no guild slot bindings.
    local layout = {layout="category", slotSize=config.slotSize, showSubnames=config.showSubnames}
    return B.Layout:Build(projection, {}, layout, cols, w.collapsed or {}, w.query)
end

local function Sources(w, group)
    local rows = {}
    for _, tab in ipairs(w.tabs or {}) do
        local source = tab.view and group.guildSources[tab.id]
        if source and OverviewSourceVisible(tab.id) then
            local name = TabName(tab)
            rows[#rows+1] = {page=tab.id, label=name, count=source.count,
                text=name, icon=tab.icon or 134400, valueText="×" .. source.count}
        end
    end
    return rows
end

local function SameRows(first, second)
    if #first ~= #second then return false end
    for n, row in ipairs(first) do
        local other = second[n]
        if row.page ~= other.page or row.label ~= other.label or row.count ~= other.count
            or row.icon ~= other.icon or row.text ~= other.text then return false end
    end
    return true
end

function I:Build(w, items, empties, config, cols)
    local state = w.guildInventory
    if not Current(w, state) then
        self:Clear(w)
        if w.open == false or w.guildMode and w.guildMode ~= "items" then return {}, 0 end
        state = {guild=B.Cache.guildKey, page=w.page, painted={}}
        w.guildInventory = state
    end
    w.crossPageCount = nil
    local nodes, height
    if w.page then
        nodes, height = Fixed(w, state, items, empties, config)
    else
        nodes, height = Overview(w, state, items, config, cols)
    end
    local popup = state.popup
    if popup then
        local menu = B.View.menu
        local group = state.groups[popup.key]
        if not menu or menu.owner ~= popup.owner or not group or not SameRows(popup.rows, Sources(w, group)) then
            CloseMenu(state)
        end
    end
    if state.tipOwner and GameTooltip:IsOwned(state.tipOwner) then
        local current = w.page and state.bySlot[state.tipSlot] or state.groups and state.groups[state.tipKey]
        if current and not current.empty then self:Tooltip(w, current, state.tipOwner, true)
        else GameTooltip:Hide(); state.tipOwner = nil end
    end
    return nodes, height
end

local function Locate(w, state, group, page)
    if not Current(w, state) or not state.groups[group.guildKey] or not VisibleTab(w, page)
        or not state.groups[group.guildKey].guildSources[page] or not OverviewSourceVisible(page) then return false end
    if not B.BankView:Select(w, page) then return false end
    -- Select clears the old state and may already have completed a synchronous layout.
    if w.open == false or w.guildMode and w.guildMode ~= "items" or w.page ~= page
        or B.Cache.guildKey ~= state.guild or not VisibleTab(w, page) then return false end
    local target = w.guildInventory
    if not target then
        target = {guild=state.guild, page=page, painted={}}
        w.guildInventory = target
    end
    if group.guildVariant and Current(w, target) then
        target.locate = {variant=group.guildVariant}
        Resolve(w, target)
        for _, button in ipairs(w.cachePool or {}) do
            local binding = B.View.buttonData[button]
            if binding and binding.window == w and button:IsShown() then I:PaintHighlight(w, button, binding.item) end
        end
    end
    return true
end

function I:Click(w, item, owner)
    local state = w.guildInventory
    if w.page or not Current(w, state) or not state.groups or not item or not item.guildKey then return false end
    if YUI.API.Bags.InCombat() or YUI.API.Bags.CursorBusy() then return false end
    local group = state.groups[item.guildKey]
    if not group or group ~= item then return false end
    CloseMenu(state)
    local rows = Sources(w, group)
    if #rows == 0 then return false end
    GameTooltip:Hide()
    if #rows == 1 then return Locate(w, state, group, rows[1].page) end
    local popup = {key=group.guildKey, owner=owner, rows=rows}
    state.popup = popup
    for _, row in ipairs(rows) do
        local page = row.page
        row.action = function()
            if state.popup ~= popup then return false end
            CloseMenu(state)
            return Locate(w, state, group, page)
        end
    end
    B.View:Menu(owner, rows, nil, true)
    return true
end

function I:Tooltip(w, item, owner, refreshing)
    local state = w.guildInventory
    local rows
    if Current(w, state) and item and not item.empty then
        if w.page then
            local tab = VisibleTab(w, w.page)
            if tab and state.bySlot and state.bySlot[item.slot] == item then
                rows = {{page=w.page, label=TabLabel(tab, item.guildCached)}}
            end
        elseif state.groups and state.groups[item.guildKey] == item then
            rows = Sources(w, item)
        end
    end
    if not rows or #rows == 0 then
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
        return false
    end
    local native = w.page and state.ready and not B.Deposit.guildRequests[w.page] and GameTooltip.SetGuildBankItem
    if refreshing and state.tipOwner == owner and GameTooltip:IsOwned(owner) and state.tipLink == item.link and state.tipID == item.itemID
        and state.tipStack == item.displayCount and state.tipCount == item.count and state.tipNative == native
        and state.tipRows and SameRows(state.tipRows, rows) then return true end
    state.tipOwner, state.tipSlot, state.tipKey = owner, item.slot, item.guildKey
    state.tipLink, state.tipID, state.tipRows = item.link, item.itemID, rows
    state.tipStack, state.tipCount, state.tipNative = item.displayCount, item.count, native
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if native then
        GameTooltip:SetGuildBankItem(w.page, item.slot)
    elseif item.link then GameTooltip:SetHyperlink(item.link)
    else GameTooltip:SetItemByID(item.itemID) end
    for _, row in ipairs(rows) do
        if row.count then GameTooltip:AddDoubleLine(row.label, tostring(row.count))
        else GameTooltip:AddLine(row.label) end
    end
    GameTooltip:Show()
    return true
end

local function AddFade(group, order, duration, from, to, smoothing)
    local fade = group:CreateAnimation("Alpha")
    fade:SetOrder(order)
    fade:SetDuration(duration)
    fade:SetFromAlpha(from)
    fade:SetToAlpha(to)
    fade:SetSmoothing(smoothing)
end

-- Use the native container's new-item artwork and timing on separate regions.
-- A guild tab/slot is never a player bag/slot for the new-item API.
local function ShowNativeLocate(button, marker, quality)
    if not marker.glow then
        local G = YUI.GUI2
        marker.flash = G:CreateTexture(button, {layer="OVERLAY", subLevel=2})
        marker.flash:SetPoint("CENTER")
        marker.flash:SetBlendMode("ADD")
        marker.flash:SetAtlas("bags-glow-flash", true)
        marker.glow = G:CreateTexture(button, {layer="OVERLAY", subLevel=2})
        marker.glow:SetPoint("CENTER")
        marker.glow:SetBlendMode("ADD")
        if marker.glow.CreateAnimationGroup then
            marker.pulse = marker.glow:CreateAnimationGroup()
            marker.pulse:SetLooping("REPEAT")
            marker.pulse:SetToFinalAlpha(true)
            AddFade(marker.pulse, 1, .5, 1, .2, "NONE")
            AddFade(marker.pulse, 2, .5, .2, 1, "NONE")
            marker.burst = marker.flash:CreateAnimationGroup()
            marker.burst:SetToFinalAlpha(true)
            AddFade(marker.burst, 1, .6, 1, 0, "OUT")
        end
    end
    local atlas = quality and ColorManager and ColorManager.GetAtlasDataForNewItemQuality
        and ColorManager.GetAtlasDataForNewItemQuality(quality)
    marker.glow:SetAtlas(atlas or "bags-glow-white", true)
    marker.glow:SetAlpha(1)
    marker.glow:Show()
    marker.flash:SetShown(marker.burst ~= nil)
    if marker.burst then
        marker.flash:SetAlpha(1)
        marker.burst:Play()
        marker.pulse:Play()
    end
end

function I:PaintHighlight(w, button, item)
    local state = w.guildInventory
    if state and state.tipOwner == button and item and
        (state.tipKey ~= item.guildKey or w.page and state.tipSlot ~= item.slot or item.empty) then
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        state.tipOwner = nil
    end
    if state and state.popup and state.popup.owner == button and state.popup.key ~= (item and item.guildKey) then
        CloseMenu(state)
    end
    if not Highlighted(w, state, item) then self:ReleaseHighlight(button); return end
    local skin = B:GetConfig().skin
    local marker = button.ybagsGuildLocate
    if marker then
        if marker.state == state and marker.slot == item.slot and marker.skin == skin
            and marker.quality == item.quality then return end
        self:ReleaseHighlight(button)
    else
        marker = YUI.GUI2:CreateFrame(button, {hidden=true, mouse=false})
        button.ybagsGuildLocate = marker
        button:HookScript("OnHide", function(owner) I:ReleaseHighlight(owner) end)
    end
    marker.state, marker.slot, marker.skin, marker.quality = state, item.slot, skin, item.quality
    state.painted[button] = item.slot
    if skin == "native" then ShowNativeLocate(button, marker, item.quality)
    else button:LockHighlight() end
    marker:Show()
end

function I:RefreshHighlights(w)
    for _, button in ipairs(w.cachePool) do
        local marker = button.ybagsGuildLocate
        if marker and marker.state then
            local data = B.View.buttonData[button]
            self:PaintHighlight(w, button, data and data.window == w and data.item)
        end
    end
end

function I:RefreshManualTarget()
    local w = B.View.windows["live-guild"]
    if not w or not w.guildInventory then return end
    local waiting = B.Actions.waiting
    local target = waiting and waiting.guildManual and waiting.operation.target
    for _, button in ipairs(w.cachePool) do
        local data = B.View.buttonData[button]
        local item = data and data.window == w and data.item
        if button:IsShown() and item then
            if button.ybagsGuildLocate and button.ybagsGuildLocate.state
                or target and target.bag == item.bag and target.slot == item.slot then
                self:PaintHighlight(w, button, item)
            end
        else
            self:ReleaseHighlight(button)
        end
    end
end

function I:Enter(w, button, item)
    local state = w.guildInventory
    local locate = state and state.locate
    if not locate or not locate.slots or not item or not Current(w, state) or not state.ready
        or B.Deposit.guildRequests[w.page] or not VisibleTab(w, w.page) or state.bySlot[item.slot] ~= item then return end
    locate.slots[item.slot] = nil
    if not next(locate.slots) then state.locate = nil end
    self:PaintHighlight(w, button, item)
end

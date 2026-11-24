local _, addon = ...
local YUI = _G.YUI or addon
local Native = YUI and YUI.NativeInterface
if not Native or not YUI.IsForever then return end

local Security = YUI.API.Security
local CARD_HEIGHT = 24
local HEADER = "SocialUIScrollableHeaderTemplate"
local SPACER = "SocialUIScrollableSpacerTemplate"

local function Checked(value)
    assert(not Security.IsSecretValue(value), "restricted social data")
    return value
end

local function CheckedTable(value)
    assert(type(Checked(value)) == "table" and Security.CanAccessTable(value) ~= false, "unreadable social table")
    return value
end

local function Classify(data, recent)
    local spacer, header = Checked(data.isSpacer), Checked(data.headerText)
    if spacer == true and header == nil then return SPACER end
    assert(spacer == nil, "unknown social spacer")
    if header ~= nil then
        assert(type(header) == "string" and (recent or type(Checked(data.headerType)) == "number"), "unknown social header")
        return HEADER
    end
    -- Native Initialize binds node:GetData() to the button read-only. Leave
    -- names (including kstrings), notes and interaction contents to Blizzard.
    if recent then
        CheckedTable(data.characterData)
        CheckedTable(data.stateData)
        CheckedTable(CheckedTable(data.interactionData).interactions)
    else
        assert(type(Checked(data.friendIndex)) == "number", "unknown friend index")
        CheckedTable(CheckedTable(data.accountInfo).gameAccountInfo)
    end
    return "card"
end

local function FriendTier(data)
    local game = CheckedTable(CheckedTable(CheckedTable(data).accountInfo).gameAccountInfo)
    local online = Checked(game.isOnline)
    if type(online) ~= "boolean" then return end
    if not online then return 5 end
    local client, mobile = Checked(game.clientProgram), Checked(game.isWowMobile)
    if type(client) ~= "string" then return end
    if mobile or client == BNET_CLIENT_APP or client == BNET_CLIENT_CLNT or client == "BSAp" or client == "" then return 4 end
    if client ~= BNET_CLIENT_WOW then return 3 end
    local project, current = Checked(game.wowProjectID), Checked(WOW_PROJECT_ID)
    if type(project) ~= "number" or type(current) ~= "number" then return end
    return project == current and 1 or 2
end

local function OrderedFriends(children)
    if #children < 3 or Checked(CheckedTable(children[1]:GetData()).isSpacer) ~= true then return end
    local buckets, previous, changed = {}, 0, false
    for index = 2, #children do
        local tier = FriendTier(CheckedTable(children[index]):GetData())
        if not tier then return end
        if tier < previous then changed = true end
        previous = tier
        local bucket = buckets[tier]
        if not bucket then bucket = {}; buckets[tier] = bucket end
        bucket[#bucket + 1] = children[index]
    end
    if not changed then return end
    local ordered = { children[1] }
    for tier = 1, 5 do
        local bucket = buckets[tier]
        if bucket then
            for _, node in ipairs(bucket) do ordered[#ordered + 1] = node end
        end
    end
    return ordered
end

-- Walk the real children, including collapsed branches. Enumerating the
-- visible range alone loses the children needed by the native header script.
local function CopyChildren(layer, source, parent, inHeader, nodes, previous)
    local children = CheckedTable(CheckedTable(source):GetNodes())
    local count = 0
    for index in next, children do
        assert(type(Checked(index)) == "number" and index >= 1 and index <= #children and index % 1 == 0)
        count = count + 1
    end
    assert(count == #children, "sparse social tree")
    if inHeader and layer.sortFriends then
        -- A restricted sort key leaves this group in the order supplied by Blizzard.
        local ok, ordered = pcall(OrderedFriends, children)
        if ok and ordered then children = ordered end
    end
    for index = 1, count do
        local node = CheckedTable(children[index])
        assert(not nodes[node], "duplicate social node")
        local data = CheckedTable(node:GetData())
        local kind = Classify(data, layer.recent)
        assert(kind == SPACER or (inHeader and kind == "card") or (not inHeader and kind == HEADER),
            "unknown social tree layout")
        local copy = parent:Insert(data)
        nodes[node] = copy
        local collapsed = Checked(node:IsCollapsed())
        local selected = Checked(node.selected)
        assert(collapsed == nil or type(collapsed) == "boolean")
        assert(selected == nil or type(selected) == "boolean")
        -- Native refreshes replace nodes and clear transient selection. On
        -- a redraw of the same snapshot, keep the private user's selection.
        local old = previous and previous[node]
        if old then selected = old.selected end
        copy.selected = selected
        if kind == HEADER then
            if layer.recent then
                if old then collapsed = old:IsCollapsed() end
            else
                local headerType = data.headerType
                local fromNative = collapsed == true
                if layer.nativeCollapsed[headerType] ~= fromNative then
                    layer.nativeCollapsed[headerType] = fromNative
                    layer.collapsedHeaders[headerType] = nil
                end
                local override = layer.collapsedHeaders[headerType]
                if override ~= nil then collapsed = override end
            end
            copy:SetCollapsed(collapsed, false, true)
            CopyChildren(layer, node, copy, true, nodes, previous)
        else
            -- TreeNodeMixin:Init creates an empty nodes table even for leaves.
            assert(Checked(next(CheckedTable(node:GetNodes()))) == nil, "unknown nested social row")
        end
    end
end

local function CanUse(frame)
    CheckedTable(frame)
    return not Checked(frame:IsForbidden()) and not Checked(frame:IsProtected())
        and (not frame.HasSecretValues or not Checked(frame:HasSecretValues()))
end

local Layer = {}

function Layer:Hide()
    self.cover:Hide()
    self.source, self.nodes = nil, nil
    -- Removing a provider can initialize/release frames. During combat the
    -- caller only needs the mouse/visual cover gone; replace data on refresh.
    if not Security.InCombatLockdown() and self.ScrollBox:HasDataProvider() then
        self.ScrollBox:RemoveDataProvider()
    end
end

local function Refresh(layer, provider, retain)
    layer.reason = "pane-unavailable"
    assert(not Security.InCombatLockdown() and CanUse(layer.pane.ScrollBox) and Checked(layer.pane.ScrollBox:IsVisible()))
    -- Keep the 85/87-unit native templates with enlarged text. Only build
    -- a second list in that mode when it is needed for sorting.
    layer.reason = "template-extent"
    if layer.compact then
        local baseHeight = Checked(layer.cardMixin.GetActiveBaseHeight())
        if baseHeight ~= 70 then
            if baseHeight ~= (layer.recent and 87 or 85) then return false end
            if not layer.sortFriends then layer.reason = "expanded-font"; return false end
            layer.compact = false
        end
    end
    layer.reason = "provider-copy"
    CheckedTable(provider)
    assert(type(Checked(retain)) == "boolean" or retain == nil)
    local tree, nodes = CreateTreeDataProvider(), {}
    local previous = layer.source == provider and layer.nodes
    CopyChildren(layer, provider:GetRootNode(), tree:GetRootNode(), false, nodes, previous)

    layer.reason = "template-extent"
    local owner = layer.owner
    owner:ClearTemplateExtentCache()
    for _, template in ipairs(layer.templates) do
        assert(Checked(owner:GetTemplateExtent(template)) > 0, "missing social template extent")
    end
    layer.failed = nil
    layer.reason = "provider-bind"
    layer.ScrollBox:SetDataProvider(tree, retain)
    layer.source, layer.nodes = provider, nodes
    if layer.failed then return false end
    layer.cover:Show()
    if layer.failed then return false end
    layer.reason = nil
    return true
end

function Layer:Refresh(provider, retainScrollPosition, compact, sortFriends)
    self.compact, self.sortFriends = compact, sortFriends
    local ok, shown = pcall(Refresh, self, provider, retainScrollPosition)
    if ok and shown then return true end
    self:Hide()
    return false
end

local function OnCardInitialized(layer, frame)
    if frame.LayoutScaledContent ~= layer.cardMixin.LayoutScaledContent then return end
    -- 71037 action buttons are 34x34. Scale the whole button (including
    -- its hit rect, icon, pressed art and optional summon cooldown). The
    -- centered 20x20 GameIconHolder already fits with its native +1 offset.
    local scale = layer.compact and 22 / 34 or 1
    frame.PartyButton:SetScale(scale)
    if frame.RAFSummonButton then frame.RAFSummonButton:SetScale(scale) end
    if layer.compact and layer.onInit then return layer.onInit(frame) end
end

local function OnCardReleased(layer, frame)
    if frame.LayoutScaledContent == layer.cardMixin.LayoutScaledContent and layer.onRelease then
        return layer.onRelease(frame)
    end
end

local function Dispatch(layer, callback, frame, reason)
    local ok, result = pcall(callback, layer, frame)
    if not ok or result == false then
        -- This can happen during wheel scrolling inside a locked view. Only
        -- hide here. Refresh/Hide can detach the provider outside the callback.
        if not layer.failed then layer.reason = reason end
        layer.failed = true
        layer.cover:Hide()
    end
end

local function Initialize(layer)
    local pane = layer.pane
    assert(not Security.InCombatLockdown() and CanUse(pane) and CanUse(pane.ScrollBox) and CanUse(pane.ScrollBar))
    local cover = CreateFrame("Frame", nil, pane)
    layer.cover = cover
    cover:Hide()
    cover:SetFrameLevel(math.max(Checked(pane.ScrollBox:GetFrameLevel()), Checked(pane.ScrollBar:GetFrameLevel())) + 32)
    cover:SetPoint("TOPLEFT", pane.ScrollBox)
    cover:SetPoint("BOTTOM", pane.ScrollBox)
    cover:SetPoint("RIGHT", pane)
    cover:EnableMouse(true)
    local background = cover:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 1)

    local box = CreateFrame("Frame", nil, cover, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, cover, "MinimalScrollBar")
    box:SetAllPoints(pane.ScrollBox)
    bar:SetAllPoints(pane.ScrollBar)
    layer.ScrollBox = box

    local preview = SocialUIScrollableElementExtentPreviewerMixin
    local owner = CreateFromMixins(preview)
    layer.owner = owner
    owner.ScrollBox, owner.ScrollBar = box, bar
    preview.OnLoad(owner)
    local cardTemplate = layer.recent and "RecentAlliesSocialCardTemplate" or "FriendsListSocialCardTemplate"
    layer.templates = { HEADER, SPACER, cardTemplate }
    owner.GetTemplateExtent = function(self, template)
        if layer.compact and template == cardTemplate then return CARD_HEIGHT end
        return preview.GetTemplateExtent(self, template)
    end

    local pageMixin = layer.recent and RecentAlliesSocialViewMixin or FriendsListSocialViewMixin
    layer.cardMixin = layer.recent and RecentAlliesSocialCardMixin or FriendsListSocialCardMixin
    if not layer.recent then
        -- Keep the collapse preference on the private view. The left click
        -- still needs the record to switch an open friends-of-friends window.
        owner.TrySwitchFriendsFriendsTarget = pageMixin.TrySwitchFriendsFriendsTarget
        owner.SaveHeaderCollapsedState = function(_, headerType, collapsed)
            layer.collapsedHeaders[headerType] = collapsed
        end
    end
    pageMixin.InitializeScrollBox(owner)
    -- 71037 runs row initializers via secureexecuterange. An error inside
    -- one initializer need not propagate out of SetDataProvider. Catch a
    -- missing completion when the batch finishes, including during scrolling.
    local pending = {}
    box:RegisterCallback(box.Event.OnAcquiredFrame, function(_, frame)
        -- Header and card factories queue an initializer. The spacer factory
        -- passes nil, so InvokeInitializers never visits its acquired frame.
        if frame.Initialize then pending[frame] = true end
    end, layer)
    box:RegisterCallback(box.Event.OnInitializedFrame, function(_, frame)
        pending[frame] = nil
        Dispatch(layer, OnCardInitialized, frame, "card-layout")
    end, layer)
    box:RegisterCallback(box.Event.OnReleasedFrame, function(_, frame)
        pending[frame] = nil
        Dispatch(layer, OnCardReleased, frame, "card-release")
    end, layer)
    box:RegisterCallback(box.Event.OnDataRangeChanged, function()
        if next(pending) and not layer.failed then
            layer.reason = "initializer-missing"
            layer.failed = true
            cover:Hide()
        end
    end, layer)
end

function Native:CreateSocialCompactView(pane, recent, onInit, onRelease)
    local layer = CreateFromMixins(Layer)
    layer.pane, layer.recent = pane, recent
    layer.nativeCollapsed, layer.collapsedHeaders = {}, {}
    layer.onInit, layer.onRelease = onInit, onRelease
    if pcall(Initialize, layer) then return layer end
    if layer.cover then layer.cover:Hide() end
end

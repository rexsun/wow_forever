local ADDON_NAME, YUI = ...
if not YUI.IsForever then return end
local Components, Event = YUI.Components, YUI.Event
local API, M, View = YUI.API.ProfessionAssistant, YUI.ProfessionAssistantModel, YUI.ProfessionAssistantView
local L = YUI.Locale:Get("ProfessionAssistant")
local PRODUCT = YUI:GetAddonProductId(ADDON_NAME, "suite") or "suite"
local KEY, MODULE = "ProfessionAssistant", "component.professionassistant"
local function ThemeStyle()
    local config = Components:EnsureConfig("ProfessionAssistant_Config", { themeStyle = "auto" }, PRODUCT)
    local style = config.themeStyle
    return (style == "native" or style == "dark") and style or "auto"
end
local owner, cleanupOwner = {}, {}
local active, batch, driver = false, false, false
local state, items, byGUID, filtered = M.New(), {}, {}, {}
local view, pending, timeout, attempt
local previewItems, savedState
local entries, bagHooks = {}, setmetatable({}, { __mode = "k" })
local eventCount, refreshCount, listeners = 0, 0, 0
local Refresh, Schedule, Open, Close, AttachBags, Render, AddPreviewItems

local function Message(key)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(L[key], 1, .82, 0) end
end
local function CancelTimer(which)
    if which then which:Cancel() end
end
local function EndAttempt()
    CancelTimer(timeout); timeout = nil
    if attempt and attempt.succeeded and not API.Exists(attempt.guid) then
        M.Complete(state, attempt.guid, attempt.loot)
    end
    attempt = nil
end
Close = function()
    batch = false
    CancelTimer(pending); pending = nil
    EndAttempt()
    if savedState then state = savedState end
    previewItems, savedState = nil, nil
    GameTooltip:Hide()
    if view and not API.InCombat() then
        view.left:Hide(); view.right:Hide(); view.root:Hide()
        if driver then UnregisterStateDriver(view.root, "combat"); driver = false end
    end
end

local function BeforeCast(host, item)
    if API.InCombat() then return end
    host:SetAttribute("type1", nil)
    host:SetAttribute("target-bag", nil)
    host:SetAttribute("target-slot", nil)
    if not active or not API.Known() or attempt or not item or item.preview or previewItems then return end
    if GetNumLootItems() > 0 or UnitCastingInfo("player") or UnitChannelInfo("player") then return end
    local live = API.Read(item.bag, item.slot)
    if not live or live.guid ~= item.guid then Schedule(); Message("changed"); return end
    host:SetAttribute("spell1", API.spellID)
    host:SetAttribute("target-bag", live.bag)
    host:SetAttribute("target-slot", live.slot)
    host:SetAttribute("type1", "spell")
    attempt = { guid = live.guid, item = live }
    -- Only one watchdog during an actual user-initiated cast; no idle polling.
    timeout = C_Timer.NewTimer(15, function()
        timeout = nil
        EndAttempt()
        Schedule()
    end)
end

Render = function()
    if view and batch and not API.InCombat() then View.Render(view, state, filtered, attempt ~= nil) end
end
local function ToggleItem(item)
    if attempt or API.InCombat() then return end
    local index = M.Contains(state, item.guid)
    if index then state.slots[index] = nil; Render(); return end
    local live = byGUID[item.guid]
    if live and M.Add(state, live) then Render() end
end
local function EnsureView()
    if view then return end
    view = View.Create({
        theme = ThemeStyle,
        close = Close, render = Render,
        preview = function() AddPreviewItems() end,
        getQuality = function() return state.quality end,
        quality = function(value) state.quality = value; view.offset = 0; Refresh(false) end,
        level = function(value)
            state.maxLevel = math.max(0, math.min(9999, tonumber(value) or 0))
            view.offset = 0; Refresh(true)
        end,
        remove = function(index)
            if attempt or API.InCombat() then return end
            if state.slots[index] and not state.slots[index].done then state.slots[index] = nil; Render() end
        end,
        add = ToggleItem,
        clear = function()
            if attempt or API.InCombat() then return end
            for i = 1, 9 do state.slots[i] = nil end
            Render()
        end,
        addBatch = function()
            if attempt or API.InCombat() then return end
            for _, item in ipairs(filtered) do if M.Capacity(state) == 0 then break end; M.Add(state, item) end
            Render()
        end,
        cast = function(host)
            local entry = batch and M.Next(state)
            BeforeCast(host, entry and entry.item)
        end,
    })
end
local function EnableDriver()
    EnsureView()
    if not driver then
        RegisterStateDriver(view.root, "combat", "[combat] 1; 0")
        driver = true
    end
end

local function OnBagShow() if active and not API.InCombat() then AttachBags(); Schedule() end end
AttachBags = function()
    if not active or API.InCombat() then return end
    local function Attach(container, showEntry)
        if not container then return end
        if not bagHooks[container] then
            bagHooks[container] = true
            container:HookScript("OnShow", OnBagShow)
        end
        if showEntry and not entries[container] then
            entries[container] = View.Entry(container, { click = function()
                if not active then return end
                if not API.Known() then Message("unknown"); return end
                Open()
            end })
        end
        if entries[container] then
            View.PlaceEntry(entries[container], container)
            entries[container]:SetShown(showEntry and active and API.Known())
        end
    end
    Attach(ContainerFrameCombinedBags, true)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local container = _G["ContainerFrame" .. i]
        Attach(container, container and container.GetBagID and container:GetBagID() == 0)
    end
end

Refresh = function(automatic)
    if not active or API.InCombat() then return end
    if not batch then return end
    refreshCount = refreshCount + 1
    if attempt and attempt.lootClosed and not API.Exists(attempt.guid) then EndAttempt() end
    if previewItems and YUI.IsDev ~= true then
        state, savedState, previewItems = savedState, nil, nil
    end
    if previewItems then
        items, byGUID = previewItems, {}
        for _, item in ipairs(items) do byGUID[item.guid] = item end
    else items, byGUID = API.Scan() end
    M.Reconcile(state, byGUID, attempt and attempt.guid)
    filtered = M.Filter(state, items, automatic)
    AttachBags()
    Render()
end
Schedule = function()
    if pending or not active or API.InCombat() or not batch then return end
    pending = C_Timer.NewTimer(.05, function() pending = nil; Refresh() end)
end
Open = function()
    if not active then return end
    if API.InCombat() then Message("combat"); return end
    if not API.Known() then Message("unknown"); return end
    EnableDriver()
    if not batch then
        state.maxLevel = UnitLevel("player")
        view.level:SetValue(tostring(state.maxLevel), true)
        view.offset = 0
    end
    batch = true
    View.Raise(view)
    view.root:Show(); view.left:Show(); view.right:Show()
    Refresh(true)
end

AddPreviewItems = function()
    if YUI.IsDev ~= true or not active or API.InCombat() or attempt then return end
    Open()
    if not batch then return end
    if not previewItems then
        savedState, previewItems = state, {}
        state = M.New()
        state.preview = true
        state.maxLevel = UnitLevel("player")
    end
    local first = #previewItems
    for i = first + 1, first + 10 do
        previewItems[i] = { guid = "Preview-" .. i, preview = true,
            name = string.format(L["dev.item"], i), icon = 132853, quality = 2,
            level = 1 + (i - 1) % math.max(1, UnitLevel("player")), boe = i % 2 == 0 }
    end
    state.quality = 2
    state.maxLevel = UnitLevel("player")
    view.level:SetValue(tostring(state.maxLevel), true)
    Refresh(true)
end

local function AcceptLoot()
    if attempt and M.OwnsLoot(attempt, attempt.sources or {}) then
        attempt.loot, attempt.ownsLoot = attempt.snapshot, true
        CancelTimer(timeout); timeout = nil
    end
end
local function OnEvent(event, ...)
    eventCount = eventCount + 1
    if event == "PLAYER_REGEN_DISABLED" then
        Close()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if view then
            view.left:Hide(); view.right:Hide(); view.root:Hide()
            if driver then UnregisterStateDriver(view.root, "combat"); driver = false end
        end
        AttachBags()
    elseif event == "ADDON_LOADED" or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        AttachBags()
    elseif event == "UNIT_SPELLCAST_START" then
        local unit, castGUID, spell = ...
        if unit == "player" and attempt and spell == API.spellID then attempt.castGUID = castGUID; Render() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spell = ...
        if unit == "player" and attempt and spell == API.spellID and (not attempt.castGUID or attempt.castGUID == castGUID) then
            attempt.castGUID, attempt.succeeded = castGUID, true
            AcceptLoot()
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, castGUID, spell = ...
        if unit == "player" and attempt and spell == API.spellID and (not attempt.castGUID or attempt.castGUID == castGUID) then
            EndAttempt(); Schedule()
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        if attempt then
            local loot, sources = API.Loot()
            -- Keep the earliest matching snapshot; auto-loot may already clear later events.
            if not attempt.ownsLoot and #sources > 0 then
                attempt.snapshot, attempt.sources = loot, sources
                AcceptLoot()
            end
        end
    elseif event == "LOOT_CLOSED" then
        if attempt and attempt.ownsLoot and not attempt.lootClosed then
            attempt.lootClosed = true
            if not API.Exists(attempt.guid) then EndAttempt()
            else
                -- Container updates may arrive after the loot window closes.
                timeout = C_Timer.NewTimer(5, function() timeout = nil; EndAttempt(); Schedule() end)
            end
            Schedule()
        end
    else Schedule() end
end

local function ReleaseSecure()
    if API.InCombat() then return end
    if view then
        view.root:Hide(); view.left:Hide(); view.right:Hide()
        if driver then UnregisterStateDriver(view.root, "combat"); driver = false end
    end
    for _, entry in pairs(entries) do entry:SetShown(active and API.Known()) end
    Event:OffOwner(cleanupOwner)
end
local function Toggle(enabled)
    Event:OffOwner(owner)
    listeners = 0
    Close()
    active = enabled == true
    state = M.New()
    state.maxLevel = UnitLevel("player")
    items, byGUID, filtered = {}, {}, {}
    if not API.InCombat() then
        for _, entry in pairs(entries) do entry:SetShown(active and API.Known()) end
    end
    if not active then
        if API.InCombat() then Event:On("PLAYER_REGEN_ENABLED", ReleaseSecure, cleanupOwner)
        else ReleaseSecure() end
        return
    end
    Event:OffOwner(cleanupOwner)
    local events = { "ADDON_LOADED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "GET_ITEM_INFO_RECEIVED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
    for _, event in ipairs(events) do
        Event:On(event, OnEvent, owner, event:match("^UNIT_") and { unit = "player" } or nil)
        listeners = listeners + 1
    end
    AttachBags()
end

local Feature = { id = KEY, name = L["name"], description = L["description"], default = true,
    tags = { "实用功能" }, order = 308,
    product = PRODUCT, storageKey = KEY, sourceRoot = "Components\\ProfessionAssistant", versions = { "forever" },
    assetFolders = { "Components\\ProfessionAssistant\\Media" },
    modSwitchImage = "modswitch\\professionassistant-bg.png", modSwitchImageCrop = false,
    toolboxManaged = true, settingsMode = "inline",
    callback = function(enabled) if enabled then YUI.Module:Enable(MODULE) else YUI.Module:Disable(MODULE) end end }
function Feature:GetOptions()
    local options = {
        { type = "button", label = L["enchanting"], width = 180, onClick = Open },
        { type = "dropdown", label = L["theme"], width = 180, get = ThemeStyle,
            options = { { text = L["theme.auto"], value = "auto" }, { text = L["theme.native"], value = "native" },
                { text = L["theme.dark"], value = "dark" } },
            set = function(value)
                local config = Components:EnsureConfig("ProfessionAssistant_Config", { themeStyle = "auto" }, PRODUCT)
                config.themeStyle = (value == "native" or value == "dark") and value or "auto"
                if view and not API.InCombat() then View.RefreshAppearance(view) end
            end },
    }
    if YUI.IsDev == true then
        table.insert(options, 2, { type = "button", label = L["dev.add"], width = 180, onClick = AddPreviewItems })
    end
    return options
end
function Feature:GetStats()
    return { active = active, listeners = listeners, timers = (pending and 1 or 0) + (timeout and 1 or 0),
        events = eventCount, refreshes = refreshCount, pending = pending ~= nil, casting = attempt ~= nil,
        queueCapacity = 9, inventoryPool = view and 25 or 0, idleTickers = 0 }
end
YUI.Module:Register({ id = MODULE, owner = owner, product = PRODUCT,
    dependencies = { "core.db", "core.event", "core.locale", "core.api" },
    getEnabled = function() return Components:IsEnabled(KEY) end,
    OnEnable = function() Toggle(true) end,
    OnDisable = function() Toggle(false) end,
    OnProfileChanged = function() Toggle(Components:IsEnabled(KEY)) end })
Components:RegisterFeature(KEY, Feature)

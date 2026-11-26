-- You Don't Need This - bag marks and automatic alerts
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.
--
-- Marks: a red tint and a red X on every bag slot holding an item you don't need.
-- Works with the default bags, Bagnon (tint + X) and Baganator (X as a corner icon).
-- Alerts: one summary line after login, then a message whenever an item becomes
-- unneeded (you turned in its last quest) or you loot one you don't need.
-- Both are driven by ns.Refresh, which YouDontNeedThis.lua calls (throttled) after
-- quest log, bag and turn-in events. Nothing is ever deleted or sold.

local _, ns = ...

local GetSlotItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local GetSlotItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

local function Settings() return ns.DB().settings end

------------------------------------------------------------------------
-- Bag marks
------------------------------------------------------------------------
-- Forever uses the modern bag frames: ContainerFrame1..N (one per bag) and
-- ContainerFrameCombinedBags (all bags in one window). Older layouts name their
-- buttons <Frame>Item<N>; cover those too.
local function BagFrames()
    local list = {}
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then list[#list + 1] = frame end
    end
    if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
    return list
end

local function ButtonsOf(frame)
    local list = {}
    if frame.EnumerateValidItems then
        for _, button in frame:EnumerateValidItems() do list[#list + 1] = button end
    elseif frame.Items then
        for _, button in ipairs(frame.Items) do list[#list + 1] = button end
    elseif frame:GetName() then
        for i = 1, (frame.size or 36) do
            local button = _G[frame:GetName() .. "Item" .. i]
            if button then list[#list + 1] = button end
        end
    end
    return list
end

local function SetMark(button, show)
    local mark = button.ydntMark
    if not mark then
        if not show then return end
        local icon = button.icon or button.Icon or button.IconTexture -- IconTexture: AdiBags
            or (button:GetName() and _G[button:GetName() .. "IconTexture"]) or button
        local tint = button:CreateTexture(nil, "OVERLAY", nil, 6)
        tint:SetColorTexture(1, 0, 0, 0.35)
        tint:SetAllPoints(icon)
        local cross = button:CreateTexture(nil, "OVERLAY", nil, 7)
        cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up") -- the red X from loot rolls
        cross:SetSize(16, 16)
        cross:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1)
        mark = { tint = tint, cross = cross }
        button.ydntMark = mark
    end
    mark.tint:SetShown(show)
    mark.cross:SetShown(show)
end
ns.SetMark = SetMark

-- Other bag addons (Integrations.lua) add a function here; MarkAllBags calls each one with
-- changed = true when the set of unneeded items (or a setting) changed since the last scan.
ns.refreshHooks = {}

-- Bag buttons are reused for other bags/slots, so every redraw re-evaluates each one.
local function MarkFrame(frame)
    if not (frame and frame:IsShown()) then return end
    local on = Settings().marks
    for _, button in ipairs(ButtonsOf(frame)) do
        local show = false
        if on and button:IsShown() then
            local bag = button.GetBagID and button:GetBagID() or frame:GetID()
            local itemID = bag and GetSlotItemID(bag, button:GetID())
            show = itemID ~= nil and ns.ItemStatus(itemID) == true
        end
        SetMark(button, show)
    end
end

------------------------------------------------------------------------
-- Bagnon: its item buttons (from BagBrother) call the global SetItemButtonTexture at the end
-- of every update and carry their item in button.info. Buttons showing another character's
-- cached bags are skipped, since quest completion is only known for this character.
------------------------------------------------------------------------
local bagnonButtons = setmetatable({}, { __mode = "k" })

local function MarkBagnonButton(button)
    local show = false
    if Settings().marks and not (button.IsCached and button:IsCached()) then
        local itemID = button.info.itemID
        show = itemID ~= nil and ns.ItemStatus(itemID) == true
    end
    SetMark(button, show)
end

if SetItemButtonTexture then
    hooksecurefunc("SetItemButtonTexture", function(button)
        if ns.loggedIn and type(button) == "table" and type(button.info) == "table" and button.GetBag then
            bagnonButtons[button] = true
            MarkBagnonButton(button)
        end
    end)
end

------------------------------------------------------------------------
-- Baganator: draws its own buttons, but lets addons add a "corner widget" icon.
-- We add the red X in the top-right corner (no tint; Baganator owns the slot art).
------------------------------------------------------------------------
local baganator

local function HookBaganator()
    local api = type(Baganator) == "table" and type(Baganator.API) == "table" and Baganator.API
    if baganator or not (api and api.RegisterCornerWidget) then return end
    local ok = pcall(api.RegisterCornerWidget, "You Don't Need This", "youdontneedthis",
        function(_, details) -- true = show, false = hide
            if not Settings().marks or not details then return false end
            local itemID = details.itemID or (details.itemLink and tonumber(details.itemLink:match("item:(%d+)")))
            return itemID ~= nil and ns.ItemStatus(itemID) == true
        end,
        function(button) -- creates the icon once per Baganator button
            local cross = button:CreateTexture(nil, "OVERLAY")
            cross:SetSize(16, 16)
            cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            return cross
        end,
        { corner = "top_right", priority = 1 })
    if ok then baganator = api end
end

------------------------------------------------------------------------
-- Default bank: the main bank slots are separate buttons (BankFrameItem1..N, or BankSlotsFrame.ItemN
-- on retail-style UIs) that always show bag -1. The bank bags open as ContainerFrames, covered above.
------------------------------------------------------------------------
local BANK = BANK_CONTAINER or -1

local function MarkBankButton(button)
    if not button or button.isBag then return end
    local show = false
    if Settings().marks and button:IsShown() then
        local itemID = GetSlotItemID(BANK, button:GetID())
        show = itemID ~= nil and ns.ItemStatus(itemID) == true
    end
    SetMark(button, show)
end

local function MarkBankSlots()
    if not (BankFrame and BankFrame:IsShown()) then return end
    for i = 1, (NUM_BANKGENERIC_SLOTS or 28) do
        MarkBankButton(_G["BankFrameItem" .. i] or (BankSlotsFrame and BankSlotsFrame["Item" .. i]))
    end
end

local function MarkAllBags(changed)
    for _, frame in ipairs(BagFrames()) do MarkFrame(frame) end
    MarkBankSlots()
    for _, hook in ipairs(ns.refreshHooks) do pcall(hook, changed) end
    for button in pairs(bagnonButtons) do
        if button:IsVisible() and type(button.info) == "table" then MarkBagnonButton(button) end
    end
    if baganator and baganator.RequestItemButtonsRefresh then pcall(baganator.RequestItemButtonsRefresh) end
end

------------------------------------------------------------------------
-- Alerts
------------------------------------------------------------------------
local loggedIn = false
local known -- [itemID] = true for unneeded items already in the bags; nil until the first scan

local function Alert(text)
    print(ns.PREFIX .. text)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.35, 0.35) end
end

local function ScanBags()
    local status, links = {}, {}
    ns.ForEachBagItem(function(itemID, bag, slot)
        if status[itemID] == nil then
            status[itemID] = ns.ItemStatus(itemID) == true
            if status[itemID] then links[itemID] = GetSlotItemLink(bag, slot) end
        end
    end)
    local unneeded = {}
    for itemID, isUnneeded in pairs(status) do
        if isUnneeded then unneeded[itemID] = true end
    end
    return unneeded, links
end

local function SameSet(a, b)
    if not (a and b) then return false end
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

-- announce = false: only redraw and remember the current state (e.g. after a settings toggle).
-- force = true: tell the other bag addons to redraw even if the set of unneeded bag items is the
-- same (an override or setting can change items in the bank, too).
function ns.Refresh(announce, force)
    if not loggedIn then return end
    local unneeded, links = ScanBags()
    MarkAllBags(force or not SameSet(known, unneeded))

    local alerts = Settings().alerts
    if known == nil then
        local count = 0
        for _ in pairs(unneeded) do count = count + 1 end
        local inBank = 0
        for itemID in pairs(ns.DB().bank) do
            if not unneeded[itemID] and ns.ItemStatus(itemID) == true then inBank = inBank + 1 end
        end
        if alerts and count + inBank > 0 then
            local where = ("%d item%s in your bags"):format(count, count == 1 and "" or "s")
            if inBank > 0 then where = where .. (" and %d in your bank"):format(inBank) end
            print(ns.PREFIX .. where .. " you don't need anymore (marked red). Type /ydnt list to see them.")
        end
    elseif announce and alerts then
        for itemID in pairs(unneeded) do
            if not known[itemID] then
                Alert("You don't need " .. (links[itemID] or ("item " .. itemID)) .. " anymore.")
            end
        end
    end
    known = unneeded
end

------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    loggedIn = true
    ns.loggedIn = true
    if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", MarkFrame) end
    for _, frame in ipairs(BagFrames()) do
        if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", MarkFrame) end
        frame:HookScript("OnShow", MarkFrame)
    end
    if BankFrameItemButton_Update then hooksecurefunc("BankFrameItemButton_Update", MarkBankButton) end
    if BankFrame then BankFrame:HookScript("OnShow", MarkBankSlots) end
    HookBaganator()
end)

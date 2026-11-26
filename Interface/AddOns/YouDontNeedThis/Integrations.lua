-- You Don't Need This - AdiBags and ArkInventory support
-- Copyright (C) 2026 Nick. Licensed under the GNU GPL v3 or later; see LICENSE.md.
--
-- AdiBags: a "You Don't Need This" section (a filter, toggled in AdiBags' own options) plus the red
-- tint and X on its buttons. ArkInventory: the red tint and X on its item frames.
-- Both redraw only when the set of unneeded items changes (ns.refreshHooks, called from Bags.lua).
-- Bagnon and Baganator are handled in Bags.lua.

local _, ns = ...

local SECTION = "You Don't Need This"

local function Unneeded(itemID) return itemID ~= nil and ns.ItemStatus(itemID) == true end
local function MarksOn() return ns.DB().settings.marks end

------------------------------------------------------------------------
-- AdiBags (API from its own modules: RegisterFilter + filter:Filter(slotData), and the
-- AdiBags_UpdateButton message with button.itemId / button.IconTexture)
------------------------------------------------------------------------
local adiDone = false

local function SetupAdiBags()
    if adiDone then return end
    local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local adi = AceAddon and AceAddon:GetAddon("AdiBags", true)
    if not (adi and adi.RegisterFilter and adi.NewModule) then return end
    adiDone = true

    -- Priority 90: above AdiBags' Junk (85) and item-category filters, below Manual filtering (95).
    local filter = adi:RegisterFilter("YouDontNeedThis", 90, "ABEvent-1.0")
    filter.uiName = SECTION
    filter.uiDesc = "Put quest items you don't need anymore (every quest that uses them is completed) in their own section."
    function filter:Filter(slotData)
        if Unneeded(slotData.itemId) then return SECTION end
    end

    local marked = setmetatable({}, { __mode = "k" })
    local marks = adi:NewModule("YouDontNeedThisMarks", "ABEvent-1.0")
    marks.uiName = SECTION .. " marks"
    marks.uiDesc = "Red tint and a red X on quest items you don't need anymore."
    function marks:OnEnable()
        self:RegisterMessage("AdiBags_UpdateButton", "UpdateButton")
        self:SendMessage("AdiBags_UpdateAllButtons")
    end
    function marks:OnDisable()
        for button in pairs(marked) do ns.SetMark(button, false) end
    end
    function marks:UpdateButton(_, button)
        marked[button] = true
        ns.SetMark(button, MarksOn() and Unneeded(button.itemId) or false)
    end

    ns.refreshHooks[#ns.refreshHooks + 1] = function(changed)
        if not changed then return end
        filter:SendMessage("AdiBags_FiltersChanged")
        filter:SendMessage("AdiBags_UpdateAllButtons")
    end
end

------------------------------------------------------------------------
-- ArkInventory (its documented ArkInventory.API: ItemFrameUpdated hook, ItemFrameItemTableGet,
-- ItemFrameLoadedIterate, LocationIsOffline). Offline views (other characters, or the bank when
-- it's closed) are skipped, since quest completion is only known for this character.
------------------------------------------------------------------------
local arkDone = false

local function SetupArkInventory()
    local api = not arkDone and type(ArkInventory) == "table" and type(ArkInventory.API) == "table" and ArkInventory.API
    if not (api and api.ItemFrameUpdated and api.ItemFrameItemTableGet) then return end
    arkDone = true

    local function Mark(frame, loc_id)
        if not frame then return end
        local show = false
        if MarksOn() and not (api.LocationIsOffline and api.LocationIsOffline(loc_id)) then
            local i = api.ItemFrameItemTableGet(frame)
            show = Unneeded(i and ns.ItemIDFromLink(i.h))
        end
        ns.SetMark(frame, show)
    end

    hooksecurefunc(api, "ItemFrameUpdated", Mark)

    if api.ItemFrameLoadedIterate then
        ns.refreshHooks[#ns.refreshHooks + 1] = function(changed)
            if not changed then return end
            for _, frame, loc_id in api.ItemFrameLoadedIterate() do
                if frame:IsVisible() then Mark(frame, loc_id) end
            end
        end
    end
end

------------------------------------------------------------------------
-- AdiBags plugins register while loading (AdiBags is an OptionalDep, so it's loaded before us);
-- the ADDON_LOADED fallback covers anything loaded later.
------------------------------------------------------------------------
SetupAdiBags()

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "AdiBags" then SetupAdiBags() end
    if event == "PLAYER_LOGIN" or name == "ArkInventory" then SetupArkInventory() end
end)

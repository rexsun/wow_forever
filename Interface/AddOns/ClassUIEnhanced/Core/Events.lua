
--[[
    This file handles game events that can be shared among components.
    It does not handle events that are specific to a component, like SPELL_CAST_START for the Cast Bar component
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field zoneType string the type of the zone the player is currently is
---@field zoneName string the name of the zone the player is currently in
---@field Events events namespace

---@class events : table
---@field ZONE_CHANGED_NEW_AREA fun(...) Event triggered when the player changes to a new area (all WoW flavors)
---@field PLAYER_REGEN_DISABLED fun(...) Event triggered when the player enters combat (all WoW flavors)
---@field PLAYER_REGEN_ENABLED fun(...) Event triggered when the player leaves combat (all WoW flavors)
---@field PLAYER_MOUNT_DISPLAY_CHANGED fun(...) Event triggered when mount state changes (mount/dismount)
---@field UNIT_ENTERED_VEHICLE fun(unit: string) Event triggered when a unit enters a vehicle
---@field UNIT_EXITED_VEHICLE fun(unit: string) Event triggered when a unit exits a vehicle
---@field PET_BATTLE_OPENING_START fun() Event triggered when entering a pet battle
---@field PET_BATTLE_CLOSE fun() Event triggered when leaving a pet battle
---@field UPDATE_OVERRIDE_ACTIONBAR fun() Event triggered when override action bar changes
---@field CLIENT_SCENE_OPENED fun(sceneType: number) Event triggered when a client scene opens (barbershop, etc.)
---@field CLIENT_SCENE_CLOSED fun() Event triggered when a client scene closes
---@field PLAYER_TARGET_CHANGED fun() Event triggered when the player's target changes
---@field ACTIVE_PLAYER_SPECIALIZATION_CHANGED fun() Event triggered when the player changes specialization
---@field ACTIVE_TALENT_GROUP_CHANGED fun(curr: number, prev: number) Event triggered when the player activates the other dual-spec talent group

--ATTENTION: The callback ID (exemple: "OnZoneChange") is defined in InternalCallback.lua

--functions to run when a registered event happens
---@type events
local events = {
    ["ZONE_CHANGED_NEW_AREA"] = function(...) --this event exists in all wow flavors
        local zoneName, zoneType = GetInstanceInfo()
        private.zoneName = zoneName
        --zone type is one of the following strings: "none", "party", "raid", "pvp", "arena", "scenario", "battlefield"
        private.zoneType = zoneType
        private.Callback.Trigger("OnZoneChange")
    end,

    ["PLAYER_REGEN_DISABLED"] = function(...) --this event exists in all wow flavors
        private.Callback.Trigger("OnEnterCombat")
    end,

    ["PLAYER_REGEN_ENABLED"] = function(...) --this event exists in all wow flavors
        private.Callback.Trigger("OnLeaveCombat")
    end,

    ["PLAYER_MOUNT_DISPLAY_CHANGED"] = function(...) --fires when mount state changes (mount/dismount)
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["PLAYER_TARGET_CHANGED"] = function() --fires when the player's target changes
        private.Callback.Trigger("OnTargetChange")
    end,

    ["UPDATE_SHAPESHIFT_FORM"] = function() --fires when shapeshift form changes (druid forms, etc.)
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["UNIT_ENTERED_VEHICLE"] = function(unit) --fires when a unit enters a vehicle
        if unit == "player" then
            private.Callback.Trigger("OnMountStateChange")
        end
    end,

    ["UNIT_EXITED_VEHICLE"] = function(unit) --fires when a unit exits a vehicle
        if unit == "player" then
            private.Callback.Trigger("OnMountStateChange")
        end
    end,

    ["PET_BATTLE_OPENING_START"] = function() --fires when entering a pet battle
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["PET_BATTLE_CLOSE"] = function() --fires when leaving a pet battle
        private.Callback.Trigger("OnMountStateChange")
        -- IsCooldownViewerAvailable() may not update immediately after pet
        -- battle ends; schedule a second refresh to catch the delayed
        -- transition (no COOLDOWN_VIEWER_AVAILABILITY_CHANGED event exists).
        C_Timer.After(1, function()
            private.Callback.Trigger("OnMountStateChange")
        end)
    end,

    ["UPDATE_OVERRIDE_ACTIONBAR"] = function() --fires when override action bar changes (minigames, etc.)
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["CLIENT_SCENE_OPENED"] = function(sceneType) --fires when a client scene opens (barbershop, etc.)
        -- DefaultSceneType (0) fires for brief cinematics (delve intros, etc.)
        -- that never send CLIENT_SCENE_CLOSED. Only hide UI for interactive scenes
        -- like MinigameSceneType (1) which reliably fire CLOSED when they end.
        if sceneType == 0 then return end
        private.inClientScene = true
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["CLIENT_SCENE_CLOSED"] = function() --fires when a client scene closes
        private.inClientScene = false
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["LOADING_SCREEN_DISABLED"] = function() --fires after every loading screen completes
        -- After a /reload inside a minigame client scene, CLIENT_SCENE_OPENED does not
        -- re-fire. Detect the scene by checking UIParent visibility — Blizzard hides it
        -- for interactive scenes. For normal loading screens (zone transitions, login)
        -- UIParent is shown, so this correctly clears the flag.
        private.inClientScene = not UIParent:IsShown()
        private.Callback.Trigger("OnMountStateChange")
    end,

    ["ACTIVE_PLAYER_SPECIALIZATION_CHANGED"] = function() --fires when the player changes specialization
        private.Callback.Trigger("OnSpecializationChanged")
    end,

    ["ACTIVE_TALENT_GROUP_CHANGED"] = function() --fires when the player activates the other dual-spec talent group
        -- Only with no spec system (WoW Forever), where the talent group is what
        -- a spec change means. Retail keeps the spec event above as its trigger.
        if GetNumSpecializations() <= 1 then
            private.Callback.Trigger("OnSpecializationChanged")
        end
    end,

    ["PLAYER_ENTERING_WORLD"] = function() --fires after login, reload, and zone transitions
        -- Re-detect client scene state in case event ordering differs from
        -- LOADING_SCREEN_DISABLED (UIParent is hidden during interactive scenes).
        private.inClientScene = not UIParent:IsShown()
        private.Callback.Trigger("OnMountStateChange")
    end,
}

---this frame listens to game events and dispatches them to the appropriate handlers
---@type frame
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, eventName, ...)
    if (events[eventName]) then
        events[eventName](...)
    end
end)

--register the events
for eventName in pairs(events) do --warning: no check for events that does not exist in the wow flavor
    eventFrame:RegisterEvent(eventName)
end

private.Events = events

--LibSharedMedia late-registration hook
--when other addons register fonts or textures after our initial refresh,
--re-apply them so the user's chosen media resolves correctly
local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)
if LibSharedMedia then
    local pendingRefresh = false
    local lsmCallbackTarget = {}
    LibSharedMedia.RegisterCallback(lsmCallbackTarget, "LibSharedMedia_Registered", function(_, mediaType)
        if mediaType ~= "font" and mediaType ~= "statusbar" then return end
        if pendingRefresh then return end
        pendingRefresh = true
        C_Timer.After(0, function()
            pendingRefresh = false
            if private.ComponentManager then
                private.ComponentManager.RefreshAllComponents()
            end
        end)
    end)
end
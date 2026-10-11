
--[[
    Dispatch any internal callbacks
    The use of internal callbacks is to avoid functions in one component calling functions in another component directly
    This creates a loose coupling between components, making them more modular and easier to maintain

    To create a new callback:
    - Add the event name to the callbacknames alias, this will make the auto complete show the available callback names
    - Add a new entry to the callbackTypes table

    Then scripts can register to receive the callback like this:
    private.Callback.Register("OnZoneChange", function()
        --your code here
    end)

    And scripts can trigger a callback like this:
    private.Callback.Trigger("OnZoneChange", additional, arguments, here)
--]]


local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

---@class private : table
---@field Callback internalcallback

---@class internalcallback : table
---@field Register fun(callbackName: callbacknames, func: fun()):boolean Registers a callback function for the specified callback type
---@field Unregister fun(callbackName: callbacknames, func: fun()):boolean Unregisters a callback function for the specified callback type
---@field Trigger fun(callbackName: callbacknames, ...) Triggers all registered callback functions for the specified callback type, passing any additional arguments to the functions

---@alias callbacknames
---| "OnZoneChange"
---| "OnEnterCombat"
---| "OnLeaveCombat"
---| "OnMountStateChange"
---| "OnComponentEnable"
---| "OnComponentDisable"
---| "OnProfileChanged"
---| "OnTargetChange"
---| "OnSpecializationChanged"
---| "OnCDMSpellsChanged"
---| "OnCDMAlertsChanged"
---| "OnAlertModelRebuilt"
---| "OnKeybindsChanged"
---| "OnSpellNamesResolved"

local callbackTypes = {
    ["OnZoneChange"] = true,
    ["OnEnterCombat"] = true,
    ["OnLeaveCombat"] = true,
    ["OnMountStateChange"] = true,
    ["OnComponentEnable"] = true,
    ["OnComponentDisable"] = true,
    ["OnProfileChanged"] = true,
    ["OnTargetChange"] = true,
    ["OnSpecializationChanged"] = true,
    ["OnCDMSpellsChanged"] = true,
    ["OnCDMAlertsChanged"] = true,
    ["OnAlertModelRebuilt"] = true,
    ["OnKeybindsChanged"] = true,
    ["OnSpellNamesResolved"] = true,
}

---@type table<callbacknames, function[]>
local registeredCallbacks = {}

for callbackType in pairs(callbackTypes) do
    registeredCallbacks[callbackType] = {}
end

---@type internalcallback
local callback = {
    Register = function(callbackName, func)
        if (not callbackTypes[callbackName]) then
            error("Invalid callback type: " .. tostring(callbackName))
        end
        framework.table.addunique(registeredCallbacks[callbackName], func)
        return true
    end,

    Unregister = function(callbackName, func)
        if (not callbackTypes[callbackName]) then
            error("Invalid callback type: " .. tostring(callbackName))
        end

        for index, registeredFunc in ipairs(registeredCallbacks[callbackName]) do
            if (registeredFunc == func) then
                table.remove(registeredCallbacks[callbackName], index)
                return true
            end
        end

        return false
    end,

    ---Dispatch over a SNAPSHOT, never the live array. `Unregister` is a
    ---`table.remove` and handlers routinely call it on themselves first thing (8
    ---of the 15 `OnLeaveCombat` registrations do, to retire a one-shot task), so a
    ---live `ipairs` walk skips the handler after each self-remover — silently, with
    ---no error and nothing to grep for. See `tests/callbackdispatch_check.lua`.
    ---
    ---ponytail: copies the array per dispatch. These are state transitions, not
    ---per-frame paths. If one ever lands on a per-frame path, move to a per-NAME
    ---scratch buffer — `Trigger` is re-entrant, so one shared buffer is not enough.
    Trigger = function(callbackName, ...)
        if (not callbackTypes[callbackName]) then
            error("Invalid callback type: " .. tostring(callbackName))
        end

        local registered = registeredCallbacks[callbackName]
        local snapshot = {}
        for index = 1, #registered do
            snapshot[index] = registered[index]
        end

        for index = 1, #snapshot do
            snapshot[index](...)
        end
    end,
}

private.Callback = callback
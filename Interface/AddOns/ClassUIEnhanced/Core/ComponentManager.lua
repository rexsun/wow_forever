
-- Component manager: registers components, toggles enabled state, delegates OnEnable/OnDisable.

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field ComponentManager componentmanager

---the name of each component, these are also table names in the private table
---@alias componentname
---| "BuffTracker"
---| "BuffTrackerBars"
---| "CooldownTracker"
---| "TrinketTracker"
---| "RacialTracker"
---| "ConsumableTracker"
---| "ConsumableBuffTracker"
---| "RaidBuffTracker"
---| "OutboundBuffTracker"
---| "UtilitiesTracker"
---| "PlayerCastBar"
---| "TargetCastBar"
---| "FocusCastBar"
---| "GlobalCooldown"
---| "PrimaryResources"
---| "SecondaryResources"

---function in the component class exists in all components and they are declared within the component file
---@class component : table
---@field name componentname
---@field Initialize fun() Initializes the component
---@field Refresh fun() Refreshes the component
---@field OnEnable fun() Called when the component is enabled
---@field OnDisable fun() Called when the component is disabled
---@field GetComponentName fun() : componentname Get the name of the component
---@field GetComponentSize fun() : number, number Return when width and height the component using in the UIParent, used on the anchor system
---@field GetEnabled fun() : boolean Returns the effective enabled state; may return false due to class/spec constraints even when settings.enabled is true
---@field GetSettings fun() : component_profile_main Get the profile table for the component
---@field GetFrame fun() : frame? Get the main frame of the component

---@class componentmanager : table
---@field GetComponent fun(componentName: componentname|string) : component Gets a registered component by its name
---@field RegisterComponent fun(componentName: componentname|string, componentTable: table) Registers a component
---@field UnregisterComponent fun(componentName: string) Removes a dynamically registered component (e.g. additional frames on deletion)
---@field RefreshAllComponents fun() Refreshes all components
---@field GetAllComponents fun() : component[] Returns a table with all registered components
---@field EnableComponent fun(componentName: componentname|string) Enables a component by its name, calls OnEnable() on the component
---@field DisableComponent fun(componentName: componentname|string) Disables a component by its name, calls OnDisable() on the component

---@type table<componentname, component>
local allComponents = {}

--components in register order
---@type component[]
local registeredComponentsInOrder = {}


---@type componentmanager
local componentManager = {
    ---@param componentName componentname
    ---@return component
    GetComponent = function(componentName)
        assert(type(componentName) == "string", "Component name must be a string.")
        return allComponents[componentName]
    end,

    RefreshAllComponents = function()
        private.fontsDirty = true
        for _, componentTable in ipairs(registeredComponentsInOrder) do
            componentTable.Refresh()
        end
        private.fontsDirty = false
    end,

    ---@param componentName componentname|string
    ---@param componentTable component
    RegisterComponent = function(componentName, componentTable)
        allComponents[componentName] = componentTable
        registeredComponentsInOrder[#registeredComponentsInOrder+1] = componentTable
    end,

    ---Remove a dynamically registered component. Used when deleting additional frames.
    ---@param componentName string
    UnregisterComponent = function(componentName)
        allComponents[componentName] = nil
        for i = #registeredComponentsInOrder, 1, -1 do
            if registeredComponentsInOrder[i].name == componentName then
                table.remove(registeredComponentsInOrder, i)
                break
            end
        end
    end,

    ---@return component[]
    GetAllComponents = function()
        return registeredComponentsInOrder
    end,

    ---@param componentName componentname
    EnableComponent = function(componentName)
        local component = allComponents[componentName]
        assert(component, "Component '" .. componentName .. "' is not registered in the Component Manager.")

        ---@type component_profile_main
        local profileTable = component.GetSettings()
        profileTable.enabled = true

        component.OnEnable()

        --sent callback that a component was enabled
        private.Callback.Trigger("OnComponentEnable", componentName)
    end,

    ---@param componentName componentname
    DisableComponent = function(componentName)
        local component = allComponents[componentName]
        assert(component, "Component '" .. componentName .. "' is not registered in the Component Manager.")

        ---@type component_profile_main
        local profileTable = component.GetSettings()
        profileTable.enabled = false

        component.OnDisable()

        --sent callback that a component was disabled
        private.Callback.Trigger("OnComponentDisable", componentName)
    end,

}

private.ComponentManager = componentManager
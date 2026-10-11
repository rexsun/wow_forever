
--[[
    UIDefaults.lua
    
    This file contains default configuration values for the ClassUIEnhanced options panel UI elements.
    
    It serves as the central repository for all default settings used in constructing the
    options panel interface. The defaults define:
    
    - UI element templates (checkboxes, sliders, dropdowns, buttons, fonts)
    - Zebra striping colors for alternating rows in lists
    - Column layout configurations for multi-column panels
    - Default positioning and sizing parameters
    - Color schemes and visual appearance settings
    - Component-specific default values
    
    These defaults are used in the construction of the options panel to ensure consistent UI appearance.
    Values set here are not user-configurable, do not belong on the profile, and are not saved to disk.

    When defining new UI elements settings, follow the rules:
    - Use descriptive keys that clearly indicate the purpose of each default value.
    - Group related settings together in nested tables for better organization.
        - Avoid hardcoding values directly in the UI construction code; instead, reference the defaults defined here.
        - Document each default value with comments explaining its purpose and usage.
    - Prefer reuse defaults that can be applied across multiple UI elements to maintain consistency.
        - E.g.: All zebra striping must use the same color values defined in the zebraStriping table.
--]]

local _
---@type string, private
local addonName, private = ...

local uIDefaults = {
    presets = {
        checkbox = "OPTIONS_CHECKBOX_TEMPLATE",
        slider = "OPTIONS_SLIDER_TEMPLATE",
        dropdown = "OPTIONS_DROPDOWN_TEMPLATE",
        button = "OPTIONS_BUTTON_TEMPLATE",
        font = "OPTIONS_FONT_TEMPLATE",
        fontHeader = "ORANGE_FONT_TEMPLATE",
    },

    zebraStriping = {
        -- Color 1 (even)
        color1 = {0, 0, 0, 0.09},
        -- Color 2 (odd)
        color2 = {0.05, 0.05, 0.05, 0.1},
    },

    lines = {
        hoverColor = {0.1, 0.1, 0.1, 0.1},
    },

    colorColumns = {
        -- Column dimensions
        columnWidth = 220,
        columnHeight = 500,
        
        -- Column spacing (x offset between columns)
        columnSpacing = 240,
        
        -- Starting x position for first column
        startXOffset = 0,

        -- Starting y position for all columns (relative to description font string)
        startYOffset = -15,
    },
}

private.UIDefaults = uIDefaults

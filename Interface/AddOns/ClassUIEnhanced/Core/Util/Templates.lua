
local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field Templates template

---@class template : table
---@field RoundedCornerPreset table
---@field TitleTexture string
---@field OptionsPanel table
---@field ButtonTemplate table

---@type template
local templates = {
    RoundedCornerPreset = {
        roundness = 5,
        color = {.075, .075, .075, 1},
        border_color = {.05, .05, .05, 1},
        horizontal_border_size_offset = 8,
    },
    TitleTexture = "Interface\\AddOns\\" .. addonName .. "\\Assets\\Textures\\logo.png",
    OptionsPanel = {
        width = 1000,
        height = 600,
    },
    ButtonTemplate = {
        backdrop = {edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true},
        backdropcolor = {0.1, 0.1, 0.1, 0.9},
        backdropbordercolor = {0.3, 0.3, 0.3, 0.8},
        onentercolor = {0.15, 0.15, 0.15, 0.9},
        onenterbordercolor = {0.45, 0.45, 0.45, 0.9},
    },
}

private.Templates = templates

local YUI = _G.YUI
local S = YUI.Settings
local LC = YUI.Locale:Get("Core")

local function GetConfig()
    -- Retail Version (Mainline)
    if YUI.IsRetail then
        return {
            {type = "header", label = LC["settings.help.title"]},
            {type = "space", height = 10}, 
            {
                type = "text",
                label = LC["help.text.001"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.002"],
                justify = "LEFT"
            }, {type = "space", height = 15}, 
            {
                type = "text",
                label = LC["help.text.003"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.004"],
                justify = "LEFT"
            }, {type = "space", height = 15}, 
            {
                type = "text",
                label = LC["help.text.005"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.006"],
                justify = "LEFT"
            }, {type = "space", height = 15}, 
            {
                type = "text",
                label = LC["help.text.007"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.008"],
                justify = "LEFT"
            }, {type = "space", height = 15}, 
            {
                type = "text",
                label = LC["help.text.009"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.010"],
                justify = "LEFT"
            }, {type = "space", height = 15}, 
            {
                type = "text",
                label = LC["help.text.011"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.012"],
                justify = "LEFT"
            }, {type = "space", height = 15}, 
            {
                type = "text",
                label = LC["help.text.013"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.014"],
                justify = "LEFT"
            }, {type = "space", height = 15}
        }

        -- Wrath Version (WotLK Classic)
    elseif YUI.IsWrath then
        return {
            {type = "header", label = LC["settings.help.title"]},
            {type = "space", height = 10}, {
                type = "text",
                label = LC["help.text.015"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.016"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.017"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.018"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.019"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.020"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.021"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.022"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.023"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.024"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.025"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.026"],
                justify = "LEFT"
            }, {type = "space", height = 15}
        }

        -- Mist Version (MoP)
    elseif YUI.IsMists then
        return {
            {type = "header", label = LC["settings.help.title"]},
            {type = "space", height = 10}, {
                type = "text",
                label = LC["help.text.015"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.016"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.017"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.018"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.019"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.020"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.021"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.022"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.023"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.024"],
                justify = "LEFT"
            }, {type = "space", height = 15}, {
                type = "text",
                label = LC["help.text.025"],
                style = "header",
                colorKey = "color.text.heading",
                justify = "LEFT"
            }, {
                type = "text",
                label = LC["help.text.026"],
                justify = "LEFT"
            }, {type = "space", height = 15}
        }

        -- Default / Other
    else
        return {
            {type = "header", label = LC["settings.help.title"]},
            {type = "space", height = 10}, {
                type = "text",
                label = string.format(LC["settings.help.current_version"], YUI.GameVersion or "Unknown"),
                colorKey = "color.state.danger"
            }, {
                type = "text",
                label = LC["settings.help.no_info"],
                colorKey = "color.text.secondary"
            }
        }
    end
end

local function Render(parent) S:RenderConfig(parent, GetConfig()) end

S:RegisterModule("常见问题", "Interface\\Icons\\INV_Misc_QuestionMark", Render, { titleKey = "settings.modules.help" })

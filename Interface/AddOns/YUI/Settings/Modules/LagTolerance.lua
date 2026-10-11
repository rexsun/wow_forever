local YUI = _G.YUI
local S = YUI.Settings

local function GetConfig()
    return {
        { type = "header", label = "延迟容限" },
        { type = "text", label = "在此设置全职业延迟容限。\n\n|cffff0000该功能开发中，尽请期待", colorKey = "color.text.secondary" },
        { type = "space", height = 20 },
        -- 暂时留空
    }
end

local function Render(parent)
    S:RenderConfig(parent, GetConfig())
end

S:RegisterModule("延迟容限", "Interface\\Icons\\Spell_Holy_BorrowedTime", Render)

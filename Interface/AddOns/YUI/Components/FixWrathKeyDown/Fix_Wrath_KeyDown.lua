local ADDON_NAME, YUI = ...
local Components = YUI.Components

if not YUI.IsWrath then return end
if not C_AddOns.IsAddOnLoaded("ElvUI") then return end

local function OnEnable(enable)
    if enable then
       -- [YUI Fix] 现在必须取消按下施法 04-09
        SetCVar("ActionButtonUseKeyDown", 0)
        -- 过3s再次设置,防止被其他插件覆盖
        C_Timer.After(3, function()
            SetCVar("ActionButtonUseKeyDown", 0)
        end)

        YUI:Print("已自动禁用【按下施法】，如有需要，在 /yui 组件管理中关闭【自动禁用按下施法】功能")
    end
end

Components:RegisterFeature("FixWrathKeyDown", {
    name = "自动禁用【按下施法】",
    description = "当前版本按下施法会导致很多功能无法点击",
    default = false,
    callback = OnEnable,
})

local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhCN") then return end

YUI.Locale:Register("RightPlus", "zhCN", {
    ["feature.name"] = "右键社交增强",
    ["feature.description"] = "在玩家右键菜单中添加“添加好友”和“邀请公会”操作。",
})

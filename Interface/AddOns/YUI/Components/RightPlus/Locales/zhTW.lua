local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhTW") then return end

YUI.Locale:Register("RightPlus", "zhTW", {
    ["feature.name"] = "右鍵社交增強",
    ["feature.description"] = "在玩家右鍵選單中加入「新增好友」和「邀請公會」操作。",
})

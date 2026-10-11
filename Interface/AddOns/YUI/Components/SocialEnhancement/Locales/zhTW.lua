local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhTW") then return end

YUI.Locale:Register("SocialEnhancement", "zhTW", {
    ["feature.name"] = "社交增強",
    ["feature.description"] = "提供 Tab 切換聊天目標和可選的玩家右鍵社交操作。",
    ["settings.tab_cycle"] = "使用 Tab / Shift+Tab 切換聊天目標",
    ["settings.tab_cycle.tooltip"] = "在可用的隊伍、公會和世界頻道間循環，不改動輸入文字和游標。",
    ["settings.tab_cycle.ychat"] = "Tab 切換目前由 YChat 管理。",
    ["settings.right_click"] = "增強玩家右鍵選單",
    ["settings.right_click.tooltip"] = "在支援的玩家選單中增加好友和邀請加入公會操作。",
    ["settings.right_click.conflict"] = "偵測到其他介面插件正在管理這些選單，此功能無法使用。",
    ["menu.add_friend"] = "新增好友",
    ["menu.invite_guild"] = "邀請加入公會",
})

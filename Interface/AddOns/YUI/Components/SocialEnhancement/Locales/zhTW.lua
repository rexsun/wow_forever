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
    ["settings.right_click.forever_tooltip"] = "新增好友使用原生遊戲好友流程。目前用戶端不提供公會邀請增強，請使用遊戲原生介面手動邀請。",
    ["settings.right_click.conflict"] = "偵測到其他介面插件正在管理這些選單，此功能無法使用。",
    ["menu.add_friend"] = "新增好友",
    ["menu.invite_guild"] = "邀請加入公會",
    ["error.restricted"] = "目前用戶端不提供公會邀請增強，請使用遊戲原生介面手動邀請。",
    ["error.combat"] = "戰鬥中無法新增好友或邀請公會，請脫戰後重試。",
    ["error.not_in_guild"] = "加入公會後才能邀請其他玩家。",
    ["error.guild_permission"] = "你沒有邀請玩家加入公會的權限。",
    ["error.invalid_name"] = "無法讀取玩家的完整姓名，請重新開啟玩家選單。",
    ["error.target_changed"] = "玩家目標已變更或無法使用，請重新開啟玩家選單。",
    ["error.prefill_failed"] = "無法完整填入玩家姓名，操作已取消，請重新開啟玩家選單。",
    ["error.unavailable"] = "無法開啟社交視窗，請使用遊戲原生好友或公會介面。",
})

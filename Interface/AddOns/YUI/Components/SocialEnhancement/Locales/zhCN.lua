local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("zhCN") then return end

YUI.Locale:Register("SocialEnhancement", "zhCN", {
    ["feature.name"] = "社交增强",
    ["feature.description"] = "提供 Tab 切换聊天目标和可选的玩家右键社交操作。",
    ["settings.tab_cycle"] = "使用 Tab / Shift+Tab 切换聊天目标",
    ["settings.tab_cycle.tooltip"] = "在可用的队伍、公会和世界频道间循环，不改动输入文字和光标。",
    ["settings.tab_cycle.ychat"] = "Tab 切换当前由 YChat 管理。",
    ["settings.right_click"] = "增强玩家右键菜单",
    ["settings.right_click.tooltip"] = "在支持的玩家菜单中增加好友和邀请加入公会操作。",
    ["settings.right_click.conflict"] = "检测到其他界面插件正在管理这些菜单，此功能不可用。",
    ["menu.add_friend"] = "添加好友",
    ["menu.invite_guild"] = "邀请加入公会",
})

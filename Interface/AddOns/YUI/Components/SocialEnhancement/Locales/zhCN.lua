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
    ["settings.right_click.forever_tooltip"] = "添加好友使用原生游戏好友流程。当前客户端不提供公会邀请增强，请使用游戏原生界面手动邀请。",
    ["settings.right_click.conflict"] = "检测到其他界面插件正在管理这些菜单，此功能不可用。",
    ["menu.add_friend"] = "添加好友",
    ["menu.invite_guild"] = "邀请加入公会",
    ["error.restricted"] = "当前客户端不提供公会邀请增强，请使用游戏原生界面手动邀请。",
    ["error.combat"] = "战斗中无法添加好友或邀请公会，请脱战后重试。",
    ["error.not_in_guild"] = "加入公会后才能邀请其他玩家。",
    ["error.guild_permission"] = "你没有邀请玩家加入公会的权限。",
    ["error.invalid_name"] = "无法读取玩家的完整姓名，请重新打开玩家菜单。",
    ["error.target_changed"] = "玩家目标已变化或不可用，请重新打开玩家菜单。",
    ["error.prefill_failed"] = "无法完整填入玩家姓名，操作已取消，请重新打开玩家菜单。",
    ["error.unavailable"] = "无法打开社交窗口，请使用游戏原生好友或公会界面。",
})

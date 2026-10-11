local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("enUS") then return end

YUI.Locale:Register("SocialEnhancement", "enUS", {
    ["feature.name"] = "Social Enhancement",
    ["feature.description"] = "Tab target switching and optional player-menu social actions.",
    ["settings.tab_cycle"] = "Use Tab / Shift+Tab to cycle chat targets",
    ["settings.tab_cycle.tooltip"] = "Cycles through supported group, guild, and world chat targets without changing the input text.",
    ["settings.tab_cycle.ychat"] = "Tab target switching is managed by YChat.",
    ["settings.right_click"] = "Enhance player right-click menus",
    ["settings.right_click.tooltip"] = "Adds friend and guild-invite actions to supported player menus.",
    ["settings.right_click.conflict"] = "Unavailable because another interface addon manages these menus.",
    ["menu.add_friend"] = "Add Friend",
    ["menu.invite_guild"] = "Invite to Guild",
})

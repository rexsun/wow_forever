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
    ["settings.right_click.forever_tooltip"] = "Uses the game's native WoW friend flow. Guild invitation enhancement is unavailable on this client; please invite manually through the game's UI.",
    ["settings.right_click.conflict"] = "Unavailable because another interface addon manages these menus.",
    ["menu.add_friend"] = "Add Friend",
    ["menu.invite_guild"] = "Invite to Guild",
    ["error.restricted"] = "Guild invitation enhancement is unavailable on this client. Please use the game's UI to invite manually.",
    ["error.combat"] = "Please leave combat before adding a friend or inviting a player to your guild.",
    ["error.not_in_guild"] = "You must be in a guild to invite a player.",
    ["error.guild_permission"] = "You do not have permission to invite players to your guild.",
    ["error.invalid_name"] = "Unable to read the player's full name. Please reopen the player menu.",
    ["error.target_changed"] = "The player is no longer available or has changed. Please reopen the player menu.",
    ["error.prefill_failed"] = "The full player name could not be filled in. The action was canceled; please reopen the player menu.",
    ["error.unavailable"] = "Unable to open the social window. Please use the game's Friends or Guild window.",
})

local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("enUS") then return end

YUI.Locale:Register("RightPlus", "enUS", {
    ["feature.name"] = "Right-click Social Actions",
    ["feature.description"] = "Adds Add Friend and Invite to Guild actions to player context menus.",
})

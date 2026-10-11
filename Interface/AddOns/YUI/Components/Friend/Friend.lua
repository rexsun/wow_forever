local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

YUI.Friend = YUI.Friend or {}

function YUI.Friend:IsFriend(name)
    local Social = YUI.API and YUI.API.Social
    return Social and Social.IsFriend and Social.IsFriend(name) == true or false
end



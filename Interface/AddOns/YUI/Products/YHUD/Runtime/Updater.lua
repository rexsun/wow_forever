local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Updater = YHUD.Updater or {}
YHUD.Updater = Updater

function Updater:Apply(state, diff)
    local View = YHUD.View
    if not (View and View.active) then return false end
    return View:UpdateSource(state, diff)
end

local _, ns = ...
ns = _G.YUI or ns

local GUI2 = ns and ns.GUI2
local Appearance = GUI2 and GUI2.WindowAppearance
if not Appearance then return end

ns.AuctionHelperAppearance = Appearance
return Appearance

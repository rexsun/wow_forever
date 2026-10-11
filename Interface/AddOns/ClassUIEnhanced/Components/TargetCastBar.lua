
local _
---@type string, private
local _, private = ...

---@class private : table
---@field TargetCastBar targetcastbar

---@class targetcastbar : component

local targetCastBar = private.CastBar.CreateCastBarComponent("target", "TargetCastBar", "PLAYER_TARGET_CHANGED")

private.TargetCastBar = targetCastBar
private.ComponentManager.RegisterComponent("TargetCastBar", targetCastBar)

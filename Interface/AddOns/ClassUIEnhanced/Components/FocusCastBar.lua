
local _
---@type string, private
local _, private = ...

---@class private : table
---@field FocusCastBar focuscastbar

---@class focuscastbar : component

local focusCastBar = private.CastBar.CreateCastBarComponent("focus", "FocusCastBar", "PLAYER_FOCUS_CHANGED")

private.FocusCastBar = focusCastBar
private.ComponentManager.RegisterComponent("FocusCastBar", focusCastBar)

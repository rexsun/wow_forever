
--[[
    UtilitiesTracker — displays utility cooldown spell icons via the shared
    plain-frame icon tracker factory (Core/IconTracker.lua; display-only, not
    clickable).  CDM (CooldownViewer) category CooldownUtility is the spell
    data source; the CDM viewer is alpha-suppressed and never rendered.
    Custom spells are merged in.  Additional-frame-routed spells are excluded.

    pandemic_glow rides Blizzard's native AddPandemicRegion (12.1.0.69111) on
    the factory's aura-slot buttons — see Core/IconTracker.lua's syncAuraSlots.
    Full gap tracker: .context/migration-parity-gaps.md (mirrored on PR #41).
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field UtilitiesTracker utilitiestracker

---@class utilitiestracker : component

---@type utilitiestracker
local utilitiesTracker = private.IconTracker.CreateTracker({
    name = "UtilitiesTracker",
    containerName = "CUE_UT_Container",
    categoryId = private.Enum.CooldownViewerCategoryIDs.CooldownUtility,
    routeKey = "Utility",
})

private.UtilitiesTracker = utilitiesTracker
private.ComponentManager.RegisterComponent("UtilitiesTracker", utilitiesTracker)

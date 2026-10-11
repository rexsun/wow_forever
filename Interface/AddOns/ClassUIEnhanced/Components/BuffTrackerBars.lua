
--[[
    Buff tracker bars — the primary aura-bar tracker.

    The rendering engine lives in Core/AuraBarTracker.lua so Additional Frames of
    type "bar" can instantiate the same thing (they need their OWN aura
    containers; the old cross-parenting of live CDM viewer children cannot work
    on 12.1).  This file is the config: which spells, which settings table, which
    CDM viewer supplies the groups-vs-slots mode.

    Everything else — containers, both engines, cell chrome, glow syncs, layout,
    component lifecycle — is the factory's.  See Components/BuffTrackerBars.md.
--]]

---@type string, private
local addonName, private = ...

---@class private : table
---@field BuffTrackerBars table

---Build the {[spellID]=true} map: CDM category BuffBar minus
---Additional-Frame-routed spells, plus this component's custom spells.
---
---ONE map, fed to BOTH unit containers — the filter strings decide where an aura
---can land, exactly as Blizzard's own CDM does (`scanUnits = { "player", "target" }`,
---CooldownViewerItemData.lua:1; `selfAura` is a DB2 field their UI never reads).
---`CDMDataSource` still RETURNS the self/target split because
---`Core/IconTracker.lua` needs it for an unrelated purpose — gating which spells
---its player-unit aura slots may bind — so the merge belongs here, not there.
---@return table<number, true> spellMap
local function buildSpellMap()
    -- includeLinked: aura-driven — the displayed aura is often a linked id,
    -- not the base spellID (see getTrackedSpellMap doc).
    local selfMap, targetMap = private.CDMDataSource.BuildComponentSpellMaps(
        private.Enum.CooldownViewerCategoryIDs.BuffBar,
        "BuffBar", "BuffTrackerBars", true)
    for spellID in pairs(targetMap) do selfMap[spellID] = true end
    return selfMap
end

local buffTrackerBars = private.AuraBarTracker.CreateTracker({
    name = "BuffTrackerBars",
    prefix = "CUE_BTB",
    getSettings = function()
        return private.profile.components.BuffTrackerBars
    end,
    buildSpellMap = buildSpellMap,
})

private.BuffTrackerBars = buffTrackerBars
private.ComponentManager.RegisterComponent("BuffTrackerBars", buffTrackerBars)

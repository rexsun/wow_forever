local _, ns = ...

-- Quick Setup: the things people do most, one click each, on the first page
-- /fui opens (the owner's list, 25 Sept 2026):
--
--   1. move frames              2. keybinds
--   3. the quest helper on/off  4. Healing / Tanking / DPS frames on/off
--   5. ForeverUI's look off (Blizzard's UI back, frames kept)
--   6. nameplates off (so another nameplate addon can have them)
--   7. where the party frames go (moving, same as 1)
--   8. how many buttons on bars 1-3, and keybinding them
--
-- Nothing here is new: every tile calls what the full pages already use, so
-- a change made here shows on those pages and the other way round. It is a
-- front door, not a second copy.

local function Frames()
  return ns.Frames
end

local function ActionBars()
  return ns.GetModule("ActionBars")
end

local function Say(text)
  ns.Print(text)
end

local function Refresh()
  if ns.RefreshOptions then ns.RefreshOptions() end
end

-- A role grid: always, in groups only, or off -- one tile, one click to
-- the next (owner, 30 Sept 2026: the old "frames: on" + a separate "Solo"
-- switch was confusing, and a grid switched on stayed hidden while leveling).
local STATE_LABEL = { always = "always", group = "in groups only", off = "off" }
local function GridTile(role, label, icon)
  return {
    type = "action", width = 200, icon = icon,
    labelFor = function()
      local f = Frames()
      local state = f and f.GridState and f.GridState(role) or "off"
      return ("%s: %s"):format(label, STATE_LABEL[state] or state)
    end,
    desc = "Click: always (solo too) -> in groups only -> off.",
    isSelected = function()
      local f = Frames()
      return f and f.GridState and f.GridState(role) ~= "off" or false
    end,
    onClick = function()
      local f = Frames()
      if not (f and f.CycleGridState) then
        Say("the party & raid frames are switched off - turn them on under Modules.")
        return
      end
      if InCombatLockdown and InCombatLockdown() then
        Say("frames can't be shown or hidden in combat.")
        return
      end
      f.CycleGridState(role)
      Refresh()
    end,
  }
end

-- A module on or off.
local function ModuleTile(name, onLabel, offLabel, desc, icon)
  return {
    type = "action", width = 200, icon = icon, desc = desc,
    labelFor = function() return ns.IsModuleEnabled(name) and onLabel or offLabel end,
    isSelected = function() return ns.IsModuleEnabled(name) end,
    onClick = function()
      local on = not ns.IsModuleEnabled(name)
      local module = ns.GetModule(name)
      if module and module.Toggle and name == "QuestForever" then
        module.Toggle(on)
      else
        ns.SetModuleEnabled(name, on)
      end
      Refresh()
    end,
  }
end

-- How many buttons on one bar, the same value as that bar's tab on Action
-- Bars (its own store, so the page shows it too).
local function BarButtons(key, label)
  return {
    type = "stepper", key = "buttons", label = label, min = 1, max = 12, step = 1,
    moduleName = "ActionBars",
    store = function()
      local bars = ActionBars()
      return bars and bars.BarStore and bars.BarStore(key) or {}
    end,
  }
end

local function BarPerRow(key, label)
  return {
    type = "stepper", key = "perRow", label = label, min = 1, max = 12, step = 1,
    moduleName = "ActionBars",
    store = function()
      local bars = ActionBars()
      return bars and bars.BarStore and bars.BarStore(key) or {}
    end,
  }
end

-- The raid marker keys (Modules/Markers): skull, cross, moon and the smart
-- key, set right here - click, press the key.
local function MarkerKeyTiles()
  local markers = ns.GetModule("Markers")
  return markers and markers.KeyTiles and markers.KeyTiles() or {}
end

function ns.QuickPageSchema()
  local schema = {
    { type = "heading", label = "Quick Setup", subtitle = "The things you'll do most - one click each.",
      icon = "star" },

    { type = "heading", label = "Move and bind", columns = 3, icon = "framemgmt" },
    { type = "action", width = 200, icon = "framemgmt",
      desc = "Drag anything - bars, party frames, minimap, quest list - where you want it.",
      labelFor = function() return ns.MoversShown() and "Done moving" or "Move frames" end,
      isSelected = function() return ns.MoversShown() end,
      onClick = function() ns.ToggleMovers() Refresh() end },
    { type = "action", width = 200, icon = "keybinds",
      desc = "Hover a bar button and press a key (or mouse button) to bind it.",
      labelFor = function()
        local bars = ActionBars()
        return (bars and bars.GetMode and bars.GetMode() == "keys") and "Done binding" or "Keybind the bars"
      end,
      isSelected = function()
        local bars = ActionBars()
        return bars and bars.GetMode and bars.GetMode() == "keys" or false
      end,
      onClick = function()
        local bars = ActionBars()
        if bars and bars.ToggleKeybinds then bars.ToggleKeybinds() else Say("the action bars are switched off.") end
        Refresh()
      end },
    { type = "action", width = 200, icon = "actionbars",
      desc = "Unlock the bars and drop spells onto them from your spellbook.",
      labelFor = function()
        local bars = ActionBars()
        return (bars and bars.IsEditing and bars.IsEditing()) and "Done editing" or "Put spells on the bars"
      end,
      isSelected = function()
        local bars = ActionBars()
        return bars and bars.IsEditing and bars.IsEditing() or false
      end,
      onClick = function()
        local bars = ActionBars()
        if bars and bars.ToggleEditing then bars.ToggleEditing() else Say("the action bars are switched off.") end
        Refresh()
      end },

    { type = "heading", label = "Party & raid frames", columns = 3, icon = "unitframes" },
    GridTile("healer", "Healing", "heal"),
    GridTile("tank", "Tanking", "tank"),
    GridTile("dps", "DPS", "dps"),

    { type = "heading", label = "On and off", columns = 3, icon = "modules" },
    ModuleTile("QuestForever", "Quest helper: on", "Quest helper: off",
      "Quest givers, hand-ins and objectives on your map while you level.", "quests"),
    ModuleTile("Nameplates", "Nameplates: ForeverUI's", "Nameplates: the game's",
      "Off lets another nameplate addon (or the game's own) have them.", "nameplates"),
    ModuleTile("Markers", "Raid markers: on", "Raid markers: off",
      "Skull, cross, moon on your target in a click or a key (shown in a group).", "target"),
    { type = "action", width = 200, icon = "interface",
      desc = "Everything else back to Blizzard's own - bars, unit frames, chat, bags - keeping only the party & raid frames.",
      labelFor = function()
        return ns.CurrentLoadout() == "frames" and "Bring ForeverUI's look back" or "Blizzard's look (keep frames)"
      end,
      isSelected = function() return ns.CurrentLoadout() == "frames" end,
      onClick = function()
        local key = ns.CurrentLoadout() == "frames" and "everything" or "frames"
        local ok, moved = ns.ApplyLoadout(key)
        if ok then
          Say(("%s -- %d module%s changed."):format(ns.Loadout(key).label, moved, moved == 1 and "" or "s"))
        end
        Refresh()
      end },

    { type = "action", width = 200, icon = "heal",
      desc = "Only the healing frames - every other part of the game stays Blizzard's own.",
      labelFor = function() return ns.IsRoleOnly("healer") and "Healing only: on" or "Healing only" end,
      isSelected = function() return ns.IsRoleOnly("healer") end,
      onClick = function()
        local ok, moved = ns.ApplyRoleOnly("healer")
        if ok then
          Say(("Healing only -- %d module%s changed."):format(moved, moved == 1 and "" or "s"))
        end
        Refresh()
      end },

    { type = "heading", label = "Raid marker keys - click a tile, press a key", columns = 3, icon = "target",
      markerKeys = true },
    { type = "heading", label = "Your bars - buttons on each", columns = 3, icon = "actionbars" },
    BarButtons("bar1", "Main bar"),
    BarButtons("bar2", "Bar 2"),
    BarButtons("bar3", "Bar 3"),
    { type = "heading", label = "Your bars - buttons per row", columns = 3, icon = "actionbars" },
    BarPerRow("bar1", "Main bar"),
    BarPerRow("bar2", "Bar 2"),
    BarPerRow("bar3", "Bar 3"),
    { type = "note", label = "Show or hide bars 2-4, sizes and spacing: Action Bars. Frame looks and click-casting: Heal, Tank or DPS on the left." },

    { type = "heading", label = "Start over", columns = 3, icon = "reset" },
    { type = "action", width = 200, icon = "reset", label = "Reset every frame position",
      desc = "Every frame back where it started.",
      onClick = function() ns.ResetAllMovers() Refresh() end },
    { type = "action", width = 200, icon = "installer", label = "Run the setup again",
      desc = "The first-time questions, with your answers filled in.",
      onClick = function() ns.ShowInstaller(true) end },
  }
  -- The marker key tiles go under their heading (a call in the middle of a
  -- table constructor would give only its first value).
  for i, entry in ipairs(schema) do
    if entry.markerKeys then
      for n, tile in ipairs(MarkerKeyTiles()) do
        table.insert(schema, i + n, tile)
      end
      break
    end
  end
  return schema
end

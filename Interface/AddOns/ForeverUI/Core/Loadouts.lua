local _, ns = ...

-- How much of ForeverUI you actually want running.
--
-- Not everybody wants a whole interface. Somebody who heals may want the
-- party and raid frames and nothing else -- Blizzard's bars, Blizzard's bags,
-- Blizzard's map, and these frames on top. Somebody who already runs VuhDo or
-- Grid wants the opposite: the whole interface, with the group frames left
-- alone. Both are one click here rather than a dozen switches on the Modules
-- page, and the question is asked at first login so nobody has to find it.
--
-- A loadout is only a shortcut. It turns modules on and off through the same
-- ns.SetModuleEnabled every switch uses, and nothing stops anyone from then
-- flipping one by hand -- at which point the answer to "which loadout am I
-- on?" is simply "your own", and the page says so.

local FRAMES = "Frames"   -- the party/raid frame engine, the module all this turns on

ns.LOADOUTS = {
  {
    key = "everything",
    label = "The whole interface",
    short = "Everything",
    icon = "interface",
    note = "Action bars, unit frames, bags, chat, the minimap, the quest tracker, nameplates and the party frames. The full set.",
  },
  {
    key = "frames",
    label = "Only the party & raid frames",
    short = "Frames only",
    icon = "heal",
    note = "Just the frames for your role, healer, tank or damage. Everything else is left to the game, exactly as if ForeverUI were an addon that only did group frames.",
  },
  {
    key = "ui",
    label = "Everything except the party & raid frames",
    short = "No frames",
    icon = "unitframes",
    note = "The whole interface, with group frames left to VuhDo, Grid, or the game's own.",
  },
}

function ns.Loadout(key)
  for _, entry in ipairs(ns.LOADOUTS) do
    if entry.key == key then
      return entry
    end
  end
  return nil
end

-- Whether a given module belongs in a given loadout.
-- nil: this loadout doesn't decide it. The quest helper is its own question
-- (the installer asks it separately), so no loadout turns it on or off.
local INDEPENDENT = { QuestForever = true, Kicks = true, ForeverAuras = true }

local function Wants(key, name)
  if INDEPENDENT[name] then
    return nil
  elseif key == "frames" then
    return name == FRAMES
  elseif key == "ui" then
    return name ~= FRAMES
  end
  return true -- "everything", and anything unrecognised: leave it all on
end
ns.LoadoutWants = Wants

-- Which loadout the modules currently match, or nil for a hand-made set.
-- Worked out from what is actually switched on rather than from what was
-- last chosen, so turning one module off by hand is honestly reported
-- instead of leaving a stale label on the page.
function ns.CurrentLoadout()
  for _, entry in ipairs(ns.LOADOUTS) do
    local matches = true
    ns.ForEachModule(function(_, name)
      local wanted = Wants(entry.key, name)
      if wanted ~= nil and ns.IsModuleEnabled(name) ~= wanted then
        matches = false
      end
    end)
    if matches then
      return entry.key
    end
  end
  return nil
end

-- One line for the page and for /fui only.
function ns.LoadoutSummary()
  local key = ns.CurrentLoadout()
  local entry = key and ns.Loadout(key)
  if entry then
    return entry.note
  end
  local on, off = {}, {}
  ns.ForEachModule(function(module, name)
    local list = ns.IsModuleEnabled(name) and on or off
    list[#list + 1] = module.title or name
  end)
  if #off == 0 then
    return "Everything is on."
  end
  return ("Your own set: %d on, %d off (%s)."):format(#on, #off, table.concat(off, ", "))
end

-- Switch. Every module is put where the loadout says, through the same path a
-- single switch uses, so anything that needs a reload to undo still asks for
-- one -- once, however many modules moved.
function ns.ApplyLoadout(key)
  local entry = ns.Loadout(key)
  if not entry then
    return false, ("there is no \"%s\" loadout"):format(tostring(key))
  end
  local moved = 0
  -- Whatever asks for a reload while this runs, the honest reason is the
  -- choice that was just made, not the module that noticed first.
  ns.reloadReason = ("\"%s\""):format(entry.label)
  ns.ForEachModule(function(_, name)
    local wanted = Wants(key, name)
    if wanted ~= nil and ns.IsModuleEnabled(name) ~= wanted then
      ns.SetModuleEnabled(name, wanted)
      moved = moved + 1
    end
  end)
  ns.reloadReason = nil
  ns.db.loadout = key
  if ns.RefreshOptions then
    ns.RefreshOptions()
  end
  return true, moved
end

-- "Just the healing, leave everything else behind" (several players, 24
-- Sept 2026). Frames only is half of that: it still left whichever grids
-- were up - tank and DPS as well. This is the whole of it in one go: the
-- frames and nothing else, only that role's grid on screen, and the frames
-- set up for that role.
ns.ROLE_ONLY = {
  healer = { label = "Healing only", icon = "heal" },
  tank = { label = "Tanking only", icon = "tank" },
  dps = { label = "DPS only", icon = "dps" },
}

function ns.ApplyRoleOnly(role)
  if not ns.ROLE_ONLY[role] then
    return false, ("there is no \"%s\" role - healer, tank or dps"):format(tostring(role))
  end
  local ok, moved = ns.ApplyLoadout("frames")
  if not ok then
    return false, moved
  end
  local frames = ns.Frames
  if frames then
    if frames.GetMode and frames.SetMode and frames.GetMode() ~= role then
      frames.SetMode(role)
    end
    if frames.SetGridShown then
      for _, each in ipairs({ "healer", "tank", "dps" }) do
        frames.SetGridShown(each, each == role)
      end
    end
  end
  return true, moved
end

-- Is this exactly "frames only, with just this role's grid"?
function ns.IsRoleOnly(role)
  if ns.CurrentLoadout() ~= "frames" then
    return false
  end
  local frames = ns.Frames
  local shown = frames and frames.ShownGrids and frames.ShownGrids() or {}
  return #shown == 1 and shown[1] == role
end

local _, ns = ...

-- Testing tools: /fui test <what>.
--
-- Things you need while building and checking ForeverUI that a player never
-- would, kept in one file so they are easy to find and easy to leave out.
-- Nothing here runs by itself; every tool is a command you type, and none of
-- them can lose a setting you did not ask to change.
--
--   /fui test              mock party frames, to lay things out solo
--   /fui test setup        the first-run wizard as a brand-new player sees it
--   /fui test setup dry    the same walk-through, changing nothing at all
--   /fui test firstrun     forget that setup ran, so the next login is a first
--   /fui test group [n]    a pretend party (or raid of n) on every grid
--   /fui test group off    back to the real group
--   /fui test combat [n]   a pretend fight: 5, 10, 20 or 40 (Frames/CombatSim.lua)
--   /fui test combat off   stop it
--   /fui test help         this list

local TOOLS = {
  { "/fui test", "mock party frames, so you can lay things out solo" },
  { "/fui test setup", "the first-run wizard as a brand-new player sees it (Apply really applies)" },
  { "/fui test setup dry", "the same walk-through; Apply only says what it would have done" },
  { "/fui test firstrun", "forget setup ran, then reload: you get the real first login" },
  { "/fui test group", "a pretend party of five on every grid; clicks really cast, on you" },
  { "/fui test group 10|25|40", "a pretend raid of that size" },
  { "/fui test group off", "back to your real group" },
  { "/fui test combat 5|10|20|40", "a pretend FIGHT: damage, AoE, deaths, dispels, HoTs, threat, enemy casts" },
  { "/fui test combat off", "stop the fight" },
  { "/fui test help", "this list" },
}

local function Help()
  ns.Print("testing tools:")
  for _, tool in ipairs(TOOLS) do
    print(("  |cffffd100%s|r - %s"):format(tool[1], tool[2]))
  end
end
ns.TestingHelp = Help

-- The wizard as someone who has never run ForeverUI meets it: page one,
-- default answers, not your own scale and grids read back to you.
local function Setup(dry)
  if InCombatLockdown and InCombatLockdown() then
    ns.Print("not in combat -- the setup rebuilds the grids.")
    return false
  end
  ns.ShowInstaller(false, { fresh = true, dry = dry })
  if dry then
    ns.Print("|cffffd100test run|r: click through freely; nothing will change.")
  end
  return true
end
ns.TestSetup = Setup

-- The real first login: the flag that says setup has been seen is cleared,
-- and a reload brings the wizard up through the same path a new player takes.
-- The reload is offered with a button -- the game only lets an addon reload
-- from a click.
local function FirstRun()
  if not ns.db then
    return false
  end
  ns.db.installed = nil
  if ns.RequestReload then
    ns.RequestReload("Testing the first login")
  end
  ns.Print("setup will run at the next login. Your settings are untouched.")
  return true
end
ns.TestFirstRun = FirstRun

function ns.TestCommand(rest)
  local what, arg = (rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if what == "" or what == "frames" then
    ns.ToggleTestMode()   -- what /fui test has always done
  elseif what == "setup" or what == "install" or what == "wizard" then
    Setup(arg == "dry")
  elseif what == "firstrun" or what == "first" then
    FirstRun()
  elseif what == "group" or what == "party" or what == "raid" then
    local frames = ns.Frames
    if not (frames and frames.SimulateGroup) then
      ns.Print("the party & raid frames are switched off -- nothing to fill.")
    elseif arg == "off" or arg == "stop" then
      if frames.CombatSimRunning and frames.CombatSimRunning() then
        frames.StopCombatSim()
      else
        frames.StopSimulating()
      end
    else
      local size = tonumber(arg) or (what == "raid" and 25 or 5)
      frames.SimulateGroup(size)
    end
  elseif what == "combat" or what == "fight" then
    local frames = ns.Frames
    if not (frames and frames.StartCombatSim) then
      ns.Print("the party & raid frames are switched off -- nothing to fight with.")
    elseif arg == "off" or arg == "stop" then
      frames.StopCombatSim()
    else
      frames.StartCombatSim(tonumber(arg) or 5)
    end
  else
    Help()
  end
end

local _, ns = ...

-- Playing with a controller (CurseForge, 28 Sept 2026: "i love the look of
-- the frames but it crashes when i try to play with controller"; owner:
-- "build controller support").
--
-- Forever runs Blizzard's whole console-style controller UI (the camelot
-- game type loads Blizzard_Gamepad and Blizzard_GamepadActionBars for every
-- player): its own action bars on their own action slots, a pointer that
-- walks Blizzard's frames, the radial menu, the bag it focuses. ForeverUI
-- fighting any of that is what broke it:
--   * the action bar module wraps the cooldown and press-and-hold code of
--     every action button the game registers -- the controller's included --
--     so a page or stance change ran them tainted, and in combat the game
--     blocked the controller's buttons as ForeverUI's;
--   * our bag window keeps Blizzard's bag open but invisible, and the pointer
--     walked its invisible slots;
--   * the buff frame and micro menu were tucked away under the radial menu.
--
-- So in controller mode the parts that replace what the controller drives
-- step aside and the game's own run untouched -- ForeverUI's action bars,
-- bag window, micro bar and XP bar, and its hiding of the buff frame and chat.
-- Everything else (unit frames, grids, quests, nameplates, the look) stays.
--
-- Settings > General > Controller: Auto (follow the game's controller mode),
-- On, Off. Taint can't be undone in a running UI, so a switch asks for a
-- reload; which way it went is decided once, at login.

-- XPBar too (Altiokis on CurseForge, 30 Sept 2026: "I have two experience
-- bars, using controller"): the controller UI draws its own XP bar with its
-- action bars, so ours was the second one.
local SUSPENDS = { ActionBars = true, Bags = true, MicroBar = true, XPBar = true }
ns.CONTROLLER_SUSPENDS = SUSPENDS

-- The game's own answer: is its controller UI in charge right now?
function ns.GamepadUIActive()
  if InputUtil and InputUtil.IsGamepadUIEnabled then
    local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
    if ok then return on and true or false end
  end
  if C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and Enum and Enum.InputDeviceInterfaceType then
    local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)
    if ok then return style == Enum.InputDeviceInterfaceType.Gamepad end
  end
  return false
end

-- The game's own aura containers (CustomAuraContainerTemplate) make their
-- icons with CreateFrame, and while the controller's navigation is live it
-- hooks every CreateFrame and walks the new frame's parents -- from the
-- caller's (our) code, into the container, which the game locks away from
-- addons: "SmartNavigation.lua:926: attempted to index a table that cannot
-- be accessed while tainted (execution tainted by 'ForeverUI')" (Altiokis on
-- CurseForge, 28 Sept 2026, right after the setup). So with the controller
-- in charge none are made; each place that uses them has its own fallback.
-- Checked live, not only at login: picking up a pad mid-session counts.
function ns.AuraContainersAllowed()
  if _G.CustomAuraContainerGroupDefaultOptions == nil then return false end
  if ns.GamepadUIActive() then return false end
  if ns.controllerAtBoot then return false end
  return true
end

function ns.ControllerSetting()
  local mode = ns.db and ns.db.controllerMode
  if mode == "on" or mode == "off" then return mode end
  return "auto"
end

local function Wanted()
  local mode = ns.ControllerSetting()
  if mode == "on" then return true end
  if mode == "off" then return false end
  return ns.GamepadUIActive()
end
ns.ControllerWanted = Wanted

-- Decided once per session, the first time anything asks (the modules, at
-- login): a module that already wrapped Blizzard's buttons can't unwrap them.
function ns.ControllerActive()
  if ns.controllerAtBoot == nil then
    if not ns.db then return false end
    ns.controllerAtBoot = Wanted()
  end
  return ns.controllerAtBoot
end

-- Does this module sit out for the controller?
function ns.ControllerSuspended(name)
  return SUSPENDS[name] == true and ns.ControllerActive()
end

-- The game switched between mouse-and-keyboard and controller (or the
-- setting changed): ForeverUI's side only changes on a reload.
local asked
function ns.ControllerCheck()
  if ns.controllerAtBoot == nil or not (ns.db and ns.db.installed) then return false end
  local want = Wanted()
  if want == ns.controllerAtBoot or asked == want then return false end
  asked = want
  if ns.RequestReload then
    ns.RequestReload(want and "Switching to controller mode (the game's controller bars and bag)"
      or "Switching back to keyboard and mouse (ForeverUI's bars and bag)")
  end
  return true
end

-- The world map's controller cursor pans the map when it reaches an edge,
-- at a speed scaled by how far the left stick is pushed. Blizzard only
-- records that (ScrollContainer.gamepadPanMagnitude) when the map's own
-- stick binding fires, and never starts it at anything -- so if the cursor
-- is moving before that has happened (the map opened on the quest list, or
-- the stick already held when it opened), every frame at the edge is
-- "MapCanvas_ScrollContainerMixin.lua:1041: attempt to perform arithmetic
-- on field 'gamepadPanMagnitude' (a nil value)", 8561 times in one report
-- (CurseForge, 29 Sept 2026, PS5 controller on a Mac). Give it a starting
-- value through Blizzard's own setter, once, at login, from this frame's
-- own event -- never from inside the map's code -- and only with the
-- controller UI on. The first real stick movement overwrites it.
function ns.SteadyMapPan()
  local map = rawget(_G, "WorldMapFrame")
  local container = type(map) == "table" and map.ScrollContainer
  if type(container) ~= "table" or type(container.SetGamepadPanMagnitude) ~= "function" then return false end
  if type(rawget(container, "gamepadPanMagnitude")) ~= "nil" then return false end
  if not ns.GamepadUIActive() then return false end
  return (pcall(container.SetGamepadPanMagnitude, container, 1))
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "INPUT_DEVICE_INTERFACE_TRANSITION", "GAME_PAD_ACTIVE_CHANGED",
  "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do
  pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
  if event ~= "PLAYER_ENTERING_WORLD" and event ~= "ADDON_LOADED" then
    pcall(ns.ControllerCheck)
  end
  pcall(ns.SteadyMapPan)
end)
ns.controllerWatcher = watcher

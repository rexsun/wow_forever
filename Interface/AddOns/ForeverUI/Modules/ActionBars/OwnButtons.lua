local _, ns = ...

-- Local patch (4 Oct 2026): ForeverUI's own action buttons, driven by our own
-- event frame instead of Blizzard's shared button loops.
--
-- Our buttons are built from ActionBarButtonTemplate, whose OnLoad signs them
-- up with Blizzard's ActionBarButtonEventsFrame (and, once a slot has an
-- action, ActionBarActionEventsFrame and ActionBarButtonUpdateFrame). Those
-- frames hand each event to every button in one plain pairs() loop, and
-- ActionBarController_UpdateAll walks the same list. A button made by an
-- addon runs as that addon, so everything after it in the loop ran as
-- ForeverUI: Blizzard's own buttons (hence the cooldown wrappers this addon
-- used to put on them) and, after the page loop, MainActionBar:Show() ->
-- EditModeManager:UpdateBottomActionBarPositions() -> SetPoint, which wrote
-- Edit Mode's snap records under our name. Every later Edit Mode pass read
-- them and redrew Blizzard's party frames as ForeverUI:
-- "CompactUnitFrame.lua:699: attempt to compare local 'oldR' (a secret number
-- value, while execution tainted by 'ForeverUI')". !TaintProbe caught the
-- write with that exact stack.
--
-- So each of our buttons is taken out of those lists and handed the same
-- events from here, where running as ForeverUI touches nothing of Blizzard's.

local module = ns.GetModule("ActionBars")
if not module then return end

local OwnLoop = {}
module.OwnLoop = OwnLoop

local buttonEvents = {}   -- out of ActionBarButtonEventsFrame.frames
local actionEvents = {}   -- would be in ActionBarActionEventsFrame.frames
local updates = {}        -- would be in ActionBarButtonUpdateFrame.frames
OwnLoop.buttonEvents, OwnLoop.actionEvents, OwnLoop.updates = buttonEvents, actionEvents, updates

-- Mirrors ActionBarButtonEventsFrameMixin:OnLoad and
-- ActionBarActionEventsFrameMixin:OnLoad (ActionButton.lua).
local BUTTON_EVENTS = {
  "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "GAME_PAD_ACTIVE_CHANGED",
  "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
}
local BUTTON_UNIT_EVENTS = { UNIT_FLAGS = "pet", UNIT_AURA = "pet" }
local ACTION_EVENTS = {
  "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
  "ARCHAEOLOGY_CLOSED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL",
  "STOP_AUTOREPEAT_SPELL", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "COMPANION_UPDATE",
  "UNIT_SPELLCAST_SENT", "LEARNED_SPELL_IN_SKILL_LINE", "PET_STABLE_UPDATE", "PET_STABLE_SHOW",
  "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "UPDATE_SUMMONPETS_ACTION",
  "SPELL_UPDATE_ICON",
}
local ACTION_UNIT_EVENTS = {
  UNIT_SPELLCAST_INTERRUPTED = "player", UNIT_SPELLCAST_SUCCEEDED = "player", UNIT_SPELLCAST_FAILED = "player",
  UNIT_SPELLCAST_START = "player", UNIT_SPELLCAST_STOP = "player", UNIT_SPELLCAST_CHANNEL_START = "player",
  UNIT_SPELLCAST_CHANNEL_STOP = "player", UNIT_SPELLCAST_RETICLE_TARGET = "player",
  UNIT_SPELLCAST_RETICLE_CLEAR = "player", UNIT_SPELLCAST_EMPOWER_START = "player",
  UNIT_SPELLCAST_EMPOWER_STOP = "player", LOSS_OF_CONTROL_ADDED = "player", LOSS_OF_CONTROL_UPDATE = "player",
}

local isButtonEvent, isActionEvent = {}, {}
for _, e in ipairs(BUTTON_EVENTS) do isButtonEvent[e] = true end
for e in pairs(BUTTON_UNIT_EVENTS) do isButtonEvent[e] = true end
for _, e in ipairs(ACTION_EVENTS) do isActionEvent[e] = true end
for e in pairs(ACTION_UNIT_EVENTS) do isActionEvent[e] = true end

local function IsOurs(button)
  return type(button) == "table" and rawget(button, "fuiTemplate") ~= nil
end
OwnLoop.IsOurs = IsOurs

local function Call(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local handler = geterrorhandler()
    if handler then handler(err) end
  end
end

-- Spellcast events go only to the buttons whose spell it is, as Blizzard's
-- frame does (ActionBarActionEventsFrameMixin:OnEvent).
local function SpellcastMatches(button, event, ...)
  if event:sub(1, 15) ~= "UNIT_SPELLCAST_" then return true end
  local unit = ...
  local spellID
  if event == "UNIT_SPELLCAST_SENT" then
    spellID = select(4, ...)
  else
    spellID = select(3, ...)
  end
  if unit ~= "player" or type(button.MatchesActiveButtonSpellID) ~= "function" then return false end
  local ok, matches = pcall(button.MatchesActiveButtonSpellID, button, spellID)
  return ok and matches == true
end

-- Local patch (8 Oct 2026): UpdateAction ends in UpdatePingAttributes, which
-- calls SetAttribute on the (protected) button. Run from here it runs as
-- ForeverUI, so an ACTIONBAR_SLOT_CHANGED in combat was blocked:
-- "ForeverUI tried to call the protected function
-- 'ForeverUIbar2Button3:SetAttribute()'". The ping attributes only serve the
-- ping system, so in combat they wait for PLAYER_REGEN_ENABLED.
local pendingPing = {}

local function GuardPing(button)
  if rawget(button, "fuiPingGuard") then return end
  local base = button.UpdatePingAttributes
  if type(base) ~= "function" then return end
  button.fuiPingGuard = true
  button.UpdatePingAttributes = function(self, ...)
    if InCombatLockdown() then
      pendingPing[self] = true
      return
    end
    return base(self, ...)
  end
end
OwnLoop.GuardPing = GuardPing

local function FlushPendingPing()
  local waiting = {}
  for button in pairs(pendingPing) do waiting[#waiting + 1] = button end
  wipe(pendingPing)
  for _, button in ipairs(waiting) do
    Call(button.UpdatePingAttributes, button)
  end
end

local driver = CreateFrame("Frame")
OwnLoop.driver = driver
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
for _, e in ipairs(BUTTON_EVENTS) do pcall(driver.RegisterEvent, driver, e) end
for _, e in ipairs(ACTION_EVENTS) do pcall(driver.RegisterEvent, driver, e) end
for e, unit in pairs(BUTTON_UNIT_EVENTS) do pcall(driver.RegisterUnitEvent, driver, e, unit) end
for e, unit in pairs(ACTION_UNIT_EVENTS) do pcall(driver.RegisterUnitEvent, driver, e, unit) end

driver:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_REGEN_ENABLED" then
    FlushPendingPing()
    return
  end
  if isButtonEvent[event] then
    for button in pairs(buttonEvents) do
      Call(button.OnEvent, button, event, ...)
    end
  end
  if isActionEvent[event] then
    for button in pairs(actionEvents) do
      if SpellcastMatches(button, event, ...) then
        Call(button.OnEvent, button, event, ...)
      end
    end
  end
end)

driver:SetScript("OnUpdate", function(_, elapsed)
  for button in pairs(updates) do
    Call(button.OnUpdate, button, elapsed)
  end
end)

-- The keyed lists. A key set to nil leaves nothing of ours behind; the
-- button's own later RegisterFrame/UnregisterFrame calls are followed by the
-- hooks below, so it never lingers there.
local KEYED = {
  ActionBarActionEventsFrame = actionEvents,
  ActionBarButtonUpdateFrame = updates,
}

local function TakeOursFromKeyed(registryName)
  local registry = rawget(_G, registryName)
  local list = type(registry) == "table" and rawget(registry, "frames")
  if type(list) ~= "table" then return end
  local found = {}
  for button in pairs(list) do
    if IsOurs(button) then found[#found + 1] = button end
  end
  for _, button in ipairs(found) do
    list[button] = nil
    GuardPing(button)
    KEYED[registryName][button] = true
  end
end

local hookedKeyed = false
local function HookKeyed()
  if hookedKeyed or not hooksecurefunc then return end
  hookedKeyed = true
  for name, mine in pairs(KEYED) do
    local registry = rawget(_G, name)
    if type(registry) == "table" and type(registry.RegisterFrame) == "function" then
      hooksecurefunc(registry, "RegisterFrame", function(self, button)
        if IsOurs(button) then
          local list = rawget(self, "frames")
          if type(list) == "table" then list[button] = nil end
          GuardPing(button)
          mine[button] = true
        end
      end)
      if type(registry.UnregisterFrame) == "function" then
        hooksecurefunc(registry, "UnregisterFrame", function(_, button)
          if IsOurs(button) then mine[button] = nil end
        end)
      end
    end
  end
end

-- Called from module.DropSleepingPadsFromLoop for each of our buttons it has
-- taken out of ActionBarButtonEventsFrame's ordered list.
function OwnLoop.AdoptFromOrdered(button)
  GuardPing(button)
  buttonEvents[button] = true
end

-- Our buttons' keyed-list entries, every time the module sweeps.
function OwnLoop.AdoptKeyed()
  HookKeyed()
  for name in pairs(KEYED) do
    TakeOursFromKeyed(name)
  end
end

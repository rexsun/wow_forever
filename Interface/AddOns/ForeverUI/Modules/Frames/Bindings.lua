local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Click-casting. A binding key is a modifier prefix plus a mouse button number,
-- spelled exactly the way Blizzard's secure templates look attributes up:
--   "1"               left click
--   "shift-2"         shift + right click
--   "alt-ctrl-1"      alt + ctrl + left click (order is always alt, ctrl, shift)
-- A binding is { kind = "spell", spell = "Flash Heal" } | { kind = "target" } | { kind = "menu" }.
--
-- Spells are stored by NAME, never by ID or from a built-in list: the name casts
-- your highest rank as you level, and whatever Forever's reworked classes
-- actually have comes straight from your spellbook.

-- Buttons 6 to 8 are bindable too. Not every mouse sends them, and the game
-- only delivers what the mouse reports, so they sit in the list quietly and
-- work for whoever has them.
--
-- The wheel isn't a click, so the game never sends it to a frame. While the
-- mouse is over one of ours, the wheel is bound (securely, so it works in
-- combat) to click that frame with a made-up button name, and the secure
-- template looks attributes up for an unknown button as "type-<name>":
--   "wheelup"         scroll up over a frame
--   "shift-wheeldown" shift + scroll down
-- Mouse buttons 1-8 are real clicks on the frame. Everything in HOVER below
-- is not a click at all -- a wheel tick, a function key, Page Up -- and the
-- game never sends those to a frame. They work the same way the wheel always
-- has: while your mouse is over one of our frames the key is taken over and
-- pointed at a hidden button whose unit is "mouseover", and handed straight
-- back when you move off.
--
-- The function keys are here because a gaming mouse's extra buttons arrive as
-- F13 and upwards rather than as mouse buttons, so this is what makes a
-- twelve-button mouse fully bindable.
local SUFFIXES = { "1", "2", "3", "4", "5", "6", "7", "8",
  "wheelup", "wheeldown",
  "f16", "f17", "f18", "f19",
  "numpadstar", "pageup", "pagedown" }

ns.BINDING_SUFFIXES = SUFFIXES

local HOVER = {
  wheelup = "MOUSEWHEELUP", wheeldown = "MOUSEWHEELDOWN",
  f16 = "F16", f17 = "F17", f18 = "F18", f19 = "F19",
  numpadstar = "NUMPADMULTIPLY", pageup = "PAGEUP", pagedown = "PAGEDOWN",
}

local PREFIXES = { "", "shift-", "ctrl-", "ctrl-shift-", "alt-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-" }
ns.BINDING_PREFIXES = PREFIXES
local CLICK_SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3", Button4 = "4",
  Button5 = "5", Button6 = "6", Button7 = "7", Button8 = "8" }
local BUTTON_NAMES = { ["1"] = "Left", ["2"] = "Right", ["3"] = "Middle", ["4"] = "Button 4",
  ["5"] = "Button 5", ["6"] = "Button 6", ["7"] = "Button 7", ["8"] = "Button 8",
  wheelup = "Wheel Up", wheeldown = "Wheel Down",
  f16 = "F16", f17 = "F17", f18 = "F18", f19 = "F19",
  numpadstar = "Num Pad *", pageup = "Page Up", pagedown = "Page Down" }
local BOOK = BOOKTYPE_SPELL or "spell"
local _ -- throwaway for the many APIs whose first return we don't want

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------

function ns.ModifierPrefix()
  local prefix = ""
  if IsShiftKeyDown() then prefix = "shift-" .. prefix end
  if IsControlKeyDown() then prefix = "ctrl-" .. prefix end
  if IsAltKeyDown() then prefix = "alt-" .. prefix end
  return prefix
end

-- nil for buttons we don't bind (e.g. Button6+).
function ns.KeyFromClick(mouseButton)
  local suffix = CLICK_SUFFIX[mouseButton]
  return suffix and (ns.ModifierPrefix() .. suffix)
end

-- "alt-shift-1" -> "Alt + Shift + Left"
-- The modifiers are peeled off the front rather than the button guessed off
-- the back. Matching a trailing digit read "f16" as button 6, which is the
-- sort of thing that only shows up once a mouse's extra keys are bindable.
local MODIFIERS = { "alt", "ctrl", "shift" }

function ns.SplitKey(key)
  local rest, parts = key or "", {}
  local found = true
  while found do
    found = false
    for _, mod in ipairs(MODIFIERS) do
      local tail = rest:match("^" .. mod .. "%-(.*)$")
      if tail then
        parts[#parts + 1] = mod:sub(1, 1):upper() .. mod:sub(2)
        rest = tail
        found = true
        break
      end
    end
  end
  return parts, rest
end

function ns.DescribeKey(key)
  local parts, suffix = ns.SplitKey(key)
  parts[#parts + 1] = BUTTON_NAMES[suffix] or suffix
  return table.concat(parts, " + ")
end

-- Left before right before middle; plain before modified.
function ns.SortedBindingKeys(bindings)
  local keys = {}
  for _, suffix in ipairs(SUFFIXES) do
    for _, prefix in ipairs(PREFIXES) do
      if bindings[prefix .. suffix] then
        keys[#keys + 1] = prefix .. suffix
      end
    end
  end
  return keys
end

---------------------------------------------------------------------------
-- Secure attributes
---------------------------------------------------------------------------

-- What the game is actually told to cast.
--
-- A bare name always casts your highest rank, which is what you want almost
-- always and exactly what you don't want when you are downranking to save
-- mana. The game's own syntax for a particular rank is the name with the
-- rank in brackets after it -- Lesser Heal(Rank 2) -- and the rank line is
-- read straight from the spellbook, so whatever Forever calls its ranks is
-- what gets used.
function ns.CastName(binding)
  if not binding or not binding.spell or binding.spell == "" then
    return nil
  end
  if binding.rank and binding.rank ~= "" then
    return ("%s(%s)"):format(binding.spell, binding.rank)
  end
  return binding.spell
end

-- For the window and the log: "Lesser Heal" or "Lesser Heal (Rank 2)".
function ns.SpellLabel(binding)
  if not binding or not binding.spell then
    return nil
  end
  if binding.rank and binding.rank ~= "" then
    return ("%s (%s)"):format(binding.spell, binding.rank)
  end
  return binding.spell
end

-- There was a machine here once: one click written as a macro that knew both
-- roles, so shifting into Bear changed what it cast without anything being
-- rebound. It worked, but it asked you to hold the state in your head, and the
-- clicks with no macro form -- the unit menu -- could never join in. The role
-- grids replaced it: three independent grids on one roster, nothing switching.
-- See Modules/Grids. A tank's click still reaches the mob, through the
-- "unitsuffix" attribute below rather than through a macro.

-- The bindings belonging to a role, whether it is the one you are in (live on
-- ns.db) or the other one (parked in ns.db.modes by Modes.lua).
-- A role's clicks. One place, always: ns.db.modes[role].bindings. The live
-- ns.db.bindings IS that table for whichever role is active, so this answers
-- the same object either way and nothing can drift.
function ns.BindingsFor(role)
  return ns.BindingStore(role or ns.GetMode())
end

-- Every attribute the engine manages, mapped to its value or false when
-- unbound, so applying also clears bindings that were removed.
-- What a plain spell click hands the secure button. A lower rank goes as
-- that rank's own spell ID (the secure button then calls CastSpellByID with
-- the frame's unit): on Forever a name with a rank in it,
-- "Mark of the Wild(Rank 3)", landed on the caster instead of the player
-- clicked (RogueTryhard on CurseForge, 28 Sept 2026: "When adding lower ranks
-- manually and casting them w/ addon, they only cast on self"). A spell with
-- no rank stays its name, so it keeps casting your highest as you level.
local function SpellAttribute(b, byName)
  if b.rank and b.rank ~= "" and byName then
    local entry = byName[b.spell]
    for _, r in ipairs(entry and entry.ranks or {}) do
      if r.rank == b.rank and r.spellID then return r.spellID end
    end
  end
  return ns.CastName(b)
end
ns.SpellAttribute = SpellAttribute

function ns.BindingAttributes(bindings)
  local attrs = {}
  -- The spellbook, once, only if some click wants a lower rank.
  local byName
  for _, b in pairs(bindings or {}) do
    if type(b) == "table" and b.kind == "spell" and b.rank and b.rank ~= "" and ns.ScanSpellbook then
      local ok, _, found = pcall(ns.ScanSpellbook, true)
      byName = ok and found or nil
      break
    end
  end
  for _, prefix in ipairs(PREFIXES) do
    for _, suffix in ipairs(SUFFIXES) do
      -- A hover key's attributes are named after the made-up button the
      -- override binding clicks. The secure template turns a button name it
      -- doesn't know into the suffix "-" .. name (SecureButton_GetButtonSuffix,
      -- Blizzard_FrameXML/SecureTemplates.lua on the forever branch), so it
      -- reads "shift-" .. "spell" .. "-hfwheeldown". Without the dash nothing
      -- ever found these, and the wheel did nothing on any grid.
      local attrSuffix = HOVER[suffix] and ("-hf" .. suffix) or suffix
      local typeName, spellName = prefix .. "type" .. attrSuffix, prefix .. "spell" .. attrSuffix
      -- "unitsuffix" is what makes a tank's click land on the mob: the secure
      -- template appends it to the frame's unit for that one click, so a click
      -- on the mage's frame acts on "party2target" -- whatever the mage pulled.
      -- These only fire for tank-mode binding kinds; healer bindings never set
      -- them, so healer mode behaves exactly as before.
      local suffixName = prefix .. "unitsuffix" .. attrSuffix
      local macroName = prefix .. "macrotext" .. attrSuffix
      -- A raid mark: the secure template's own "raidtarget" action, which
      -- marks a unit with no macro and works in a fight (owner, 25 Sept
      -- 2026: "right click my healer in the grid ... populate those
      -- symbols"). Always on THEIR target - the mob that player is on; on
      -- your own frame, your target.
      local markerName, markActionName = prefix .. "marker" .. attrSuffix, prefix .. "action" .. attrSuffix
      local key = prefix .. suffix
      local b = bindings[key]
      attrs[typeName], attrs[spellName], attrs[suffixName], attrs[macroName] = false, false, false, false
      attrs[markerName], attrs[markActionName] = false, false
      if b and b.kind == "mark" then
        attrs[typeName], attrs[suffixName] = "raidtarget", "target"
        attrs[markerName] = tostring(b.marker or 8)
        attrs[markActionName] = (b.marker == 0) and "clear" or "set"
      end

      if b and b.kind == "engage" then
        attrs[typeName], attrs[macroName] = "macro", ns.EngageMacro(ns.CastName(b))
      end
      if b and b.their and (b.kind == "spell" or b.kind == "assist") then
        attrs[suffixName] = "target"
      end
      if b and b.kind == "assist" then
        attrs[typeName], attrs[suffixName] = "target", "target" -- target THEIR target
      elseif b and b.kind == "spell" then
        -- Smart cast, a trinket or an instant fired first (Healer.lua): the
        -- click becomes a small macro. Without any of those it stays a plain
        -- spell, exactly as before.
        local macro = (not b.their) and ns.SpellMacro and ns.SpellMacro(b) or nil
        if macro then
          attrs[typeName], attrs[macroName] = "macro", macro
        else
          attrs[typeName], attrs[spellName] = "spell", SpellAttribute(b, byName)
        end
      elseif b and b.kind == "macro" then
        -- Your own macro on this click (Healer.lua).
        local text = ns.BindingMacroText and ns.BindingMacroText(b)
        if text then
          attrs[typeName], attrs[macroName] = "macro", text
        end
      elseif b and b.kind == "target" then
        attrs[typeName] = "target"
      elseif b and b.kind == "menu" then
        attrs[typeName] = "togglemenu"
      elseif b and b.kind == "focus" then
        attrs[typeName] = "focus" -- makes that player your focus target
      end
    end
  end
  return attrs
end

-- The wheel.
--
-- The textbook way is a secure snippet that binds the wheel as the mouse enters
-- a frame. Forever's client can't run secure snippets at all - the function
-- that compiles them (loadstring_untainted) isn't there, so every one of them
-- dies with "attempt to call a nil value". So instead there is one hidden
-- button whose unit is "mouseover" - whoever's frame the mouse is on - and the
-- wheel is bound to click it:
--   out of combat: only while the mouse is over one of our frames, so the wheel
--                  zooms the camera everywhere else;
--   in combat:     bindings can't change, so it is taken as the fight starts
--                  and handed back when it ends; a tick with the mouse off
--                  the frames does the key's own camera zoom or chat paging
--                  (ns.PassWheelThrough) instead of nothing.
-- Only directions with a spell on them are ever taken.
-- One hidden button per role: with all three grids on screen, the wheel over
-- the tank grid has to cast the tank's wheel spell, not the active role's.
local wheelButtons, wheelHover, wheelRole = {}, false, nil
local WHEEL_NAMES = { healer = "ForeverUIFramesWheelButton", tank = "ForeverUIFramesWheelButtonTank",
  dps = "ForeverUIFramesWheelButtonDps" }

local REVERSED = { wheelup = "MOUSEWHEELDOWN", wheeldown = "MOUSEWHEELUP" }

function ns.WheelKeys(bindings)
  local keys = {}
  local reverse = ns.db and ns.db.reverseWheel
  for _, prefix in ipairs(PREFIXES) do
    for suffix, gameKey in pairs(HOVER) do
      -- Reversed (a Mac with natural scrolling): the game hears the opposite
      -- of the way you roll, so "Wheel Down" is listened for as Wheel Up.
      local wheelKey = reverse and REVERSED[suffix] or gameKey
      if bindings[prefix .. suffix] then
        keys[prefix:upper() .. wheelKey] = "hf" .. suffix
      end
    end
  end
  return keys
end

-- What the wheel does when it isn't over a frame.
--
-- In a fight the wheel stays ours from the pull to the end (see above), so
-- without this it did nothing anywhere else: no camera zoom until combat
-- ended (owner, 23 Sept 2026: "when in combat ... scroll up and down stop
-- working"). A tick away from the frames now does what that key is bound to
-- in the game's own Key Bindings, for the few bindings an addon may run in
-- combat: the camera zoom and paging the chat. Blizzard's binding bodies are
-- copied (Bindings_Standard.xml), so it zooms exactly as far as it would.
local PASS_THROUGH = {
  CAMERAZOOMIN = function()
    if MoveViewInStart then MoveViewInStart(1.0, 0, true) elseif CameraZoomIn then CameraZoomIn(1.0) end
  end,
  CAMERAZOOMOUT = function()
    if MoveViewOutStart then MoveViewOutStart(1.0, 0, true) elseif CameraZoomOut then CameraZoomOut(1.0) end
  end,
  CHATPAGEUP = function()
    local util = ChatFrameUtil
    if util and util.ChatPageUp then util.ChatPageUp() elseif ChatFrame_ChatPageUp then ChatFrame_ChatPageUp() end
  end,
  CHATPAGEDOWN = function()
    local util = ChatFrameUtil
    if util and util.ChatPageDown then util.ChatPageDown() elseif ChatFrame_ChatPageDown then ChatFrame_ChatPageDown() end
  end,
}
ns.WHEEL_PASS_THROUGH = PASS_THROUGH

-- The key the game heard, modifiers included, for a click named "hfwheelup".
local function HeardKey(click)
  local suffix = type(click) == "string" and click:match("^hf(.+)$")
  if not suffix or not HOVER[suffix] then
    return nil
  end
  local key = (ns.db and ns.db.reverseWheel and REVERSED[suffix]) or HOVER[suffix]
  local mods = ""
  if IsAltKeyDown and IsAltKeyDown() then mods = mods .. "ALT-" end
  if IsControlKeyDown and IsControlKeyDown() then mods = mods .. "CTRL-" end
  if IsShiftKeyDown and IsShiftKeyDown() then mods = mods .. "SHIFT-" end
  return mods .. key
end
ns.WheelHeardKey = HeardKey

function ns.PassWheelThrough(click)
  if wheelHover or not GetBindingAction then
    return nil
  end
  local key = HeardKey(click)
  -- Without the override check: the binding you set, not the one we put
  -- over it for the fight.
  local action = key and GetBindingAction(key)
  local run = action and PASS_THROUGH[action]
  if run then
    pcall(run)
    return action
  end
  return nil
end

local function WheelButton(role)
  role = WHEEL_NAMES[role or ""] and role or ns.GetMode()
  local button = wheelButtons[role]
  if not button then
    button = CreateFrame("Button", WHEEL_NAMES[role], UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("unit", "mouseover")
    -- A wheel tick is a key-down with no key-up. The template acts on the up
    -- unless told otherwise (or the "cast on key down" option is on), so
    -- without this a tick did nothing for anyone casting on key up.
    button:SetAttribute("useOnKeyDown", true)
    button.isWheelButton = true
    button.wheelRole = role
    -- Insecure, and only ever reading: the secure click still goes ahead
    -- (at "mouseover", which is nobody when you're over nothing at all).
    if button.HookScript then
      button:HookScript("PreClick", function(_, click, down)
        if down ~= false then
          ns.PassWheelThrough(click)
        end
      end)
    end
    wheelButtons[role] = button
    if role == "healer" then ns.wheelButton = button end
    if ns.HookCasts then ns.HookCasts(button) end
  end
  return button
end
ns.WheelButton = WheelButton

-- Point a role's wheel button at that role's clicks. Secure attributes, so
-- out of combat only.
local function LoadWheel(role)
  local button = WheelButton(role)
  for name, value in pairs(ns.BindingAttributes(ns.BindingsFor(role))) do
    if name:find("-hf", 1, true) then
      button:SetAttribute(name, value or nil)
    end
  end
  return button
end

local function ClearAllWheels()
  for _, button in pairs(wheelButtons) do
    ClearOverrideBindings(button)
  end
end

-- Is this key already doing something of the player's own that we couldn't
-- do for them in a fight - an action button, a bar button's click, a macro?
-- Camera zoom and chat paging don't count: PassWheelThrough does those.
-- Read with our own wheel bindings cleared, so what's found is theirs.
local function KeyIsTheirs(key)
  if not GetBindingAction then return false end
  local ok, action = pcall(GetBindingAction, key, true)
  if not ok or type(action) ~= "string" or action == "" then return false end
  if PASS_THROUGH[action] then return false end
  if action:find("ForeverUIFramesWheelButton", 1, true) then return false end
  return true
end
ns.WheelKeyIsTheirs = KeyIsTheirs

-- Both of these change bindings, which the game forbids in combat.
-- `role`: the grid under the mouse (the active role when unknown).
-- `forCombat`: the take that lasts the whole fight. Then a wheel key the
-- player has on something else - a bar button (owner, 25 Sept 2026: "it won't
-- let me cast up and down scroll buttons on the bars in combat") - is left
-- to that: an addon can't press an action button for you mid-fight, so taking
-- the key would leave the bar dead until combat ends. Over a frame out of
-- combat the frames still win, as before.
ns.wheelLeftAlone = {}
function ns.TakeWheel(role, forCombat)
  if InCombatLockdown() or not SetOverrideBindingClick then
    return false
  end
  role = role or wheelRole or ns.GetMode()
  wheelRole = role
  local owner = LoadWheel(role)
  ClearAllWheels()
  local taken = false
  for k in pairs(ns.wheelLeftAlone) do ns.wheelLeftAlone[k] = nil end
  for key, click in pairs(ns.WheelKeys(ns.BindingsFor(role))) do
    if forCombat and KeyIsTheirs(key) then
      ns.wheelLeftAlone[key] = true
    else
      SetOverrideBindingClick(owner, true, key, owner:GetName(), click)
      taken = true
    end
  end
  return taken
end

function ns.ReleaseWheel()
  if InCombatLockdown() or not ClearOverrideBindings or not next(wheelButtons) then
    return false
  end
  ClearAllWheels()
  return true
end

local function HookWheel(button)
  if button.hfWheelHooked or not button.HookScript then
    return
  end
  button.hfWheelHooked = true
  button:HookScript("OnEnter", function(self)
    wheelHover = true
    ns.hoverButton = self
    ns.TakeWheel(ns.ButtonGrid and ns.ButtonGrid(self) or nil)
  end)
  button:HookScript("OnLeave", function()
    wheelHover = false
    ns.ReleaseWheel()
  end)
end

-- PLAYER_REGEN_DISABLED arrives just before the lockdown does, which is the
-- last moment the wheel can be taken for the fight.
function ns.WheelCombat(entering)
  if entering then
    ns.TakeWheel(nil, true)
  elseif not wheelHover then
    ns.ReleaseWheel()
  end
end

-- Built once per change: the same attribute names get applied to every
-- button, and this runs whenever a frame appears.
-- Cached per grid. One cache was fine when there was one grid; with three on
-- screen it would hand the tank's buttons whichever role's clicks happened to
-- be built first, and the frames would look perfect while casting the wrong
-- spell at the wrong unit.
local cachedAttrs = {}

local function Attributes(role)
  role = role or ns.GetMode()
  if not cachedAttrs[role] then
    cachedAttrs[role] = ns.BindingAttributes(ns.BindingsFor(role))
  end
  return cachedAttrs[role]
end
ns.GridAttributes = Attributes

function ns.ForgetBindingAttributes(role)
  if role then
    cachedAttrs[role] = nil
  else
    cachedAttrs = {}
  end
end

-- Bind one button directly.
--
-- The header's _initialAttribute mechanism is meant to do this for buttons the
-- game creates itself, and on a normal client it does. Forever's restricted
-- environment has already been caught dropping one of these setup paths
-- (initialConfigFunction), and a frame that comes out unbound looks exactly
-- like settings that failed to save. So every button is bound here as well,
-- the plain way, the moment it has a unit.
function ns.BindButton(button)
  if not button or InCombatLockdown() then
    return false
  end
  -- The grid the button belongs to, not the grid being configured. These are
  -- different the moment more than one is on screen.
  for name, value in pairs(Attributes(ns.ButtonGrid(button))) do
    local want = value or nil
    if button:GetAttribute(name) ~= want then
      button:SetAttribute(name, want)
    end
  end
  HookWheel(button)
  if ns.HookCasts then ns.HookCasts(button) end
  return true
end

local function ApplyToHeader(header, attrs)
  -- Buttons the header creates later (someone joins mid-fight) copy these
  -- securely, so they come out already bound even in combat.
  -- Every header attribute change re-lays out the whole group unless "_ignore"
  -- is set (Blizzard's own trick); these don't affect layout, so skip that.
  local oldIgnore = header:GetAttribute("_ignore")
  header:SetAttribute("_ignore", "attributeChanges")
  local names = {}
  for name, value in pairs(attrs) do
    if value then
      names[#names + 1] = name
      header:SetAttribute("_initialAttribute-" .. name, value)
    end
  end
  table.sort(names)
  header:SetAttribute("_initialAttributeNames", table.concat(names, ","))
  header:SetAttribute("_ignore", oldIgnore)

  -- Buttons that already exist.
  local i, child = 1, header:GetAttribute("child1")
  while child do
    for name, value in pairs(attrs) do
      local want = value or nil
      if child:GetAttribute(name) ~= want then
        child:SetAttribute(name, want)
      end
    end
    i = i + 1
    child = header:GetAttribute("child" .. i)
  end
end

-- Party header and all eight raid group headers.
local function ApplyNow()
  cachedAttrs = {} -- the bindings may have just changed, for any grid
  if SetOverrideBindingClick then
    for role in pairs(WHEEL_NAMES) do
      LoadWheel(role)
    end
    if wheelHover then ns.TakeWheel() end
  end
  -- Each grid's headers get THAT grid's clicks. ns.AllHeaders() is only the
  -- grid swapped in last, and it got the playing role's clicks, so a player
  -- joining mid-way could get another role's spells on their new frame.
  local roleOf = {}
  for role, set in pairs(ns.gridSets or {}) do
    if set.header then roleOf[set.header] = role end
    for _, h in ipairs(set.raidHeaders or {}) do roleOf[h] = role end
    if set.petHeader then roleOf[set.petHeader] = role end
  end
  local active = ns.activeGrid or ns.GetMode()
  for _, h in ipairs(ns.AllHeaders()) do roleOf[h] = roleOf[h] or active end
  if not next(roleOf) then
    return
  end
  for header, role in pairs(roleOf) do
    ApplyToHeader(header, Attributes(role))
  end
  -- And every frame currently showing someone, whether or not the header
  -- lists it as one of its children.
  ns.ForEachButton(ns.BindButton)
  -- Tank mode's Loose list has its own secure buttons to bind.
  if ns.db.mode == "tank" and ns.BindLooseSlots then
    ns.BindLooseSlots()
  end
end

local applyQueued = false

-- Returns true if applied now, false if it will apply when combat ends.
function ns.ApplyBindings()
  if InCombatLockdown() then
    if not applyQueued then
      applyQueued = true
      ns.WhenOutOfCombat(function()
        applyQueued = false
        ApplyNow()
        if ns.RefreshOptions then ns.RefreshOptions() end
      end)
    end
    return false
  end
  ApplyNow()
  return true
end

-- ENGAGE (tank mode): one click on a player, and you are on the thing that is
-- on them. There is no unit for "the mob attacking this player", only for
-- "this player's target", and nothing about a secure frame can change in a
-- fight. What CAN decide at the moment of the click is a macro condition, and
-- while your mouse is on a frame, "mouseover" IS that frame's player. So:
--   1. if their target is an enemy, that is almost always the mob on them: take it;
--   2. if it isn't, step to the next enemy -- click again to walk the pack;
--   3. start attacking, and if a spell was named (your taunt), cast it.
function ns.EngageMacro(spell)
  local lines = {
    "/stopmacro [@mouseover,noexists]", -- an empty Loose slot does nothing
    "/target [@mouseovertarget,harm,nodead]",
    "/targetenemy [@mouseovertarget,noharm][@mouseovertarget,noexists][@mouseovertarget,dead]",
    "/startattack [harm,nodead]",
  }
  if spell and spell ~= "" then
    lines[#lines + 1] = "/cast [harm,nodead] " .. spell
  end
  return table.concat(lines, "\n")
end

-- Every change is written down with where it came from. A binding that
-- disappears between sessions is otherwise impossible to explain after the
-- fact, and "it isn't saving" and "something overwrote it" look identical.
local LOG_LENGTH = 12

function ns.LogBinding(key, binding, source)
  ns.db.bindingLog = ns.db.bindingLog or {}
  local log = ns.db.bindingLog
  table.insert(log, 1, {
    when = (time and time()) or 0,
    key = key,
    what = binding and (ns.SpellLabel(binding) or binding.kind) or "cleared",
    source = source or "options",
  })
  for i = #log, LOG_LENGTH + 1, -1 do
    log[i] = nil
  end
end

function ns.SetBinding(key, binding, source)
  -- Anything not written by the class defaults was picked by a person.
  if type(binding) == "table" and source ~= "class default" and source ~= "class button" then
    binding.chosen = true
  end
  -- Through the store, not through ns.db.bindings. They are the same table
  -- when nothing has reassigned it -- and "when nothing has reassigned it" is
  -- exactly the assumption that lost clicks before.
  ns.BindingsFor(ns.GetMode())[key] = binding
  if FUI.TouchProfile then FUI.TouchProfile() end
  if ns.Trace then
    ns.Trace(("SetBinding %s=%s (%s)"):format(key,
      tostring(binding and (binding.spell or binding.kind) or "cleared"), tostring(source)))
  end
  ns.LogBinding(key, binding, source)
  ns.Note(("bound %s -> %s (%s)"):format(key, binding and (ns.SpellLabel(binding) or binding.kind) or "cleared", source or "options"))
  ns.ApplyBindings()
  if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- What a healer should have on left click before touching anything
---------------------------------------------------------------------------

-- Best first. What matters is that the top entry you actually know ends up on
-- left click: a levelling Priest gets Lesser Heal, and Flash Heal takes over
-- the moment it's learned.
ns.CLASS_HEALS = {
  PRIEST  = { "Flash Heal", "Lesser Heal", "Heal", "Greater Heal" },
  DRUID   = { "Regrowth", "Healing Touch" },
  PALADIN = { "Flash of Light", "Holy Light" },
  SHAMAN  = { "Lesser Healing Wave", "Healing Wave" },
}

function ns.BestHealSpell()
  local class
  if UnitClass then
    _, class = UnitClass("player")
  end
  local wanted = class and ns.CLASS_HEALS[class]
  if not wanted then
    return nil
  end
  local _, byName = ns.ScanSpellbook(false)
  for _, name in ipairs(wanted) do
    if byName[name] then
      return name
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- What a tank should have on the mouse before touching anything (tank mode)
---------------------------------------------------------------------------

-- Taunts, best first. These are cast on the clicked player's TARGET -- the mob
-- they pulled -- not on the player. An unknown name is simply never found.
ns.CLASS_TAUNTS = {
  WARRIOR     = { "Taunt", "Mocking Blow" },
  DRUID       = { "Growl" },
  PALADIN     = { "Hand of Reckoning", "Reckoning" },
  DEATHKNIGHT = { "Dark Command", "Death Grip" },
  MONK        = { "Provoke" },
  DEMONHUNTER = { "Torment" },
  HUNTER      = { "Distracting Shot" },
  SHAMAN      = { "Earth Shock" }, -- the Classic shaman tank's threat button
}

-- Rescues cast ON the player in trouble: they take the hit, or pull it off.
ns.CLASS_RESCUES = {
  WARRIOR = { "Intervene" },
  PALADIN = { "Righteous Defense", "Blessing of Protection", "Hand of Protection" },
}

-- A spell that has to land on the mob. The game can say so itself
-- (C_Spell.IsSpellHelpful); where it can't, every taunt above still counts.
local aimedAtMob
function ns.IsAimedAtTheirTarget(spell, helpful)
  if not aimedAtMob then
    aimedAtMob = {}
    for _, list in pairs(ns.CLASS_TAUNTS) do
      for _, name in ipairs(list) do
        aimedAtMob[name] = true
      end
    end
  end
  return aimedAtMob[spell] == true or helpful == false
end

local function FirstKnown(list)
  local _, byName = ns.ScanSpellbook(true)
  for _, name in ipairs(list or {}) do
    if byName[name] then
      return name
    end
  end
  return nil
end

local function PlayerClass()
  if UnitClass then
    local _, class = UnitClass("player")
    return class
  end
end

function ns.BestTauntSpell()
  return FirstKnown(ns.CLASS_TAUNTS[PlayerClass()])
end

function ns.BestRescueSpell()
  return FirstKnown(ns.CLASS_RESCUES[PlayerClass()])
end

---------------------------------------------------------------------------
-- Class defaults, per mode
---------------------------------------------------------------------------

-- Is this click still the out-of-the-box one, free for a class default?
--
-- "Target the unit" is the default for left click AND a perfectly good thing
-- to choose -- plenty of healers want a plain click to target. Judged by kind
-- alone the two are the same, so a Target somebody picked was quietly
-- replaced with a heal the next time the defaults ran (every login, while the
-- beta client drops the "defaults done" mark with the rest of the saved
-- settings). A click set by hand carries `chosen`, and a chosen click is never
-- untouched, whatever it does.
local function Untouched(binding)
  return not binding or (binding.kind == "target" and not binding.chosen)
end
ns.BindingUntouched = Untouched

-- Put a heal on left click. Done once per class per profile, and only while
-- left click is still the out-of-the-box "target the unit" - anything you
-- chose yourself is left alone. `force` is the options button.
local function ApplyHealDefaults(force)
  local spell = ns.BestHealSpell()
  if not spell then
    return nil
  end
  local _, class = UnitClass("player")
  ns.db.classDefaults = ns.db.classDefaults or {}
  if not force then
    local current = ns.db.bindings["1"]
    local untouched = Untouched(current)
    if ns.db.classDefaults[class] or not untouched then
      return nil
    end
  end
  ns.db.classDefaults[class] = true
  ns.SetBinding("1", { kind = "spell", spell = spell }, force and "class button" or "class default")
  return spell
end

-- What a damage dealer presses on somebody ELSE mid-fight.
--
-- Not damage: nothing here is aimed at a mob. A DPS grid is for the moments
-- you stop attacking for a second and do something for the group -- take a
-- curse off, shield the person about to die, hand your threat to the tank.
-- Best first; an unknown name is simply never found.
ns.CLASS_UTILITY = {
  DRUID    = { "Remove Curse", "Abolish Poison", "Cure Poison", "Innervate", "Rebirth" },
  PRIEST   = { "Dispel Magic", "Abolish Disease", "Cure Disease", "Power Word: Shield" },
  PALADIN  = { "Cleanse", "Purify", "Blessing of Protection", "Hand of Protection" },
  SHAMAN   = { "Cure Poison", "Cure Disease", "Purge", "Ancestral Spirit" },
  MAGE     = { "Remove Lesser Curse", "Remove Curse", "Arcane Intellect", "Spellsteal" },
  WARLOCK  = { "Soulstone Resurrection", "Unending Breath", "Detect Invisibility" },
  ROGUE    = { "Tricks of the Trade", "Blind", "Kick" },
  HUNTER   = { "Misdirection", "Tranquilizing Shot" },
  WARRIOR  = { "Intervene", "Battle Shout" },
}

function ns.BestUtilitySpell()
  return FirstKnown(ns.CLASS_UTILITY[PlayerClass()])
end

-- Out of the box for damage: the group spell on left click, the unit menu on
-- right, assist on shift -- so a click on a frame is never wasted.
local function ApplyDpsDefaults(force)
  local helper = ns.BestUtilitySpell()
  local class = PlayerClass()
  ns.db.classDefaults = ns.db.classDefaults or {}
  if not force then
    local current = ns.db.bindings["1"]
    local untouched = Untouched(current)
    if ns.db.classDefaults[class] or not untouched then
      return nil
    end
  end
  ns.db.classDefaults[class] = true
  local source = force and "class button" or "class default"
  if helper then
    ns.SetBinding("1", { kind = "spell", spell = helper }, source)
  else
    -- No group spell known: the click still picks the person, which is what
    -- an unbound frame does everywhere else.
    ns.SetBinding("1", { kind = "target" }, source)
  end
  if force or not ns.db.bindings["2"] then
    ns.SetBinding("2", { kind = "menu" }, source)
  end
  -- Assist: target what they are fighting, so you are on the same mob.
  if force or not ns.db.bindings["shift-1"] then
    ns.SetBinding("shift-1", { kind = "assist" }, source)
  end
  return helper
end

-- Out of the box for a tank: left click taunts whatever that player has on
-- them, right click targets it, shift + left rescues them if your class can.
local function ApplyTankDefaults(force)
  local taunt = ns.BestTauntSpell()
  local class = PlayerClass()
  if not taunt then
    -- No taunt (or none learned yet): the click still gets you onto the mob.
    ns.db.classDefaults = ns.db.classDefaults or {}
    local current = ns.db.bindings["1"]
    if class and (force or (not ns.db.classDefaults[class] and Untouched(current))) then
      -- Deliberately NOT marking the class done. No taunt was found, which on
      -- a fresh character usually means it has not been learned yet -- and the
      -- marker is one-shot, so setting it here would mean the taunt never got
      -- seeded at all, however long you played. The engage click is seeded now
      -- and the taunt lands the first time we can see it.
      ns.SetBinding("1", { kind = "engage" }, force and "class button" or "class default")
      return "engage"
    end
    return nil
  end
  ns.db.classDefaults = ns.db.classDefaults or {}
  if not force then
    local current = ns.db.bindings["1"]
    local untouched = Untouched(current)
    if ns.db.classDefaults[class] or not untouched then
      -- No repair here any more.
      --
      -- This used to notice a tank with no taunt bound and put one on right
      -- click "if right click was still the menu nobody chose". It could not
      -- tell a menu nobody chose from a menu somebody chose, and it ran on
      -- every mode switch -- so it overwrote a deliberate binding with a
      -- taunt. Seeding now happens only for a role with NO clicks at all,
      -- which cannot be the result of a choice. The button on the window
      -- (force) is how you ask for the defaults back.
      return nil
    end
  end
  ns.db.classDefaults[class] = true
  local source = force and "class button" or "class default"
  -- Left click gets you onto the mob and swinging; right click does the same
  -- and taunts. Taunt has a cooldown, so it isn't the one you press by reflex.
  ns.SetBinding("1", { kind = "engage" }, source)
  local right = ns.db.bindings["2"]
  if force or not right or right.kind == "menu" then
    ns.SetBinding("2", { kind = "engage", spell = taunt }, source)
  end
  local rescue = ns.BestRescueSpell()
  if rescue and (force or not ns.db.bindings["shift-1"]) then
    ns.SetBinding("shift-1", { kind = "spell", spell = rescue }, source)
  end
  if force or not ns.db.bindings["shift-2"] then
    ns.SetBinding("shift-2", { kind = "menu" }, source)
  end
  return taunt
end

-- The seeding that runs depends on the role this character is in.
-- Seeding is for a role that has NOTHING, and only then.
--
-- The old guards asked "is left click still the out-of-the-box target?" and
-- "have we marked this class done?". Both could be true for a role the player
-- had set up -- and SetMode calls this on every switch, so each one quietly
-- overwrote a click. That is the whole "my tanking keybinds do not save":
-- they saved, and then the next mode switch wrote over them with a default.
--
-- An empty store is the only safe signal, because it cannot be the result of
-- a choice.
-- "Untouched" means: still exactly what a fresh profile is handed.
--
-- Not "empty" -- a fresh store is seeded with the default pair, so empty
-- never happens and seeding would never run for a new player. And not "is
-- left click still target", which is true of plenty of set-up roles.
local function SameBinding(a, b)
  if a == nil or b == nil then
    return a == b
  end
  -- A click somebody chose is never "the default", even when it does the
  -- same thing: Target + Menu picked by hand is a set-up role.
  if a.chosen or b.chosen then
    return false
  end
  return a.kind == b.kind and a.spell == b.spell and (a.their or false) == (b.their or false)
    and a.marker == b.marker
end

-- Only the clicks seeding would actually WRITE are considered.
--
-- Looking at the whole store would veto on any unrelated binding -- a spell
-- on shift+left should not stop a fresh left click being filled in. Looking
-- at left click alone is what let this overwrite a set-up role: a tank whose
-- left click happened to be "target" still had a taunt on right click, and
-- the seeding took that as permission to rewrite both.
-- Left and right only. The shift clicks seeding also fills are extras; a
-- spell already on shift+left should not stop a fresh left click getting its
-- class heal, and protecting these two is what stops a set-up role being
-- rewritten.
local SEEDED_KEYS = { "1", "2" }

local function AlreadySetUp()
  local role = ns.GetMode()
  local store = ns.BindingsFor(role)
  if next(store) == nil then
    return false   -- nothing at all: definitely never set up
  end
  local fresh = (ns.MODE_DEFAULTS[role] or {}).bindings or ns.DEFAULT_BINDINGS or {}
  for _, key in ipairs(SEEDED_KEYS) do
    if not SameBinding(store[key], fresh[key]) then
      return true  -- this is one of ours and it has been chosen
    end
  end
  return false
end
ns.BindingsAreDefault = function() return not AlreadySetUp() end

function ns.ApplyClassDefaults(force)
  if not force and AlreadySetUp() then
    return nil
  end
  if ns.db.mode == "tank" then
    return ApplyTankDefaults(force)
  elseif ns.db.mode == "dps" then
    return ApplyDpsDefaults(force)
  end
  return ApplyHealDefaults(force)
end

-- A click on a row in the options panel: the click itself says which key to bind.
function ns.BindFromClick(binding, mouseButton)
  local key = ns.KeyFromClick(mouseButton)
  if not key then
    return nil
  end
  local copy = {}
  for k, v in pairs(binding) do copy[k] = v end
  ns.SetBinding(key, copy)
  return key
end

---------------------------------------------------------------------------
-- Spellbook
---------------------------------------------------------------------------

-- Reading the spellbook differs between clients, so try each shape in turn.
-- Returns a list of { slot, bank } to look at, or nil if this client's
-- spellbook can't be read at all.
local function SpellBookSlots()
  local slots = {}
  if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, numSlots = GetSpellTabInfo(tab)
      if offset and numSlots then
        for slot = offset + 1, offset + numSlots do
          slots[#slots + 1] = slot
        end
      end
    end
    if #slots > 0 then
      return slots, "classic"
    end
  end
  -- Newer clients moved it under C_SpellBook.
  local book = C_SpellBook
  if book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo then
    for line = 1, book.GetNumSpellBookSkillLines() do
      local info = book.GetSpellBookSkillLineInfo(line)
      if info and info.itemIndexOffset and info.numSpellBookItems then
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          slots[#slots + 1] = slot
        end
      end
    end
    if #slots > 0 then
      return slots, "modern"
    end
  end
  return nil
end

-- name, spell id, and the RANK line under the name ("Rank 1"), which is the
-- whole basis of downranking. Both spellbook APIs hand it back as a second
-- return beside the name; it used to be dropped on the floor here.
local function SpellAt(slot, shape)
  if shape == "classic" then
    local slotType, spellID = GetSpellBookItemInfo(slot, BOOK)
    if slotType ~= "SPELL" or (IsPassiveSpell and IsPassiveSpell(slot, BOOK)) then
      return nil
    end
    local name, rank = GetSpellBookItemName(slot, BOOK)
    return name, spellID, rank
  end
  local book = C_SpellBook
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  local info = book.GetSpellBookItemInfo and book.GetSpellBookItemInfo(slot, bank)
  if not info or info.isPassive or (info.itemType and info.itemType ~= 0 and info.spellID == nil) then
    return nil
  end
  local name, rank
  if book.GetSpellBookItemName then
    name, rank = book.GetSpellBookItemName(slot, bank)
  end
  name = info.name or name
  rank = info.subName or rank
  return name, info.spellID, rank
end

-- Castable spells you know, one entry per NAME, plus any you added by hand.
-- Harmful spells only when asked for. Returns list, byName, couldRead.
--
-- Each entry also carries `ranks`, every rank of that spell in the order the
-- spellbook lists them -- lowest first, highest last. The entry's own spellID
-- and icon stay the highest rank, so everything that only wants "the spell"
-- is unaffected; downranking reads `ranks`.
function ns.ScanSpellbook(includeHarmful)
  local list, byName = {}, {}
  local isHelpful = C_Spell and C_Spell.IsSpellHelpful
  local getTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

  local function add(name, spellID, helpful, manual, rank)
    if not name or name == "" then
      return
    end
    local entry = byName[name]
    if not entry then
      entry = { name = name, ranks = {} }
      byName[name] = entry
      list[#list + 1] = entry
    end
    entry.spellID = spellID or entry.spellID
    entry.icon = (spellID and getTexture and getTexture(spellID)) or entry.icon
    entry.helpful = helpful
    entry.manual = manual or entry.manual
    if rank and rank ~= "" then
      entry.ranks[#entry.ranks + 1] = {
        rank = rank,
        spellID = spellID,
        icon = (spellID and getTexture and getTexture(spellID)) or nil,
      }
      entry.rank = rank   -- the highest seen so far
    end
  end

  local slots, shape = SpellBookSlots()
  for _, slot in ipairs(slots or {}) do
    local name, spellID, rank = SpellAt(slot, shape)
    if name then
      local helpful = (not isHelpful) or (spellID and isHelpful(spellID)) and true or false
      if helpful or includeHarmful then
        add(name, spellID, helpful, nil, rank)
      end
    end
  end

  -- Spells you typed in yourself: always listed, whatever the client does.
  for _, name in ipairs(ns.db.manualSpells or {}) do
    add(name, nil, true, true)
  end

  return list, byName, slots ~= nil
end

function ns.AddManualSpell(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    return false
  end
  for _, existing in ipairs(ns.db.manualSpells) do
    if existing == name then
      return false
    end
  end
  table.insert(ns.db.manualSpells, name)
  ns.SetSetting("manualSpells", ns.db.manualSpells)
  return true
end

function ns.RemoveManualSpell(name)
  for i, existing in ipairs(ns.db.manualSpells) do
    if existing == name then
      table.remove(ns.db.manualSpells, i)
      ns.SetSetting("manualSpells", ns.db.manualSpells)
      return true
    end
  end
  return false
end

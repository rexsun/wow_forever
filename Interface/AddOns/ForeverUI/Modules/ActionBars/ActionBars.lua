local _, ns = ...

-- Action bars: our own buttons, Blizzard's art gone.
--
-- Buttons are built from Blizzard's own secure template, so clicking, casting,
-- cooldowns, keybind text and drag-and-drop keep working exactly as the game
-- intends - we only decide how many there are, how big they are and where.
--
-- The main bar swaps pages when you shapeshift, stealth or press the page
-- buttons. That has to happen during combat, which addon code may not do, so
-- the swap is handed to the game: each button gets an attribute driver whose
-- conditions the game evaluates itself, setting the button's action slot
-- without any of our code running.
--
-- Two attempts got this wrong before it worked.
--
-- A snippet through SecureHandlerStateTemplate:Execute is the textbook way,
-- and this client cannot compile snippets at all: it throws "attempt to call
-- a nil value" out of RestrictedExecution, which aborted the whole build and
-- left the bars half-made.
--
-- An attribute driver needs no compiler, but the value it sets is a *string*
-- -- that is what SecureCmdOptionParse returns -- and a button of type
-- "action" needs a number. UseAction("5") is not UseAction(5), so every
-- button had an action it could not use and no click did anything.
--
-- So the page is worked out in Lua and the attribute set as a number. The
-- cost is honest: a stance or stealth swap mid-fight cannot re-page until the
-- fight ends, because setting attributes in combat is not allowed. On a
-- client that could compile a snippet this would be done the textbook way.

local module = ns.RegisterModule({
  name = "ActionBars",
  title = "Action Bars",
})

-- Action slots. The main bar is 1-12 and pages on top of that; the others are
-- fixed ranges the game reserves for the extra bars.
-- The starting positions are the owner's own layout, captured from a live
-- setup rather than guessed: a six-wide block of large buttons above the
-- bags, bar 2 stacked above it, bar 3 tucked into the bottom-right corner
-- and bar 4 on end down the right edge.
local BARS = {
  { key = "bar1", label = "Main bar", first = 1,  paged = true,  default = { "BOTTOM", "BOTTOM", 0, 68 } },
  { key = "bar2", label = "Bar 2",    first = 61, default = { "BOTTOM", "BOTTOM", 0, 177 } },
  { key = "bar3", label = "Bar 3",    first = 49, default = { "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 48 } },
  -- Bar 4 starts life on end down the right edge; see `vertical` below.
  { key = "bar4", label = "Bar 4",    first = 25, default = { "RIGHT", "RIGHT", 0, -86 } },
  -- The game's other four (babylon on CurseForge, 27 Sept 2026: "doesn't
  -- have all 7"). Same slots as Blizzard's Bars 5-8 on this client
  -- (MultiActionBars.lua: LEFT page 4, MULTIBAR_5/6/7 pages 13-15), so
  -- whatever is already on them shows up. Off until switched on.
  { key = "bar5", label = "Bar 5",    first = 37,  default = { "RIGHT", "RIGHT", -46, -86 } },
  { key = "bar6", label = "Bar 6",    first = 145, default = { "BOTTOM", "BOTTOM", 0, 286 } },
  { key = "bar7", label = "Bar 7",    first = 157, default = { "BOTTOM", "BOTTOM", 0, 332 } },
  { key = "bar8", label = "Bar 8",    first = 169, default = { "BOTTOM", "BOTTOM", 0, 378 } },
}
module.BARS = BARS

-- The game's own binding command for the same slots (Bindings.xml). Keys set
-- in Blizzard's Key Bindings window -- or kept from before ForeverUI -- are
-- bound to these, not to our buttons, and press the same action slot.
local GAME_BINDINGS = {
  bar1 = "ACTIONBUTTON",          -- page 1, paged like ours
  bar2 = "MULTIACTIONBAR1BUTTON", -- bottom left, page 6
  bar3 = "MULTIACTIONBAR2BUTTON", -- bottom right, page 5
  bar4 = "MULTIACTIONBAR3BUTTON", -- right, page 3
  bar5 = "MULTIACTIONBAR4BUTTON", -- left, page 4
  bar6 = "MULTIACTIONBAR5BUTTON", -- page 13
  bar7 = "MULTIACTIONBAR6BUTTON", -- page 14
  bar8 = "MULTIACTIONBAR7BUTTON", -- page 15
}
module.GAME_BINDINGS = GAME_BINDINGS

-- Which page the main bar shows. Left to the game to evaluate: stance and
-- stealth change it mid-fight, when addons aren't allowed to.
local BUTTONS_PER_BAR = 12

-- Which page the main bar is showing right now. Stances and stealth put the
-- game on a "bonus" bar, which numbers 7 upwards.
local function CurrentPage()
  local bonus = GetBonusBarOffset and GetBonusBarOffset() or 0
  if bonus and bonus > 0 then
    return 6 + bonus
  end
  local page = GetActionBarPage and GetActionBarPage() or 1
  return (type(page) == "number" and page > 0) and page or 1
end
module.CurrentPage = CurrentPage

-- The slot a button uses on a given page. A number, always: an action button
-- given a string does nothing when you click it.
local function SlotFor(page, index)
  return (page - 1) * BUTTONS_PER_BAR + index
end
module.SlotFor = SlotFor

module.defaults = {
  -- Big buttons, no gap, six to a row: two tight blocks rather than one long
  -- strip. Taken from the owner's setup, which is what this is drawn around.
  buttonSize = 54,
  spacing = 0,
  perRow = 6,
  showKeybinds = true,
  showMacroText = true,
  flatButtons = true,
  hideBlizzardBars = true,
  -- Blizzard's pet and stance bars are left alone when these are on: we have
  -- no bars of our own for them, and hiding them took a hunter's pet buttons
  -- away (CurseForge comment, 25 Sept 2026). They only show when there is
  -- something on them; Edit Mode moves them.
  showPetBar = true,
  showStanceBar = false,
  hideMicroMenu = true,
  hideBags = true,
  hideXpBar = true,
  showEmptyButtons = false,
  cooldownNumbers = true,   -- a countdown on every button that isn't ready yet
  -- sprutorgel on CurseForge, 26 Sept 2026:
  rangeRed = true,          -- the whole icon red when the spell can't reach
  attackFlash = false,      -- Blizzard's red flash while auto-attacking / shooting
  ownButtonColor = false,   -- button borders in their own colour, not General's
  buttonBorderColor = { 0.62, 0.40, 1.00 },
  -- "character" saves keybinds to this character only; "account" to every
  -- character. nil means "wherever the game is currently saving".
  bindingScope = "character",
  -- Binding mode: hover a button and press a key (off = the old click-to-pick
  -- first), mouse buttons and the wheel bindable, modifiers held count as part
  -- of the binding, and a click when one is bound.
  hoverBind = true,
  allowMouse = true,
  allowModifiers = true,
  bindSound = true,
  iconZoom = 8,             -- percent of each icon edge cropped (sprutorgel, 28 Sept 2026)
  -- goldfish117 on CurseForge, 28 Sept 2026: "allow us to move abilities
  -- around by holding down shift". The bars stay locked; shift + drag picks
  -- a spell up the way Blizzard's own locked bars do.
  shiftDrag = true,
  bars = { bar1 = true, bar2 = true, bar3 = false, bar4 = false,
    bar5 = false, bar6 = false, bar7 = false, bar8 = false },
  -- A vertical bar is one button per row, whatever "buttons per row" says.
  vertical = { bar1 = false, bar2 = false, bar3 = false, bar4 = true,
    bar5 = true, bar6 = false, bar7 = false, bar8 = false },
  -- Each bar's own values, Bartender-style (a CurseForge request, 24 Sept
  -- 2026: "5 buttons for 1 bar, and another amount for second bar"):
  -- barOpts.bar2 = { buttons = 5, perRow = 5, size = 40, spacing = 2 }.
  -- Anything a bar leaves out follows the settings above.
  barOpts = {},
}

local BAR_FALLBACK = { perRow = "perRow", size = "buttonSize", spacing = "spacing" }

-- One bar's value for `field` (buttons, perRow, size, spacing): its own if
-- it has one, otherwise the shared setting (all 12 buttons, for the count).
function module.BarOpt(key, field)
  local settings = ns.db.modules.ActionBars
  local own = settings.barOpts and settings.barOpts[key]
  if own and own[field] ~= nil then
    return own[field]
  end
  if field == "buttons" then
    return 12
  end
  return settings[BAR_FALLBACK[field] or field]
end

-- A settings-page store for one bar: reads fall back, writes are the bar's own.
local function BarStore(key)
  return setmetatable({}, {
    __index = function(_, field) return module.BarOpt(key, field) end,
    __newindex = function(_, field, value)
      local settings = ns.db.modules.ActionBars
      settings.barOpts = settings.barOpts or {}
      settings.barOpts[key] = settings.barOpts[key] or {}
      settings.barOpts[key][field] = value
    end,
  })
end

module.BarStore = BarStore   -- the Quick Setup page edits bars through it too

function module.ResetBarOpts(key)
  local settings = ns.db.modules.ActionBars
  if settings.barOpts then settings.barOpts[key] = nil end
  module:Refresh()
  if ns.RefreshOptions then ns.RefreshOptions() end
end

local function BarsStore()
  return ns.db.modules.ActionBars.bars
end

local function VerticalStore()
  return ns.db.modules.ActionBars.vertical
end

module.options = {
  { type = "heading", label = "Buttons" },
  { type = "stepper", key = "buttonSize", label = "Button size", min = 18, max = 54, step = 2 },
  { type = "stepper", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1 },
  { type = "stepper", key = "perRow", label = "Buttons per row", min = 1, max = 12, step = 1 },
  { type = "checkbox", key = "showKeybinds", label = "Show keybind text" },
  { type = "checkbox", key = "showMacroText", label = "Show macro names" },
  { type = "checkbox", key = "cooldownNumbers", label = "Cooldown numbers (seconds until ready)",
    desc = "Drawn by the game itself, so they keep counting in combat." },
  { type = "checkbox", key = "flatButtons", label = "Flat buttons (icon fills the block)", reload = true },
  { type = "stepper", key = "iconZoom", label = "Icon zoom",
    desc = "How much of the spell's picture's edge is cropped. 8% trims its own frame; more zooms in.",
    min = 0, max = 30, step = 1, format = function(v) return ("%d%%"):format(v) end,
    apply = function() if module.RepaintAllButtons then module.RepaintAllButtons() end end },
  { type = "checkbox", key = "rangeRed", label = "Red icon when out of range",
    desc = "The whole button, not only the keybind - so it shows with keybinds off too.",
    apply = function() if module.RepaintAllButtons then module.RepaintAllButtons() end end },
  { type = "checkbox", key = "attackFlash", label = "Flash while auto-attacking or shooting",
    desc = "Blizzard's red flash. Off, the button just stays lit while it's on.",
    apply = function() if module.RepaintAllButtons then module.RepaintAllButtons() end end },
  { type = "checkbox", key = "ownButtonColor", label = "Own colour for the button borders",
    desc = "Off, they follow General > Border colour like everything else.",
    apply = function() if module.RepaintAllButtons then module.RepaintAllButtons() end end },
  { type = "color", key = "buttonBorderColor", label = "Button border colour",
    apply = function() if module.RepaintAllButtons then module.RepaintAllButtons() end end },

  { type = "heading", label = "Your bars" },
  { type = "checkbox", key = "bar2", label = "Show bar 2", store = BarsStore },
  { type = "checkbox", key = "bar3", label = "Show bar 3", store = BarsStore },
  { type = "checkbox", key = "bar4", label = "Show bar 4", store = BarsStore },
  { type = "checkbox", key = "bar5", label = "Show bar 5", store = BarsStore },
  { type = "checkbox", key = "bar6", label = "Show bar 6", store = BarsStore },
  { type = "checkbox", key = "bar7", label = "Show bar 7", store = BarsStore },
  { type = "checkbox", key = "bar8", label = "Show bar 8", store = BarsStore },
  -- Vertical is on each bar's own tab (it was here as well until 25 Sept 2026).

  { type = "heading", label = "Editing" },
  { type = "action", label = "Edit bars", width = 200,
    labelFor = function()
      local m = ns.GetModule("ActionBars")
      return m.IsEditing() and "Editing: drop spells in" or "Edit bars"
    end,
    onClick = function() ns.GetModule("ActionBars").ToggleEditing() end },
  { type = "checkbox", key = "shiftDrag", label = "Shift + drag moves spells, even while the bars are locked",
    desc = "Hold Shift and drag a spell off a button, then drop it on another. Without Shift nothing moves.",
    apply = function() ns.GetModule("ActionBars"):Refresh() end },
  { type = "note", label = "Drop spells onto the bars while editing. Keybinds are the Keybinds tab above." },

  { type = "heading", label = "Bars" },
  { type = "checkbox", key = "hideBlizzardBars", label = "Hide Blizzard's action bars", reload = true },
  { type = "checkbox", key = "showPetBar", label = "...but keep Blizzard's pet bar", reload = true,
    desc = "Hunter and warlock pet buttons. It shows only when you have a pet; move it with Edit Mode (Esc > Edit Mode)." },
  { type = "checkbox", key = "showStanceBar", label = "...and Blizzard's stance / form bar", reload = true,
    desc = "Stances, forms, stealth. Off, they're still on your keys and in your spellbook." },
  -- Blizzard's micro menu, bag bar and XP bar: their switches live on the
  -- Micro Bar, Bags and XP Bar pages (25 Sept 2026) - still these settings.
  { type = "checkbox", key = "showEmptyButtons", label = "Show empty button outlines" },
  { type = "note", label = "Bar 1 follows stances and stealth on its own. Drag bars with /fui move. Blizzard's micro menu, bag bar and XP bar: their own pages." },
}

-- One tab per bar, under the settings above.
do
  local BAR_TABS = {
    { key = "bar1", label = "Main bar" }, { key = "bar2", label = "Bar 2" },
    { key = "bar3", label = "Bar 3" }, { key = "bar4", label = "Bar 4" },
    { key = "bar5", label = "Bar 5" }, { key = "bar6", label = "Bar 6" },
    { key = "bar7", label = "Bar 7" }, { key = "bar8", label = "Bar 8" },
  }
  for _, bar in ipairs(BAR_TABS) do
    local key = bar.key
    local store = function() return BarStore(key) end
    local list = module.options
    list[#list + 1] = { type = "heading", tab = key, tabLabel = bar.label, label = bar.label,
      subtitle = "This bar's own layout. Anything left alone follows the settings above." }
    list[#list + 1] = { type = "stepper", tab = key, key = "buttons", label = "Buttons on this bar",
      min = 1, max = 12, step = 1, store = store }
    list[#list + 1] = { type = "stepper", tab = key, key = "perRow", label = "Buttons per row",
      min = 1, max = 12, step = 1, store = store }
    list[#list + 1] = { type = "checkbox", tab = key, key = key, label = "Vertical (one button per row)",
      store = VerticalStore }
    list[#list + 1] = { type = "stepper", tab = key, key = "size", label = "Button size",
      min = 18, max = 54, step = 2, store = store }
    list[#list + 1] = { type = "stepper", tab = key, key = "spacing", label = "Spacing",
      min = 0, max = 12, step = 1, store = store }
    list[#list + 1] = { type = "action", tab = key, label = "Follow the settings above", width = 200,
      onClick = function() module.ResetBarOpts(key) end }
  end
end

local bars = {}
local hiddenParent
-- The button the mouse is over right now. The game tells us plainly through
-- each button's OnEnter/OnLeave (set in SkinButton), which is reliable on this
-- client where IsMouseOver() can hand back a value we're not allowed to test.
-- Keybind mode reads this to know which button the overlay is over.
local hoveredButton
-- The button you CLICKED in keybind mode. The next key (or mouse button) binds
-- to it. Only this one lights up -- no confusing trail as the mouse moves.
local selectedButton
-- Declared up here (not with the rest of the keybind code below) so the
-- button hover hooks in SkinButton can see it: nil, "drag", or "keys".
local mode = nil
-- Forward declaration: SkinButton's OnEnter (above the keybind code) moves the
-- click-catching overlay onto the hovered button, but the overlay and its
-- follower are defined further down, once Bind exists.
local FollowBindOverlay

local function Settings()
  return ns.db.modules.ActionBars
end

---------------------------------------------------------------------------
-- Button look
---------------------------------------------------------------------------
--
-- Blizzard's button is a small icon sitting inside a large piece of slot art:
-- the icon is inset, the art overhangs the button on every side, and the
-- game re-applies it whenever the slot changes. So the art is cleared, the
-- re-apply is hooked to clear it again, and the icon is stretched over the
-- whole block with its own baked-in border cropped off.
--
-- Element names differ between game versions (button.icon on some clients,
-- $parentIcon on others). Both are tried, and anything missing is skipped
-- rather than raising - /fui bars reports what was found.

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- How much of an icon is cropped. Icon zoom (sprutorgel on CurseForge, 28 Sept 2026: "zoomed more like in
-- bartender, so almost no border is present"): how much of each edge of the
-- spell's picture is cropped away, in percent. 8 cuts the icon's own frame
-- off, as it always has; more zooms in on the picture itself.
local function IconCrop()
  local s = ns.db and ns.db.modules and ns.db.modules.ActionBars
  local pct = tonumber(s and s.iconZoom) or 8
  return math.max(0, math.min(30, pct)) / 100
end

-- Art that belongs to the shell rather than the spell.
local SHELL = { "FloatingBG", "Border", "NewActionTexture", "SpellHighlightTexture", "IconMask" }

local function Element(button, key)
  local direct = rawget(button, key)
  if type(direct) == "table" then
    return direct
  end
  local name = button.GetName and button:GetName()
  if name and _G[name .. key] then
    return _G[name .. key]
  end
end
module.Element = Element

-- Our buttons are made by addon code, so Blizzard's own cooldown update runs
-- on them tainted. In combat the cooldown's start and duration come through
-- as secret numbers and SetCooldown refuses them -- "Secret values are only
-- allowed during untainted execution" -- dozens of times a second. Guard the
-- call at its source: out of combat it works exactly as before; in combat
-- the spiral simply doesn't draw instead of erroring. The full cure is to
-- not own the buttons at all (adopt Blizzard's), a larger change; this stops
-- the flood. The flag is kept off the frame, in a side table.
local guardedCooldowns = {}
local function GuardCooldown(cooldown)
  if not cooldown or guardedCooldowns[cooldown] or type(cooldown.SetCooldown) ~= "function" then
    return false
  end
  guardedCooldowns[cooldown] = true
  local real = cooldown.SetCooldown
  cooldown.SetCooldown = function(self, ...)
    return pcall(real, self, ...)
  end
  return true
end
module.GuardCooldown = GuardCooldown

-- A button has more than one cooldown frame, and not from the start.
--
-- The swipe is `cooldown`, made with the button. The thin ring for a spell
-- with charges is `chargeCooldown`, which Blizzard makes the first time it
-- needs one -- so guarding at skin time catches the first and misses the
-- second, and the second is the one that got through:
--
--   ActionButton.lua:881: bad argument #1 to 'SetCooldown' ... Secret values
--   are only allowed during untainted execution
--
-- So every known cooldown field is guarded, and because the late one appears
-- whenever it likes, this is cheap to call again and again: a frame already
-- wrapped is skipped by the side table.
--
-- And a third: `lossOfControlCooldown`, the spiral a button shows while you
-- are stunned, feared or silenced. Blizzard sets it FIRST in
-- ActionButton_ApplyCooldown (ActionButton.lua:897), so it only fires when
-- something crowd-controls you in combat -- which is why it went unnoticed
-- until a player got stunned.
local COOLDOWN_FIELDS = { "cooldown", "Cooldown", "chargeCooldown", "ChargeCooldown",
  "lossOfControlCooldown", "LossOfControlCooldown" }

-- Blizzard's button code writes the "pressAndHoldAction" attribute every
-- time the slot updates. On a button the game trusts that's fine in a fight;
-- on ours (made by an addon), and on Blizzard's own once we have wrapped its
-- cooldowns below, the game blocks it and blames ForeverUI ("tried to call
-- the protected function ForeverUIbar2Button8:SetAttribute()" and then
-- "MultiBarBottomLeftButton11:SetAttribute()", owner's first dungeon, 25
-- Sept 2026). The attribute only matters for empowered spells, so in combat
-- it waits for the end of the fight.
local function DeferPressAndHold(button)
  if type(button) ~= "table" or rawget(button, "fuiPressHoldDeferred") then return end
  local pressAndHold = button.UpdatePressAndHoldAction
  if type(pressAndHold) ~= "function" then return end
  button.fuiPressHoldDeferred = true
  button.UpdatePressAndHoldAction = function(self)
    if InCombatLockdown() then
      if not self.fuiPressHoldPending then
        self.fuiPressHoldPending = true
        ns.WhenOutOfCombat(function()
          self.fuiPressHoldPending = nil
          pcall(pressAndHold, self)
        end)
      end
      return
    end
    return pressAndHold(self)
  end
end
module.DeferPressAndHold = DeferPressAndHold

-- The controller's own action buttons (Blizzard_GamepadActionBars) are never
-- touched: wrapping their cooldown and press-and-hold code made every page or
-- stance change run them tainted, and in combat the game blocked the
-- controller's buttons as ForeverUI's (CurseForge, 28 Sept 2026: "it crashes
-- when i try to play with controller").
local function IsGamepadButton(button)
  if type(button) ~= "table" then return false end
  if rawget(button, "UpdateWithStorageId") ~= nil or rawget(button, "pageUnitSlotID") ~= nil then return true end
  local name = button.GetName and button:GetName()
  if type(name) == "string" and name:find("^Gamepad") then return true end
  local parent = button.GetParent and button:GetParent()
  for _ = 1, 4 do
    if not parent then break end
    if parent == rawget(_G, "GamepadMainActionBarFrame") then return true end
    local pname = parent.GetName and parent:GetName()
    if type(pname) == "string" and pname:find("^Gamepad") then return true end
    parent = parent.GetParent and parent:GetParent()
  end
  return false
end
module.IsGamepadButton = IsGamepadButton

-- ...but only while the controller is in charge. On keyboard and mouse the
-- controller's buttons still exist, hidden, and still get every event: from
-- the same loop as ours and Blizzard's (ActionBarButtonEventsFrame:OnEvent,
-- ActionButton.lua:230). Once that loop has run one of our wrapped buttons it
-- stays tainted, so the hidden pad buttons after it set their cooldowns
-- tainted too, and in combat that is "bad argument #1 to 'SetCooldown' ...
-- Secret values are only allowed during untainted execution" from
-- Blizzard_GamepadActionBars every time you cast at an enemy (sprutorgel on
-- CurseForge, 29 Sept 2026, keyboard player, after 0.4.43 stopped guarding
-- them). Nobody presses them on keyboard, so guarding them there is free.
-- ...and better still, asleep (Altiokis on CurseForge, 30 Sept 2026, on
-- keyboard and mouse: "ActionBarButton.lua:981: attempt to perform boolean
-- test on a secret boolean value (execution tainted by 'ForeverUI')", from
-- the controller's class-spell flyout reading its spells while guarded).
-- With neither the game nor ForeverUI in controller mode those buttons are
-- hidden and never pressed, so none of their code needs to run at all: their
-- own events are switched off and they are taken out of the game's shared
-- button lists. Nothing of ours touches them after that, and nothing of
-- theirs runs to trip over a secret. A switch to the controller asks for a
-- reload (Core/Controller.lua), which brings them back as they were.
local sleepingPads = {}
module.sleepingPads = sleepingPads

local function PadsCanSleep()
  if ns.ControllerActive and ns.ControllerActive() then return false end
  if ns.GamepadUIActive and ns.GamepadUIActive() then return false end
  return true
end
module.PadsCanSleep = PadsCanSleep

-- The keyed lists (frames[button] = button, actions[slot][button] = button):
-- a key set to nil leaves nothing of ours behind for the game to read.
local function DropFromKeyedLists(button)
  for _, name in ipairs({ "ActionBarActionEventsFrame", "ActionBarButtonUpdateFrame" }) do
    local registry = rawget(_G, name)
    if type(registry) == "table" and type(registry.frames) == "table" and registry.frames[button] then
      registry.frames[button] = nil
    end
  end
  -- Directly, not through UnregisterFrame: that also switches the range
  -- check off for the slot, which our own buttons on it still want.
  for _, name in ipairs({ "ActionBarButtonRangeCheckFrame", "ActionBarButtonUsableWatcherFrame" }) do
    local registry = rawget(_G, name)
    if type(registry) == "table" and type(registry.actions) == "table" then
      for _, list in pairs(registry.actions) do
        if type(list) == "table" and list[button] then list[button] = nil end
      end
    end
  end
end

local function PutToSleep(button)
  if sleepingPads[button] then return true end
  sleepingPads[button] = true
  if button.UnregisterAllEvents then pcall(button.UnregisterAllEvents, button) end
  DropFromKeyedLists(button)
  return true
end

-- The ordered list (ActionBarButtonEventsFrame.frames, filled by tinsert):
-- taking an entry out shifts every later one, so it is only done when all
-- the later ones are sleeping pads or our own buttons. Blizzard loads the
-- controller bars after ForeverUI builds its bars, so they are the tail.
--
-- Local patch (4 Oct 2026): our own buttons are dropped too, and from then on
-- driven by Modules/ActionBars/OwnButtons.lua; see the note there. Everything
-- from the first pad or button of ours to the end goes, so no Blizzard entry
-- is ever shifted.
function module.DropSleepingPadsFromLoop()
  local registry = rawget(_G, "ActionBarButtonEventsFrame")
  local list = type(registry) == "table" and registry.frames
  if type(list) ~= "table" then return 0 end
  local ownLoop = module.OwnLoop
  local function Ours(b)
    return ownLoop ~= nil and type(b) == "table" and rawget(b, "fuiTemplate") ~= nil
  end
  local first
  for i = 1, #list do
    if sleepingPads[list[i]] or Ours(list[i]) then first = i; break end
  end
  if not first then return 0 end
  for i = first, #list do
    local b = list[i]
    if not (sleepingPads[b] or (type(b) == "table" and rawget(b, "fuiTemplate"))) then
      return 0   -- one of Blizzard's own comes later: leave the list alone
    end
  end
  local dropped = 0
  for i = #list, first, -1 do
    local b = list[i]
    if sleepingPads[b] or Ours(b) then
      table.remove(list, i)
      if Ours(b) then ownLoop.AdoptFromOrdered(b) end
      dropped = dropped + 1
    end
  end
  return dropped
end

-- The controller's class-spell flyout (druid forms, paladin auras, warrior
-- stances: GamepadMainActionBarFrame.PageUnit.LeftClassAction and
-- RightClassAction) is set up by Blizzard once you log in
-- (ClassSpellFlyout.lua, EventUtil.ContinueOnPlayerLogin), and that set-up
-- switches its events back on -- after our first pass put it to sleep. Awake
-- on keyboard and mouse, it re-read its spells from inside the game's shared
-- button loop, after our buttons, and its own aura event then ran tainted:
-- "ActionBarButton.lua:842: bad argument #1 to 'SetChecked' ... Secret values
-- are only allowed during untainted execution" (owner, 2 Oct 2026, a druid
-- shifting form). So once the world is entered, the controller page's
-- buttons are put back to sleep, even ones that were asleep already.
function module.ResleepControllerPage()
  if not PadsCanSleep() then return 0 end
  local main = rawget(_G, "GamepadMainActionBarFrame")
  local page = type(main) == "table" and rawget(main, "PageUnit") or nil
  if type(page) ~= "table" then return 0 end
  local seen, count = {}, 0
  local function Sleep(button)
    if type(button) ~= "table" or seen[button] or not button.UnregisterAllEvents then return end
    seen[button] = true
    sleepingPads[button] = true
    pcall(button.UnregisterAllEvents, button)
    DropFromKeyedLists(button)
    count = count + 1
  end
  Sleep(rawget(page, "LeftClassAction"))
  Sleep(rawget(page, "RightClassAction"))
  if page.GetChildren then
    for _, child in ipairs({ page:GetChildren() }) do
      local okType, isButton = pcall(function()
        return child.IsObjectType and (child:IsObjectType("Button") or child:IsObjectType("CheckButton"))
      end)
      if okType and isButton then Sleep(child) end
    end
  end
  module.DropSleepingPadsFromLoop()
  return count
end

local padWatcher = CreateFrame("Frame")
pcall(padWatcher.RegisterEvent, padWatcher, "PLAYER_ENTERING_WORLD")
padWatcher:SetScript("OnEvent", function()
  if ns.ModuleRunning and ns.ModuleRunning("ActionBars") then module.ResleepControllerPage() end
end)
module.padWatcher = padWatcher

local function LeaveAlone(button)
  if not IsGamepadButton(button) then return false end
  if PadsCanSleep() then return PutToSleep(button) end
  -- The game is in controller mode: never touch them. Keyboard forced on
  -- while the game's controller UI runs: guard them as before.
  return ns.ControllerActive and ns.ControllerActive() and true or false
end
module.LeaveGamepadButtonAlone = LeaveAlone

local function GuardButtonCooldowns(button)
  if not button or LeaveAlone(button) then
    return 0
  end
  -- Local patch (4 Oct 2026): our own buttons only. With them out of the
  -- game's shared loops (OwnButtons.lua), Blizzard's buttons no longer run
  -- after ours, and a wrapper written into one of theirs would itself taint
  -- every Blizzard read of it.
  if rawget(button, "fuiTemplate") == nil then
    return 0
  end
  if module.OwnLoop then module.OwnLoop.GuardPing(button) end
  DeferPressAndHold(button)
  local guarded = 0
  for _, field in ipairs(COOLDOWN_FIELDS) do
    if GuardCooldown(rawget(button, field)) then
      guarded = guarded + 1
    end
  end
  return guarded
end
module.GuardButtonCooldowns = GuardButtonCooldowns

-- Every action button the game makes, whether or not we have skinned it.
--
-- Guarding only what we skin assumes we know which buttons we tainted, and we
-- do not: taking the mouse off a hidden bar's children touches Blizzard's own
-- buttons, and so does anything else that reaches into a bar we are hiding.
-- The cost of guarding one we never touched is a single table lookup that
-- finds it already wrapped, so the whole set is swept instead of guessed at.
local BLIZZARD_BUTTONS = {
  { "ActionButton", 12 },
  { "MultiBarBottomLeftButton", 12 },
  { "MultiBarBottomRightButton", 12 },
  { "MultiBarLeftButton", 12 },
  { "MultiBarRightButton", 12 },
  { "MultiBar5Button", 12 },
  { "MultiBar6Button", 12 },
  { "MultiBar7Button", 12 },
  { "BonusActionButton", 12 },
  { "OverrideActionBarButton", 6 },
}
-- Local patch (4 Oct 2026): the stance, shapeshift, pet and possess buttons
-- are no longer on this list. They never run in the shared button loops this
-- guard exists for (each bar drives its own), so wrapping them only wrote our
-- Lua into frames Edit Mode reads first on the way in, and tainted that pass.
-- See the note above Deafen in Core/Skin.lua.

-- Buttons the list above does not name.
--
-- The gamepad bars (Blizzard_GamepadActionBars) are action buttons too, with
-- names of their own, and one of them was what fired the stun-spiral error
-- after the list was fixed. Rather than chase names, ask the game: every
-- action button registers itself with one of two event frames, and those
-- keep the list (ActionButton.lua:459 and :570, forever branch). Sweep that,
-- and hook RegisterFrame so a button made later is guarded as it appears.
--
-- Only while our bars stand in for Blizzard's: a wrapped cooldown is called
-- through addon code, which is what makes the error go quiet -- and also
-- what stops a spiral drawing in combat on a button nothing else had
-- touched. On bars we hide, that costs nothing.
-- The buttons of a Blizzard bar we leave standing are left alone too: the
-- guard is for bars we hide, and a wrapped cooldown on a bar in use can stop
-- its spiral drawing in a fight.
local KEPT_BUTTONS = { PetActionButton = "pet", StanceButton = "stance", ShapeshiftButton = "stance" }
local function ButtonKept(prefix)
  local kind = KEPT_BUTTONS[prefix]
  if kind == "pet" then return Settings().showPetBar ~= false end
  if kind == "stance" then return Settings().showStanceBar == true end
  return false
end

local REGISTRIES = { "ActionBarButtonEventsFrame", "ActionBarActionEventsFrame" }
local hookedRegistries = {}

local function GuardRegisteredButtons()
  local guarded = 0
  for _, name in ipairs(REGISTRIES) do
    local registry = rawget(_G, name)
    if type(registry) == "table" then
      if type(registry.frames) == "table" then
        for _, button in pairs(registry.frames) do
          local buttonName = type(button) == "table" and button.GetName and button:GetName() or ""
          local prefix = buttonName:match("^(%a+Button)%d+$")
          if not ButtonKept(prefix) then
            guarded = guarded + GuardButtonCooldowns(button)
          end
        end
      end
      if not hookedRegistries[registry] and hooksecurefunc and type(registry.RegisterFrame) == "function" then
        hookedRegistries[registry] = true
        hooksecurefunc(registry, "RegisterFrame", function(_, button)
          GuardButtonCooldowns(button)
          if sleepingPads[button] then module.DropSleepingPadsFromLoop() end
        end)
      end
    end
  end
  module.DropSleepingPadsFromLoop()
  if module.OwnLoop then module.OwnLoop.AdoptKeyed() end
  return guarded
end
module.GuardRegisteredButtons = GuardRegisteredButtons

local function GuardBlizzardCooldowns()
  local guarded = 0
  for _, entry in ipairs(BLIZZARD_BUTTONS) do
    local prefix, count = entry[1], entry[2]
    if not ButtonKept(prefix) then
      for i = 1, count do
        guarded = guarded + GuardButtonCooldowns(rawget(_G, prefix .. i))
      end
    end
  end
  return guarded + GuardRegisteredButtons()
end
module.GuardBlizzardCooldowns = GuardBlizzardCooldowns

local function ClearShellArt(button)
  local normal = button.GetNormalTexture and button:GetNormalTexture()
  if normal then
    normal:SetTexture(nil)
    normal:SetAlpha(0)
  end
  for _, key in ipairs(SHELL) do
    local texture = Element(button, key)
    if texture and texture.SetAlpha then
      texture:SetAlpha(0)
    end
  end
end

---------------------------------------------------------------------------
-- Range, flash and border colour (sprutorgel on CurseForge, 26 Sept 2026:
-- "the skill turns full red when out of range (not only the keybind)", "a
-- weird red square flashing inside the button" with a wand, and "change
-- color on my action bars").
---------------------------------------------------------------------------

local skinnedButtons = {}
local RANGE_RED = { 0.95, 0.25, 0.25 }

local function AbSettings()
  return ns.db and ns.db.modules and ns.db.modules.ActionBars or {}
end

-- The icon's normal colour, as Blizzard's UpdateUsable paints it: usable,
-- not enough mana, or unusable. Ours, so the game's code isn't run from here.
local function PaintUsable(button)
  local icon = button.fuiIcon
  if not icon or not button.action or not (C_ActionBar and C_ActionBar.IsUsableAction) then return end
  local ok, usable, noMana = pcall(C_ActionBar.IsUsableAction, button.action)
  if not ok then return end
  local okTest, u, m = pcall(function() return usable and true or false, noMana and true or false end)
  if not okTest then return end
  if u then icon:SetVertexColor(1, 1, 1)
  elseif m then icon:SetVertexColor(0.5, 0.5, 1)
  else icon:SetVertexColor(0.4, 0.4, 0.4) end
end

-- Red when the spell is out of range. The game's answer is kept on the
-- button by the range hook: a plain true/false, or - when the game keeps it
-- secret - its own in-range value, which the game turns into a colour
-- (EvaluateColorFromBoolean) without it ever being read here.
local function PaintRange(button)
  local icon = button.fuiIcon
  if not icon or not icon.SetVertexColor or not AbSettings().rangeRed then return end
  if button.fuiOutOfRange == true then
    icon:SetVertexColor(RANGE_RED[1], RANGE_RED[2], RANGE_RED[3])
    return
  end
  if type(button.fuiInRangeSecret) ~= "nil" then
    local eval = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean
    if eval and CreateColor then
      pcall(function()
        local color = eval(button.fuiInRangeSecret, CreateColor(1, 1, 1, 1),
          CreateColor(RANGE_RED[1], RANGE_RED[2], RANGE_RED[3], 1))
        icon:SetVertexColor(color:GetRGBA())
      end)
    end
  end
end
module.PaintRange = PaintRange

-- The auto-attack / auto-shot flash: Blizzard blinks its Flash texture on and
-- off; alpha outlasts every Show and Hide it does, so this sticks.
local function PaintFlash(button)
  local flash = button.Flash
  if type(flash) ~= "table" then flash = Element(button, "Flash") end
  if type(flash) == "table" and flash.SetAlpha then
    flash:SetAlpha(AbSettings().attackFlash and 1 or 0)
  end
end

local function PaintBorder(button)
  local s = AbSettings()
  if not button.borderEdges then return end
  if s.ownButtonColor and type(s.buttonBorderColor) == "table" then
    ns.Skin.SetBorderColor(button, { s.buttonBorderColor[1], s.buttonBorderColor[2], s.buttonBorderColor[3], 1 })
  else
    ns.Skin.SetBorderColor(button, ns.Colors.ui.accent)
  end
end

function module.RepaintAllButtons()
  local crop = IconCrop()
  for button in pairs(skinnedButtons) do
    if button.fuiIcon then button.fuiIcon:SetTexCoord(crop, 1 - crop, crop, 1 - crop) end
    PaintFlash(button)
    PaintBorder(button)
    PaintUsable(button)
    PaintRange(button)
  end
end

-- One hook for every button: the game's range pass says in or out of range.
local rangeHooked = false
local function HookRange()
  if rangeHooked or not hooksecurefunc or type(_G.ActionButton_UpdateRangeIndicator) ~= "function" then return end
  rangeHooked = true
  hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
    if not skinnedButtons[self] then return end
    local wasRed = self.fuiOutOfRange == true or type(self.fuiInRangeSecret) ~= "nil"
    self.fuiOutOfRange, self.fuiInRangeSecret = nil, nil
    -- "Checks range and isn't in range" - asked in a guard: either can be secret.
    local okOut, out = pcall(function() return (checksRange and not inRange) and true or false end)
    if okOut then
      self.fuiOutOfRange = out
    else
      local okChecks, checks = pcall(function() return checksRange and true or false end)
      if okChecks and checks then self.fuiInRangeSecret = inRange end
    end
    if wasRed then PaintUsable(self) end   -- back to the game's colour first
    PaintRange(self)
  end)
end

-- Rounded corners (General > Appearance > Corners, "Round action buttons"):
-- the button's tile and border round, and what's drawn square inside it --
-- the spell icon, the hover / pressed / checked tints, the cooldown sweep,
-- the edit tint -- moves in just far enough that its corners stay inside
-- the curve. Square, they fill the block as before.
local function FitInside(button, r)
  local px = ns.Media.Pixel()
  local pad = px + ns.Skin.CornerClearance(r)
  local function Inset(region)
    if not (region and region.ClearAllPoints) then return end
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", button, "TOPLEFT", pad, -pad)
    region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -pad, pad)
  end
  Inset(button.fuiIcon)
  local tints = r > 0 and pad or 0
  for _, get in ipairs({ "GetHighlightTexture", "GetPushedTexture", "GetCheckedTexture" }) do
    local region = button[get] and button[get](button)
    if region and region.ClearAllPoints then
      region:ClearAllPoints()
      region:SetPoint("TOPLEFT", button, "TOPLEFT", tints, -tints)
      region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -tints, tints)
    end
  end
  local cooldown = Element(button, "cooldown") or Element(button, "Cooldown")
  if cooldown and cooldown.ClearAllPoints then
    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", tints, -tints)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -tints, tints)
  end
  if button.fuiEdit then
    button.fuiEdit:ClearAllPoints()
    button.fuiEdit:SetPoint("TOPLEFT", button, "TOPLEFT", tints, -tints)
    button.fuiEdit:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -tints, tints)
  end
end
module.FitInside = FitInside

-- Blizzard's button clips its icon with a mask (IconMask,
-- "UI-HUD-ActionBar-IconFrame-Mask"): a rounded square the size of the
-- template's own icon, centred on it. Hiding the mask doesn't lift it, so
-- the icon we stretch over the block was still cut back to that shape, and
-- with Spacing at 0 the buttons stood apart with a wide dark gap where
-- Bartender's touch (sprutorgel on CurseForge, 29 Sept 2026). The mask is
-- taken off the icon instead.
local function UnmaskIcon(button, icon)
  if not (icon and icon.RemoveMaskTexture) then return 0 end
  local removed = 0
  local named = Element(button, "IconMask")
  if named and pcall(icon.RemoveMaskTexture, icon, named) then removed = removed + 1 end
  if icon.GetNumMaskTextures and icon.GetMaskTexture then
    local ok, count = pcall(icon.GetNumMaskTextures, icon)
    for i = (ok and tonumber(count) or 0), 1, -1 do
      local mask = icon:GetMaskTexture(i)
      if mask and pcall(icon.RemoveMaskTexture, icon, mask) then removed = removed + 1 end
    end
  end
  return removed
end
module.UnmaskIcon = UnmaskIcon

local function SkinButton(button)
  if button.fuiSkinned then
    return button
  end
  button.fuiSkinned = true
  skinnedButtons[button] = true
  HookRange()
  -- The game repaints the icon when mana or usability changes: red again
  -- after it, if the spell is still out of range.
  if hooksecurefunc and type(button.UpdateUsable) == "function" then
    hooksecurefunc(button, "UpdateUsable", function(self) PaintRange(self) end)
  end

  local px = ns.Media.Pixel()
  ns.Skin.Panel(button, { color = { 0, 0, 0, 1 }, group = "roundButtons", onShape = FitInside })

  local icon = Element(button, "icon") or Element(button, "Icon")
  if icon then
    -- Fill the block, minus the one-pixel border, and crop the icon's own.
    local crop = IconCrop()
    icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", px, -px)
    icon:SetPoint("BOTTOMRIGHT", -px, px)
    UnmaskIcon(button, icon)
    button.fuiIcon = icon
  end

  ClearShellArt(button)
  -- The game puts the slot art back whenever the action changes.
  if hooksecurefunc and button.SetNormalTexture then
    hooksecurefunc(button, "SetNormalTexture", function(self)
      local normal = self.GetNormalTexture and self:GetNormalTexture()
      if normal then
        normal:SetTexture(nil)
        normal:SetAlpha(0)
      end
    end)
  end

  local cooldown = Element(button, "cooldown") or Element(button, "Cooldown")
  if cooldown and cooldown.SetAllPoints then
    cooldown:ClearAllPoints()
    cooldown:SetAllPoints(button)
  end
  GuardButtonCooldowns(button)

  -- Flat states instead of Blizzard's glow textures.
  if button.SetHighlightTexture then
    button:SetHighlightTexture(WHITE)
    local highlight = button:GetHighlightTexture()
    if highlight then
      highlight:SetColorTexture(1, 1, 1, 0.18)
      highlight:SetAllPoints(button)
    end
  end
  if button.SetPushedTexture then
    button:SetPushedTexture(WHITE)
    local pushed = button:GetPushedTexture()
    if pushed then
      pushed:SetColorTexture(0, 0, 0, 0.35)
      pushed:SetAllPoints(button)
    end
  end
  if button.SetCheckedTexture then
    button:SetCheckedTexture(WHITE)
    local checked = button:GetCheckedTexture()
    if checked then
      local r, g, b = unpack(ns.Colors.ui.accent)
      checked:SetColorTexture(r, g, b, 0.35)
      checked:SetAllPoints(button)
    end
  end

  -- Keybind and count sit in the corners, out of the artwork's way.
  local hotkey = button.HotKey or Element(button, "HotKey")
  if hotkey and hotkey.SetPoint then
    ns.Media.SetFont(hotkey, "aura")
    hotkey:ClearAllPoints()
    hotkey:SetPoint("TOPRIGHT", -2, -2)
    -- Blizzard's own hotkey pass writes the long name ("Mouse Button 4",
    -- "Num Pad *") into the corner and it runs off the button. Whatever
    -- writes there, ours -- "M4", "N*" -- goes back over it.
    if hooksecurefunc and hotkey.SetText and not button.fuiHotkeyHooked then
      button.fuiHotkeyHooked = true
      local painting = false
      hooksecurefunc(hotkey, "SetText", function(self, text)
        if painting then return end
        local key = module.ShownBindingFor and module.ShownBindingFor(button)
        if key and text ~= "" and text ~= module.Abbreviate(key) then
          painting = true
          self:SetText(module.Abbreviate(key))
          painting = false
        end
      end)
    end
  end
  local count = Element(button, "Count")
  if count and count.SetPoint then
    ns.Media.SetFont(count, "aura")
    count:ClearAllPoints()
    count:SetPoint("BOTTOMRIGHT", -2, 2)
  end

  -- Shown only in edit mode, so it's obvious when a drag will stick.
  local editTint = button:CreateTexture(nil, "OVERLAY")
  editTint:SetAllPoints(button)
  local r, g, b = unpack(ns.Colors.ui.accent)
  editTint:SetColorTexture(r, g, b, 0.22)
  editTint:Hide()
  button.fuiEdit = editTint

  -- Track the hovered button for keybind mode. HookScript leaves the game's
  -- own OnEnter (the tooltip) intact and just adds ours after it.
  if button.HookScript then
    button:HookScript("OnEnter", function(self)
      hoveredButton = self
      -- Cover it with the (invisible) overlay that catches clicks, so a click
      -- picks the button instead of casting the spell under it. No highlight
      -- on hover -- only the button you actually click lights up.
      if mode == "keys" and FollowBindOverlay then
        FollowBindOverlay(self)
      end
    end)
    button:HookScript("OnLeave", function(self)
      if hoveredButton == self then
        hoveredButton = nil
      end
    end)
    -- Tell the frames what you just cast. In a fight the game hides the spell
    -- of a cast from addons, so a HoT pressed here would never show on the
    -- healer frames; the button's own action is not hidden.
    button:HookScript("PreClick", function(self)
      local frames = ns.Frames
      if not (frames and frames.NoteBarCast and GetActionInfo) then
        return
      end
      pcall(function()
        local slot = self:GetAttribute("action") or self.action
        local kind, id = GetActionInfo(tonumber(slot) or 0)
        if kind == "spell" and id then
          local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
            or (GetSpellInfo and GetSpellInfo(id))
          frames.NoteBarCast(name)
        end
      end)
    end)
  end

  PaintFlash(button)
  PaintBorder(button)
  -- Now the icon and tints exist, fit them to the corners.
  ns.Skin.ShapePanel(button)
  return button
end
module.SkinButton = SkinButton
-- General's border colour repaints every accent border, ours included: put
-- an own button colour back after it.
if ns.Skin.AddAccentListener then
  ns.Skin.AddAccentListener(function() module.RepaintAllButtons() end)
end

---------------------------------------------------------------------------
-- Keybinds
---------------------------------------------------------------------------
--
-- Blizzard's template shows a range dot on every unbound button, which reads
-- as a stray glyph in the corner of every empty slot. Instead the keybind
-- text says what the button is actually bound to, and says nothing when it
-- isn't bound to anything.

local MODIFIERS = {
  LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
  LALT = true, RALT = true, UNKNOWN = true,
}

local SHORT = {
  ["SHIFT%-"] = "S", ["CTRL%-"] = "C", ["ALT%-"] = "A",
  ["BUTTON"] = "M", ["MOUSEWHEELUP"] = "MU", ["MOUSEWHEELDOWN"] = "MD",
  ["NUMPADMULTIPLY"] = "N*", ["NUMPADDIVIDE"] = "N/", ["NUMPADPLUS"] = "N+",
  ["NUMPADMINUS"] = "N-", ["NUMPADDECIMAL"] = "N.",
  ["NUMPAD"] = "N", ["PAGEUP"] = "PU", ["PAGEDOWN"] = "PD",
  ["SPACE"] = "Sp", ["INSERT"] = "Ins", ["HOME"] = "Hm", ["DELETE"] = "Del",
  -- Controller buttons (Blizzard's GamepadConstants), as a pad is labelled.
  ["PAD1$"] = "A", ["PAD2$"] = "B", ["PAD3$"] = "X", ["PAD4$"] = "Y", ["PAD5$"] = "P5", ["PAD6$"] = "P6",
  ["PADLSHOULDER$"] = "LB", ["PADRSHOULDER$"] = "RB", ["PADLTRIGGER$"] = "LT", ["PADRTRIGGER$"] = "RT",
  ["PADDUP$"] = "DU", ["PADDDOWN$"] = "DD", ["PADDLEFT$"] = "DL", ["PADDRIGHT$"] = "DR",
  ["PADLSTICK$"] = "L3", ["PADRSTICK$"] = "R3", ["PADBACK$"] = "Bk", ["PADFORWARD$"] = "St",
  ["PADSOCIAL$"] = "Sc", ["PADSYSTEM$"] = "Sy",
}

-- "SHIFT-BUTTON4" reads as "SM4" in the corner of a 30px button.
local SHORT_ORDER = {}
for pattern in pairs(SHORT) do SHORT_ORDER[#SHORT_ORDER + 1] = pattern end
table.sort(SHORT_ORDER, function(a, b) return #a > #b end) -- NUMPADMULTIPLY before NUMPAD

local function Abbreviate(key)
  local short = key or ""
  for _, pattern in ipairs(SHORT_ORDER) do
    short = short:gsub(pattern, SHORT[pattern])
  end
  return short
end
module.Abbreviate = Abbreviate

-- The binding that clicks this button, if there is one.
local function BindingFor(button)
  local name = button.GetName and button:GetName()
  if not name or not GetBindingKey then
    return nil
  end
  local key = GetBindingKey("CLICK " .. name .. ":LeftButton")
  return key ~= "" and key or nil
end
module.BindingFor = BindingFor

-- The game's own binding for this button's slot ("MULTIACTIONBAR1BUTTON3").
-- Without it, every key set in Blizzard's Key Bindings window left our
-- buttons blank although the key pressed them.
local function GameBindingFor(button)
  local command = button.fuiGameBinding
  if not command or not GetBindingKey then
    return nil
  end
  local key = GetBindingKey(command)
  return key ~= "" and key or nil
end
module.GameBindingFor = GameBindingFor

-- What the corner shows: our own bind first, else the game's.
local function ShownBindingFor(button)
  return BindingFor(button) or GameBindingFor(button)
end
module.ShownBindingFor = ShownBindingFor

local function UpdateHotkey(button)
  local hotkey = button.HotKey
  if not hotkey or not hotkey.SetText then
    return
  end
  local key = ShownBindingFor(button)
  hotkey:SetText(key and Abbreviate(key) or "")
  hotkey:SetShown(key ~= nil and Settings().showKeybinds ~= false)
end
module.UpdateHotkey = UpdateHotkey

local function UpdateAllHotkeys()
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons) do
      UpdateHotkey(button)
    end
  end
end
module.UpdateAllHotkeys = UpdateAllHotkeys

-- Where keybinds are saved: this character's own set, or the account-wide one
-- every character shares. The game keeps two "binding sets" for exactly this;
-- 1 is account-wide, 2 is per-character (the ACCOUNT_BINDINGS/CHARACTER_BINDINGS
-- constants, with numbers as a fallback for a client that lacks them).
local ACCOUNT_SET = _G.ACCOUNT_BINDINGS or 1
local CHARACTER_SET = _G.CHARACTER_BINDINGS or 2

local function TargetSet()
  local scope = Settings().bindingScope
  if scope == "character" then
    return CHARACTER_SET
  elseif scope == "account" then
    return ACCOUNT_SET
  end
  return (GetCurrentBindingSet and GetCurrentBindingSet()) or CHARACTER_SET
end
module.TargetSet = TargetSet

-- Commit the current bindings to the chosen set.
local function SaveTo()
  if SaveBindings then
    pcall(SaveBindings, TargetSet())
  end
end
module.SaveKeybinds = SaveTo

-- OUR OWN COPY OF THE BINDS. The game keeps its binding sets in a file of
-- its own that this client has been seen not to read back, so every bind
-- made on the bars is also written into ForeverUI's saved variables -- one
-- set per character, plus a Shared one -- and put back on the bars at
-- login. That is what "Save keybinds for: This character / All characters"
-- chooses between, and it is why the page names the set it writes into.
local SHARED_SET = "Shared"

local function KeybindStore()
  ForeverUIDB.keybinds = ForeverUIDB.keybinds or { sets = {} }
  ForeverUIDB.keybinds.sets = ForeverUIDB.keybinds.sets or {}
  return ForeverUIDB.keybinds
end

-- The set the current scope writes into: the character's own, or Shared.
local function SetName()
  if (Settings().bindingScope or "character") == "account" then
    return SHARED_SET
  end
  return ns.CharacterKey() or SHARED_SET
end
module.KeybindSetName = SetName

local function CurrentSet()
  local store = KeybindStore()
  local name = SetName()
  store.sets[name] = store.sets[name] or {}
  return store.sets[name], name
end
module.CurrentKeybindSet = CurrentSet

-- A button's saved keys, always as a list. Older sets kept a single string
-- (which quietly lost the second key on a button bound to two), so both
-- shapes are read.
local function KeyList(entry)
  if type(entry) == "table" then return entry end
  if type(entry) == "string" then return { entry } end
  return {}
end
module.KeyList = KeyList

local function RecordBind(buttonName, key)
  local set = CurrentSet()
  -- One key clicks one button: drop it from wherever else it was.
  for other, bound in pairs(set) do
    if other ~= buttonName then
      local keys, kept = KeyList(bound), {}
      for _, k in ipairs(keys) do
        if k ~= key then kept[#kept + 1] = k end
      end
      set[other] = #kept > 0 and kept or nil
    end
  end
  local mine = KeyList(set[buttonName])
  for _, k in ipairs(mine) do
    if k == key then return end       -- already known
  end
  mine[#mine + 1] = key
  set[buttonName] = mine
end

local function RecordUnbind(buttonName)
  local set = CurrentSet()
  set[buttonName] = nil
end
-- Other modules' keys (the raid marker keys) go in the same store, so the
-- login restore puts them back too.
module.RecordBind, module.RecordUnbind = RecordBind, RecordUnbind

function module.CountKeybinds(name)
  local store = KeybindStore()
  local n = 0
  for _, entry in pairs(store.sets[name or SetName()] or {}) do
    n = n + #KeyList(entry)
  end
  return n
end

-- Put a saved set onto the bars: every recorded key clicks its button.
-- Runs at login (out of combat) and whenever the scope changes.
function module.ApplySavedKeybinds()
  if InCombatLockdown() or not SetBindingClick then
    return 0
  end
  local set = CurrentSet()
  local applied = 0
  for buttonName, entry in pairs(set) do
    if _G[buttonName] then
      for _, key in ipairs(KeyList(entry)) do
        pcall(SetBindingClick, key, buttonName, "LeftButton")
        applied = applied + 1
      end
    end
  end
  if applied > 0 then
    SaveTo()
  end
  return applied
end

-- What a set knows about itself: how many keys, when it was last written,
-- and whose it is. Kept beside the sets so the Keybinds page can show a set
-- it is not currently using.
local function MetaStore()
  local store = KeybindStore()
  store.meta = store.meta or {}
  return store.meta
end

function module.KeybindMeta(name)
  return MetaStore()[name]
end

function module.StampKeybindSet(name)
  name = name or SetName()
  -- `local a, b = UnitClass and UnitClass("player")` keeps only the first
  -- return, which is the localized name, not the token.
  local classFile
  if UnitClass then
    local _, token = UnitClass("player")
    classFile = token
  end
  MetaStore()[name] = {
    saved = time and time() or 0,
    count = module.CountKeybinds(name),
    class = classFile,
    level = UnitLevel and UnitLevel("player") or nil,
  }
  return MetaStore()[name]
end

-- Every set that exists, newest first, with what it knows about itself.
function module.KeybindSets()
  local store = KeybindStore()
  local list = {}
  for name, set in pairs(store.sets) do
    local count = 0
    for _, entry in pairs(set) do count = count + #KeyList(entry) end
    local meta = MetaStore()[name] or {}
    list[#list + 1] = {
      name = name,
      count = count,
      saved = meta.saved,
      class = meta.class,
      level = meta.level,
      active = name == SetName(),
    }
  end
  table.sort(list, function(a, b)
    if a.active ~= b.active then return a.active end
    return (a.saved or 0) > (b.saved or 0)
  end)
  return list
end

-- Write whatever is bound right now into a set of its own.
function module.SaveKeybindSet(name)
  name = name or SetName()
  local store = KeybindStore()
  store.sets[name] = ns.CopyTable(CurrentSet())
  module.StampKeybindSet(name)
  return module.CountKeybinds(name)
end

-- Put a saved set on the bars, and keep working in it.
function module.LoadKeybindSet(name)
  local store = KeybindStore()
  if not store.sets[name] then
    return false
  end
  module.ClearAllKeybinds()
  store.sets[SetName()] = ns.CopyTable(store.sets[name])
  local applied = module.ApplySavedKeybinds()
  UpdateAllHotkeys()
  return true, applied
end

function module.DeleteKeybindSet(name)
  local store = KeybindStore()
  if not store.sets[name] or name == SetName() then
    return false          -- the set in use is not deleted from under you
  end
  store.sets[name] = nil
  MetaStore()[name] = nil
  return true
end

-- Sets travel as TEXT, not as files: an addon cannot write to disk. The
-- format is one "button=key,key" per line, which is short enough to paste
-- into a whisper.
function module.ExportKeybinds(name)
  local store = KeybindStore()
  local set = store.sets[name or SetName()]
  if not set then
    return ""
  end
  local lines = { "ForeverUI keybinds v1" }
  local names = {}
  for button in pairs(set) do names[#names + 1] = button end
  table.sort(names)
  for _, button in ipairs(names) do
    lines[#lines + 1] = ("%s=%s"):format(button, table.concat(KeyList(set[button]), ","))
  end
  return table.concat(lines, "\n")
end

function module.ImportKeybinds(text)
  if type(text) ~= "string" or not text:find("ForeverUI keybinds", 1, true) then
    return false, "that does not look like a ForeverUI keybind set."
  end
  local set, count = {}, 0
  for line in text:gmatch("[^\r\n]+") do
    local button, keys = line:match("^(%S+)=(.+)$")
    if button and keys then
      local list = {}
      for key in keys:gmatch("[^,]+") do
        list[#list + 1] = key
        count = count + 1
      end
      set[button] = list
    end
  end
  if count == 0 then
    return false, "no keys in that text."
  end
  local store = KeybindStore()
  store.sets[SetName()] = set
  module.ClearAllKeybinds()
  store.sets[SetName()] = set        -- clearing empties it; put it back
  module.ApplySavedKeybinds()
  module.StampKeybindSet()
  UpdateAllHotkeys()
  return true, count
end

-- Copy one set over another (this character's to Shared, or back).
function module.CopyKeybindSet(from, to)
  local store = KeybindStore()
  local source = store.sets[from]
  if not source then
    return false
  end
  store.sets[to] = ns.CopyTable(source)
  return true
end

function module.GetBindingScope()
  return Settings().bindingScope or "character"
end

-- Switching scope makes that set the active one (so the binds you already
-- have for it show up) and saves into it from here on.
function module.SetBindingScope(scope)
  Settings().bindingScope = scope
  if LoadBindings then
    pcall(LoadBindings, TargetSet())
  end
  module.ApplySavedKeybinds()
  SaveTo()
  UpdateAllHotkeys()
  ns.RefreshOptions()
  return scope
end

-- Make the game's active set match the saved choice, so a bind saves where
-- the player expects even before they touch the scope control this session.
local function AlignBindingSet()
  local scope = Settings().bindingScope
  if not scope or not LoadBindings or not GetCurrentBindingSet then
    return
  end
  local ok, current = pcall(GetCurrentBindingSet)
  if ok and current ~= TargetSet() then
    pcall(LoadBindings, TargetSet())
  end
end
module.AlignBindingSet = AlignBindingSet

---------------------------------------------------------------------------
-- Locked in normal play; two edit modes to change that
---------------------------------------------------------------------------
--
--   drag  spells can be dragged on and off the bars
--   keys  hover a button and press a key to bind it
--
-- Neither survives a reload, and neither can be entered in combat. Normal
-- play is locked: nothing drags, nothing rebinds.
-- (mode itself is declared near the top so the hover hooks can see it.)

-- Picking a spell up off the spellbook and clicking it into a slot is the
-- ordinary way to arrange a bar, and the lock stops it: the game's
-- lockActionBars refuses to let anything be *placed*, not just picked up.
-- So while the cursor is actually carrying something, the bars accept it.
-- Nothing can be knocked off by accident, because an empty cursor is locked
-- again the moment the drop lands.
local CARRIABLE = {
  spell = true, item = true, macro = true, mount = true,
  companion = true, petaction = true, equipmentset = true, flyout = true,
}

local carrying = false
local ApplyMode -- defined below; the cursor watcher needs it

local function CursorIsCarrying()
  if not GetCursorInfo then
    return false
  end
  local kind = GetCursorInfo()
  return CARRIABLE[kind] == true
end
module.CursorIsCarrying = CursorIsCarrying

local MODE_COLORS = {
  drag = { 0.30, 0.76, 1.00, 0.22 },
  keys = { 1.00, 0.72, 0.20, 0.22 },
}

function module.GetMode()
  return mode
end

function module.IsCarrying()
  return carrying
end

-- Called whenever the cursor picks something up or puts it down.
local function CursorChanged()
  local now = CursorIsCarrying()
  if now == carrying then
    return carrying
  end
  carrying = now
  ApplyMode()
  if module.ApplyEmptySlots then module.ApplyEmptySlots() end
  return carrying
end
module.CursorChanged = CursorChanged

-- Kept for the older name: "editing" always meant dragging spells around.
function module.IsEditing()
  return mode == "drag"
end

-- What the game binds these keys to out of the box. Binding one to a
-- button overwrites the game's binding, and clearing that afterwards leaves
-- the key doing nothing at all -- so when the bars' bindings are cleared,
-- any of these left empty goes back to its job.
local GAME_KEYS = {
  ENTER = "OPENCHAT", SLASH = "OPENCHATSLASH", ESCAPE = "TOGGLEGAMEMENU",
  TAB = "TARGETNEARESTENEMY", SPACE = "JUMP",
  UP = "MOVEFORWARD", DOWN = "MOVEBACKWARD", LEFT = "TURNLEFT", RIGHT = "TURNRIGHT",
  W = "MOVEFORWARD", S = "MOVEBACKWARD", A = "TURNLEFT", D = "TURNRIGHT",
}
for i = 1, 12 do
  GAME_KEYS[({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" })[i]] = "ACTIONBUTTON" .. i
end
module.GAME_KEYS = GAME_KEYS

-- The few the game can't do without: with ENTER gone there is no typing the
-- command that would put it back. Keybind mode refuses these outright.
local PROTECTED_KEYS = {
  ENTER = true, ESCAPE = true, SLASH = true, BACKSPACE = true, TAB = true,
  -- The left mouse button clicks the whole UI; binding it globally to one
  -- action would break every click. Right, middle and the extra buttons are
  -- fair game.
  BUTTON1 = true,
}
module.PROTECTED_KEYS = PROTECTED_KEYS

local function Bind(button, key)
  local name = button.GetName and button:GetName()
  if not name or not SetBindingClick then
    return false
  end
  if PROTECTED_KEYS[key] then
    ns.Print(("%s can't be bound to a button; the game needs it."):format(key))
    return false
  end
  if Settings().allowModifiers ~= false then
    if IsShiftKeyDown and IsShiftKeyDown() then key = "SHIFT-" .. key end
    if IsControlKeyDown and IsControlKeyDown() then key = "CTRL-" .. key end
    if IsAltKeyDown and IsAltKeyDown() then key = "ALT-" .. key end
  end
  SetBindingClick(key, name, "LeftButton")
  RecordBind(name, key)
  SaveTo()
  UpdateHotkey(button)
  module.Status(("|cff4dc3ff%s|r bound to %s."):format(Abbreviate(key), module.ButtonLabel(button)))
  if module.PlayBindSound then module.PlayBindSound() end
  return true
end

local function Unbind(button)
  local key = BindingFor(button)
  local name = button.GetName and button:GetName()
  while key do
    if SetBinding then
      SetBinding(key, nil)
    end
    key = BindingFor(button)
  end
  -- And the game's own bind for the slot, or Backspace left its key showing.
  key = GameBindingFor(button)
  while key do
    if SetBinding then
      SetBinding(key, nil)
    end
    key = GameBindingFor(button)
  end
  if name then RecordUnbind(name) end
  SaveTo()
  UpdateHotkey(button)
  module.Status(("%s cleared."):format(module.ButtonLabel(button)))
  return true
end

-- One frame listens for keys in keybind mode, not the buttons. A frame
-- with the keyboard enabled receives EVERY key, hovered or not, and it
-- only passes a key on if its handler says so -- with forty-eight buttons
-- each having to say so in turn, one that erred on the way left the whole
-- keyboard dead, chat included, with no way to type the command that ends
-- the mode. So: one listener, which hands the key on BEFORE it looks at
-- anything that could go wrong, and only keeps it once a button under the
-- mouse has been found.
local listener

-- The button under the mouse. First choice is what OnEnter/OnLeave last told
-- us (hoveredButton) -- the game reports that plainly and it is what actually
-- broke keybinding before, because the fallback below can't be trusted on
-- this client: IsMouseOver() can hand back a value we're not allowed to test,
-- which the pcall turns into "no button", so a key press bound nothing.
local bindOverlay
local function HoveredButton()
  -- When the click-catching overlay is up it sits ON the button, so the
  -- button's own OnLeave has fired and hoveredButton is stale. The overlay
  -- remembers which button it covers; trust that first.
  if bindOverlay and bindOverlay:IsShown() and bindOverlay.target then
    return bindOverlay.target
  end
  -- Ask the game what the cursor is on right now. OnEnter/OnLeave alone go
  -- stale whenever something takes the mouse and hands it back without the
  -- mouse moving -- opening chat and closing it again, for one -- and then
  -- binding did nothing until the mouse was wiggled.
  if GetMouseFoci then
    local ok, foci = pcall(GetMouseFoci)
    if ok and type(foci) == "table" then
      for _, frame in ipairs(foci) do
        if frame == bindOverlay and bindOverlay.target then
          return bindOverlay.target
        end
        if type(frame) == "table" and frame.fuiEdit and frame.GetName then
          if FollowBindOverlay then FollowBindOverlay(frame) end
          return frame
        end
      end
    end
  end
  if hoveredButton and hoveredButton.IsShown then
    local ok, shown = pcall(hoveredButton.IsShown, hoveredButton)
    if ok and shown then
      return hoveredButton
    end
  end
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons) do
      local ok, over = pcall(function()
        return button:IsShown() and button:IsMouseOver() == true
      end)
      if ok and over == true then
        return button
      end
    end
  end
end
module.HoveredButton = HoveredButton

local function OnKey(frame, key)
  if frame.SetPropagateKeyboardInput then
    frame:SetPropagateKeyboardInput(true)
  end
  if mode ~= "keys" or MODIFIERS[key] then
    return
  end
  -- Typing beats binding: with chat (or any edit box) open, every key belongs
  -- to it. Without this, a message typed while the cursor happened to rest
  -- over a bar button would bind its letters one by one.
  if module.ChatIsOpen and module.ChatIsOpen() then
    return
  end
  if key == "ESCAPE" then
    if frame.SetPropagateKeyboardInput then
      frame:SetPropagateKeyboardInput(false)
    end
    if selectedButton then
      -- Esc lets go of the picked button. It used to CLEAR its binding,
      -- which is how "I bound it, pressed Escape, and it didn't save" came
      -- about. Clearing is Backspace or Delete now, and it says so.
      selectedButton = nil
      if module.HighlightSelected then module.HighlightSelected() end
      if module.ShowMouseCatcher then module.ShowMouseCatcher(false) end
      module.Status("Let go. Hover another button, or Escape again to finish.")
    else
      module.SetMode(nil)        -- Esc with nothing picked leaves keybind mode
    end
    return
  end
  -- Hover and press, the way Bartender and Dominos work: the key binds to
  -- the button you picked, or else to the one under the mouse. With neither,
  -- it passes through, so moving and chatting still work in keybind mode.
  local target = selectedButton
  if not target and Settings().hoverBind ~= false then
    target = HoveredButton()
  end
  if not target then
    return
  end
  if key == "BACKSPACE" or key == "DELETE" then
    if frame.SetPropagateKeyboardInput then
      frame:SetPropagateKeyboardInput(false)
    end
    Unbind(target)
    if module.RefreshBindTip then module.RefreshBindTip() end
    return
  end
  -- A key the game needs (Enter, the chat keys) is never taken, and never
  -- swallowed either: with the mouse resting over a button, keeping Enter
  -- would leave no way to open chat and type a command.
  if PROTECTED_KEYS[key] then
    module.Status(("%s can't be bound -- the game needs it."):format(key))
    return
  end
  if frame.SetPropagateKeyboardInput then
    frame:SetPropagateKeyboardInput(false)
  end
  if Bind(target, key) then
    if target == selectedButton then
      selectedButton = nil     -- done with this one; the next click picks the next
      if module.ShowMouseCatcher then module.ShowMouseCatcher(false) end
    end
    if module.HighlightSelected then module.HighlightSelected() end
    if module.RefreshBindTip then module.RefreshBindTip() end
  end
end
module.OnKey = OnKey

-- While a chat box is open the listener gives up the keyboard altogether.
-- Letting the key through (SetPropagateKeyboardInput) is not enough here:
-- the frame still holds the keyboard, and what gets typed can fall between
-- the two. Off and back on is exact.
local function ChatIsOpen()
  local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  return box and box.IsShown and box:IsShown() and true or false
end
module.ChatIsOpen = ChatIsOpen

local function Listener()
  if not listener then
    listener = CreateFrame("Frame", "ForeverUIKeybindListener", UIParent)
    listener:SetScript("OnKeyDown", OnKey)
    listener:Hide()
    -- Kept in step every tenth of a second rather than hooked to the chat
    -- box opening and closing: a hook that misses once would leave the
    -- keyboard off and binding dead until the next reload.
    local since = 0
    listener:SetScript("OnUpdate", function(self, elapsed)
      since = since + (elapsed or 0)
      if since < 0.1 then return end
      since = 0
      if mode ~= "keys" then return end
      local want = not ChatIsOpen()
      if self:IsKeyboardEnabled() ~= want then
        self:EnableKeyboard(want)
      end
    end)
  end
  return listener
end
module.Listener = Listener

-- The overlay that turns a MOUSE click into a binding.
--
-- Our buttons are secure: a real click casts the spell, which is exactly why
-- right-clicking one used to fire Moonfire instead of binding the button. So
-- in keybind mode a plain frame is laid over the button the mouse is on.
-- Being on top and mouse-enabled it swallows the click -- the button beneath
-- never casts -- reads which mouse button or wheel direction it was, and binds
-- that. Keyboard keys still come through the global listener above.
local MOUSE_BINDING = {
  RightButton = "BUTTON2", MiddleButton = "BUTTON3",
  Button4 = "BUTTON4", Button5 = "BUTTON5",
  -- LeftButton is left out on purpose: it clicks the whole UI (PROTECTED).
}
module.MOUSE_BINDING = MOUSE_BINDING

-- Paint every bindable button: a dim tint means "you can bind me", and the one
-- you've selected glows. Nothing changes on hover, so there's no trail.
local function HighlightSelected()
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons) do
      if button.fuiEdit then
        local hovered = bindOverlay and bindOverlay:IsShown() and bindOverlay.target
        if button == selectedButton then
          local r, g, b = unpack(ns.Colors.ui.accent)
          button.fuiEdit:SetColorTexture(r, g, b, 0.55)   -- the chosen one glows
        elseif button == hovered then
          button.fuiEdit:SetColorTexture(0.62, 0.40, 1.00, 0.45)  -- the one a key would bind
        else
          button.fuiEdit:SetColorTexture(1.00, 0.72, 0.20, 0.16)  -- dim "bindable"
        end
        button.fuiEdit:SetAlpha(1)
      end
    end
  end
end
module.HighlightSelected = HighlightSelected

-- Click a button to make it the target. Then a key (or a right/middle/extra
-- mouse click, or the wheel) binds to it.
-- While a button is picked, a sheet under the bars catches mouse buttons
-- pressed ANYWHERE -- the side buttons, the middle button, the wheel -- so
-- the mouse needn't be held over the button while you press the one you
-- want to bind. It sits at the bottom so the bars stay clickable on top;
-- a left click on it just lets go.
local mouseCatcher
function module.ShowMouseCatcher(show)
  if show and not mouseCatcher then
    local c = CreateFrame("Frame", "ForeverUIBindCatcher", UIParent)
    c:SetFrameStrata("BACKGROUND")
    c:SetAllPoints(UIParent)
    c:EnableMouse(true)
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseUp", function(_, mouseButton)
      if not selectedButton then return end
      if mouseButton == "LeftButton" then
        ns.Print("saw the left mouse button -- that one clicks the whole UI and can't be bound; letting go.")
        selectedButton = nil
        HighlightSelected()
        module.ShowMouseCatcher(false)
        return
      end
      local key = Settings().allowMouse ~= false and MOUSE_BINDING[mouseButton] or nil
      if key and Bind(selectedButton, key) then
        selectedButton = nil
        HighlightSelected()
        module.ShowMouseCatcher(false)
      end
    end)
    c:SetScript("OnMouseWheel", function(_, delta)
      if not selectedButton or Settings().allowMouse == false then return end
      local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
      ns.Print(("saw |cff4dc3ff%s|r"):format(key))
      if Bind(selectedButton, key) then
        selectedButton = nil
        HighlightSelected()
        module.ShowMouseCatcher(false)
      end
    end)
    mouseCatcher = c
    module.mouseCatcher = c
  end
  if mouseCatcher then
    mouseCatcher:SetShown(show and true or false)
  end
end

local function SelectButton(button)
  selectedButton = button
  HighlightSelected()
  module.ShowMouseCatcher(true)
  local bound = ShownBindingFor(button)
  if bound then
    module.Status(("%s picked (now %s). Press the new key, or Backspace to clear."):format(module.ButtonLabel(button), Abbreviate(bound)))
  else
    module.Status(("%s picked. Press the key you want."):format(module.ButtonLabel(button)))
  end
end
module.SelectButton = SelectButton

local function BuildBindOverlay()
  if bindOverlay then
    return bindOverlay
  end
  local o = CreateFrame("Frame", "ForeverUIBindOverlay", UIParent)
  o:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the action buttons
  o:EnableMouse(true)
  o:EnableMouseWheel(true)
  o:Hide()
  o:SetScript("OnMouseUp", function(self, mouseButton)
    if not self.target then
      return
    end
    if mouseButton == "LeftButton" then
      SelectButton(self.target)   -- left-click just picks the button
      return
    end
    local key = Settings().allowMouse ~= false and MOUSE_BINDING[mouseButton] or nil
    if key then
      SelectButton(self.target)   -- pick it, and bind the mouse button to it
      if Bind(self.target, key) then
        selectedButton = nil
        HighlightSelected()
        module.ShowMouseCatcher(false)
      end
    end
    -- Anything unmapped is eaten: no cast.
  end)
  o:SetScript("OnMouseWheel", function(self, delta)
    if self.target and Settings().allowMouse ~= false then
      SelectButton(self.target)
      if Bind(self.target, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") then
        selectedButton = nil
        HighlightSelected()
        module.ShowMouseCatcher(false)
      end
    end
  end)
  o:SetScript("OnEnter", function() module.RefreshBindTip() end)
  o:SetScript("OnLeave", function(self)
    self:Hide()
    self.target = nil
    if GameTooltip then GameTooltip:Hide() end
    HighlightSelected()
  end)
  bindOverlay = o
  return o
end
module.BuildBindOverlay = BuildBindOverlay

-- Lay the overlay over the button the mouse just entered (SkinButton's OnEnter
-- calls this in keybind mode through the forward-declared name).
FollowBindOverlay = function(button)
  if mode ~= "keys" or not button then
    return
  end
  local o = BuildBindOverlay()
  o.target = button
  o:ClearAllPoints()
  o:SetAllPoints(button)
  o:Show()
  HighlightSelected()
  module.RefreshBindTip()
end
module.FollowBindOverlay = FollowBindOverlay

-- "Action Bar 1, button 3" -- for the tooltip and the status line.
function module.ButtonLabel(button)
  local name = button and button.GetName and button:GetName() or "?"
  -- Buttons are named ForeverUIbar<N>Button<M> (and ForeverUIbar<name>...).
  local bar, index = name:match("^ForeverUI[Bb]ar(%w+)Button(%d+)$")
  if bar then
    return ("%s, button %s"):format(tonumber(bar) and ("Action bar " .. bar) or (bar:sub(1, 1):upper() .. bar:sub(2) .. " bar"), index)
  end
  return name
end

-- The tooltip over the hovered button: which button, what it is bound to,
-- and what a key press will do.
function module.RefreshBindTip()
  local o = bindOverlay
  if mode ~= "keys" or not (o and o:IsShown() and o.target and GameTooltip) then
    return
  end
  GameTooltip:SetOwner(o, "ANCHOR_TOP")
  GameTooltip:SetText(module.ButtonLabel(o.target), 1, 1, 1)
  local bound = ShownBindingFor(o.target)
  if bound then
    GameTooltip:AddLine(("Bound to: |cff9a6bff%s|r"):format(Abbreviate(bound)), 0.9, 0.9, 0.9)
  else
    GameTooltip:AddLine("Not bound", 0.6, 0.6, 0.6)
  end
  GameTooltip:AddLine("Press a key or mouse button to bind it.", 0.62, 0.40, 1.00, true)
  GameTooltip:AddLine("Backspace clears it.", 0.62, 0.62, 0.66)
  GameTooltip:Show()
end

-- The panel shown while keybind mode is on: what to do, the last thing that
-- happened, and a way out -- instead of paragraphs of chat.
local keyPanel
local function KeyPanel()
  if keyPanel then return keyPanel end
  local p = CreateFrame("Frame", "ForeverUIKeybindPanel", UIParent)
  p:SetSize(430, 104)
  p:SetPoint("TOP", UIParent, "TOP", 0, -120)
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:EnableMouse(true)
  p:SetMovable(true)
  p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  ns.Skin.Panel(p, { color = { 0.05, 0.03, 0.09, 0.95 }, borderColor = { 0.62, 0.40, 1.00, 1 } })
  local icon = ns.Skin.Icon(p, "keybinds", 26, { 0.74, 0.58, 1.00 })
  icon:SetPoint("TOPLEFT", 14, -12)
  local title = p:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(title, "header")
  title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
  title:SetText("Keybind mode")
  title:SetTextColor(1, 1, 1)
  local help = p:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(help, "general")
  help:SetPoint("TOPLEFT", 14, -44)
  help:SetPoint("RIGHT", -14, 0)
  help:SetJustifyH("LEFT")
  p.help = help
  help:SetTextColor(0.85, 0.85, 0.9)
  local status = p:CreateFontString(nil, "OVERLAY")
  ns.Media.SetFont(status, "general")
  status:SetPoint("BOTTOMLEFT", 14, 14)
  status:SetPoint("RIGHT", -110, 0)
  status:SetJustifyH("LEFT")
  status:SetTextColor(0.74, 0.58, 1.00)
  p.status = status
  local done = CreateFrame("Button", nil, p)
  done:SetSize(84, 26)
  done:SetPoint("BOTTOMRIGHT", -12, 10)
  ns.Skin.Button(done)
  done:SetText("Done")
  done:SetScript("OnClick", function() module.SetMode(nil) end)
  p.done = done
  p:Hide()
  keyPanel = p
  module.keyPanel = p
  return p
end

-- One line on the panel (the chat is left alone).
function module.Status(text)
  if keyPanel and keyPanel:IsShown() then
    keyPanel.status:SetText(text)
  else
    ns.Print(text)
  end
end

function module.PlayBindSound()
  if Settings().bindSound ~= false and PlaySound and SOUNDKIT then
    pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
  end
end

function ApplyMode()
  local dragging = mode == "drag"
  local placing = dragging or carrying
  -- The game's own lock as well, so anything we don't own respects it too.
  ns.SetCVar("lockActionBars", placing and "0" or "1")
  local ears = Listener()
  ears:EnableKeyboard(mode == "keys" and not ChatIsOpen())
  ears:SetShown(mode == "keys")
  -- Leaving keybind mode with the mouse still over a button would strand the
  -- overlay on top of it, swallowing real clicks. Put it away.
  if bindOverlay and mode ~= "keys" then
    bindOverlay:Hide()
    bindOverlay.target = nil
  end
  selectedButton = nil   -- a fresh mode starts with nothing picked
  module.ShowMouseCatcher(false)
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons) do
      -- Locked, a drag only starts with Shift held: Blizzard's button checks
      -- the lock and the PICKUPACTION modifier itself (ActionButton.lua,
      -- ActionBarActionButtonMixin:OnDragStart), so registering is enough.
      if placing or Settings().shiftDrag ~= false then
        button:RegisterForDrag("LeftButton")
      else
        button:RegisterForDrag()          -- nothing starts a drag
      end
      if button.fuiEdit then
        local color = MODE_COLORS[mode]
        if color then
          button.fuiEdit:SetColorTexture(unpack(color))
        end
        button.fuiEdit:SetShown(mode ~= nil)
      end
    end
  end
  -- In keybind mode, paint the dim "bindable" tint (nothing picked yet).
  if mode == "keys" then
    HighlightSelected()
    local p = KeyPanel()
    p.help:SetText(Settings().hoverBind ~= false
      and "Hover a button and press a key, mouse button or wheel.  Backspace clears it."
      or "Click a button to pick it, then press the key you want.  Backspace clears it.")
    p.status:SetText(("Saving to: %s"):format(SetName()))
    p:Show()
  elseif keyPanel then
    keyPanel:Hide()
    if GameTooltip and bindOverlay and GameTooltip:GetOwner() == bindOverlay then GameTooltip:Hide() end
  end
end
module.ApplyMode = ApplyMode
module.ApplyLock = ApplyMode  -- the name this had before there were two modes

local MODE_HELP = {
  drag = "bars unlocked - drag spells on and off. |cff4dc3ff/fui lock|r when you're done.",
  keys = "keybind mode on - hover a button and press a key. Escape or Done to finish.",
}

function module.SetMode(wanted)
  if wanted == mode then
    return mode
  end
  if InCombatLockdown() then
    ns.Print("bars can't be unlocked in combat.")
    return mode
  end
  mode = wanted
  ApplyMode()
  ns.Print(MODE_HELP[mode] or "bars locked.")
  ns.RefreshOptions()
  return mode
end

function module.SetEditing(on)
  return module.SetMode(on and "drag" or nil) == "drag"
end

-- if/else, not `mode == "drag" and nil or "drag"`: that is "drag" either
-- way, so the toggle could turn editing on but never off again.
function module.ToggleEditing()
  if mode == "drag" then
    return module.SetMode(nil)
  end
  return module.SetMode("drag")
end

-- Every binding that clicks one of our buttons, gone. For when keybind
-- mode has bound things it shouldn't have.
function module.ClearAllKeybinds()
  local cleared = 0
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons) do
      local key = BindingFor(button)
      while key do
        if SetBinding then
          SetBinding(key, nil)
        end
        cleared = cleared + 1
        key = BindingFor(button)
      end
      UpdateHotkey(button)
    end
  end
  -- And the keys the game needs, put back if anything took them: without
  -- ENTER opening chat there is no typing a command to fix it.
  local restored = 0
  for key, action in pairs(GAME_KEYS) do
    if GetBindingAction and SetBinding then
      local current = GetBindingAction(key)
      if current == nil or current == "" or current:find("^CLICK ForeverUI") then
        SetBinding(key, action)
        restored = restored + 1
      end
    end
  end
  ns.Wipe(CurrentSet())
  if cleared > 0 or restored > 0 then
    SaveTo()
  end
  ns.Print(("%d keybind%s cleared from the bars%s."):format(
    cleared, cleared == 1 and "" or "s",
    restored > 0 and (("; %d of the game's own keys put back"):format(restored)) or ""))
  return cleared, restored
end

function module.ToggleKeybinds()
  if mode == "keys" then
    return module.SetMode(nil)
  end
  return module.SetMode("keys")
end

---------------------------------------------------------------------------
-- Cooldown numbers
--
-- "If a spell is not ready I want a number to tell me when it will be" (the
-- owner, 24 Sept 2026). Two things stood in the way. Our buttons are made by
-- addon code, so in combat Blizzard's own update hands their spinner secret
-- numbers it refuses (GuardCooldown above keeps that from erroring, and the
-- spiral just didn't draw). And an addon can't read a cooldown to count it
-- down itself.
--
-- Forever's way round both: C_ActionBar.GetActionCooldownDuration returns a
-- DURATION OBJECT, which isn't locked in combat, and a Cooldown frame takes
-- one with SetCooldownFromDurationObject. The game then draws the spiral AND
-- its own countdown numbers - we never see the time. So after every cooldown
-- update (a frame later, after Blizzard's own pass) each button is handed
-- its duration object, and its countdown numbers are switched on in our font.
-- Anything under two seconds (the global cooldown) gets no number.
---------------------------------------------------------------------------

local MIN_NUMBER_MS = 2000
local countdownFonts = {}

-- A font object per size: SetCountdownFont takes a font object's name.
local function CountdownFont(size)
  size = math.max(10, math.floor(size + 0.5))
  local name = "ForeverUICooldownNumbers" .. size
  if not countdownFonts[size] and CreateFont then
    local font = CreateFont(name)
    local path = ns.Media.Role("general")
    font:SetFont(path, size, "OUTLINE")
    countdownFonts[size] = font
  end
  return name
end

local function ButtonAction(button)
  local action = button.action
  if type(action) ~= "number" and button.GetAttribute then action = button:GetAttribute("action") end
  if type(action) ~= "number" or (issecretvalue and issecretvalue(action)) then return nil end
  return action
end

-- Numbers on (or off) for one button's spinner, sized to the button.
local function SetUpNumbers(button, on)
  local cooldown = Element(button, "cooldown") or Element(button, "Cooldown")
  if not cooldown then return nil end
  if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, not on) end
  if on then
    if cooldown.SetMinimumCountdownDuration then pcall(cooldown.SetMinimumCountdownDuration, cooldown, MIN_NUMBER_MS) end
    local size = (button.GetWidth and button:GetWidth() or 36) * 0.42
    if cooldown.SetCountdownFont then pcall(cooldown.SetCountdownFont, cooldown, CountdownFont(size)) end
  end
  return cooldown
end

-- Hand every button its cooldown as a duration object.
function module.UpdateCooldownNumbers()
  local on = Settings().cooldownNumbers ~= false
  local api = C_ActionBar
  local haveDurations = api and api.GetActionCooldownDuration
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons or {}) do
      local cooldown = SetUpNumbers(button, on)
      local action = ButtonAction(button)
      if cooldown and action and haveDurations and cooldown.SetCooldownFromDurationObject then
        local ok, duration = pcall(api.GetActionCooldownDuration, action)
        if ok and duration then pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration) end
        local charge = rawget(button, "chargeCooldown") or rawget(button, "ChargeCooldown")
        if charge and api.GetActionChargeDuration and charge.SetCooldownFromDurationObject then
          local okC, chargeDuration = pcall(api.GetActionChargeDuration, action)
          if okC and chargeDuration then pcall(charge.SetCooldownFromDurationObject, charge, chargeDuration) end
        end
      end
    end
  end
end

-- One pass a frame after the burst of cooldown events, so it lands after
-- Blizzard's own (failed, in combat) update rather than before it.
local cooldownPending = false
local function QueueCooldownNumbers()
  if cooldownPending then return end
  cooldownPending = true
  local function Run()
    cooldownPending = false
    module.UpdateCooldownNumbers()
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
end
module.QueueCooldownNumbers = QueueCooldownNumbers

local cooldownWatcher = CreateFrame("Frame")
for _, event in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
  "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR",
  "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  pcall(cooldownWatcher.RegisterEvent, cooldownWatcher, event)
end
cooldownWatcher:SetScript("OnEvent", function()
  if ns.ModuleRunning("ActionBars") then QueueCooldownNumbers() end
end)
module.cooldownWatcher = cooldownWatcher

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function BuildBar(info)
  local bar = CreateFrame("Frame", "ForeverUIBar" .. info.key, UIParent, "SecureHandlerStateTemplate")
  bar.info = info
  bar.buttons = {}

  for index = 1, BUTTONS_PER_BAR do
    local name = "ForeverUI" .. info.key .. "Button" .. index
    local button = CreateFrame("CheckButton", name, bar, "ActionBarButtonTemplate")
    button.fuiTemplate = "ActionBarButtonTemplate"
    button:SetAttribute("type", "action")
    button:SetAttribute("action", info.first + index - 1)
    button.fuiGameBinding = GAME_BINDINGS[info.key] and GAME_BINDINGS[info.key] .. index
    -- No ID. A secure action button with an ID above 0 ignores its "action"
    -- attribute and uses ID + (page - 1) * 12 instead, page being the game's
    -- action bar page (SecureActionButtonMixin:CalculateAction, forever
    -- branch). So Blizzard's page keys shifted EVERY bar of ours by 12 slots
    -- a page, and the main bar never showed stealth or a stance, whatever
    -- ApplyPage set (goldfish117 on CurseForge, 30 Sept 2026: "My main bar
    -- isn't changing to stealth bar ... the keybinds for changing page still
    -- function and change every bar ... Bar 7 becomes Bar 8, Bar 5 becomes 3").
    -- With ID 0 the attribute is the slot, and only ApplyPage moves it.
    button:SetID(0)
    button:RegisterForClicks("AnyUp")
    button.fuiClicks = "AnyUp"
    button:EnableMouse(true)
    DeferPressAndHold(button)
    -- Blizzard's own hotkey pass (on every binding change) writes the label
    -- from the button's ID -- none, here -- and blanked ours (Altiokis, 30
    -- Sept 2026: "Keybind text is missing too, even though I have it
    -- enabled"). Ours goes back on after it.
    if hooksecurefunc and type(button.UpdateHotkeys) == "function" then
      hooksecurefunc(button, "UpdateHotkeys", function(self) module.UpdateHotkey(self) end)
    end
    bar.buttons[index] = button
  end


  ns.RegisterMover(info.key, info.label, bar, info.default)
  bars[info.key] = bar
  return bar
end

-- Size, spacing and wrapping. A bar set vertical is a single column; the
-- rest follow the buttons-per-row setting.
-- Buttons a bar doesn't use are parked here. Hiding them isn't enough:
-- Blizzard's own button code shows an action button again whenever its slot
-- changes. A button whose parent is hidden stays out of sight whatever it
-- is told, and comes back as it was when it is handed back to its bar.
local parked = CreateFrame("Frame")
parked:Hide()
module.parkedButtons = parked

local function LayoutBar(bar)
  local settings = Settings()
  local key = bar.info.key
  local size, gap = module.BarOpt(key, "size"), module.BarOpt(key, "spacing")
  local count = math.max(1, math.min(module.BarOpt(key, "buttons") or BUTTONS_PER_BAR, BUTTONS_PER_BAR))
  local vertical = settings.vertical and settings.vertical[key]
  if vertical == nil then vertical = module.defaults.vertical[key] end   -- a bar the profile predates
  local perRow = vertical and 1 or module.BarOpt(key, "perRow")
  perRow = math.max(1, math.min(perRow, count))
  local columns = perRow
  local rows = math.ceil(count / columns)

  for index, button in ipairs(bar.buttons) do
    if settings.flatButtons then
      SkinButton(button)
    end
    local used = index <= count
    if button:GetParent() ~= (used and bar or parked) then
      button:SetParent(used and bar or parked)
    end
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", bar, "TOPLEFT", column * (size + gap), -row * (size + gap))

    -- These come from Blizzard's template; a client that names them
    -- differently just doesn't get the toggle rather than an error.
    UpdateHotkey(button)
    if type(button.Name) == "table" and button.Name.SetShown then
      button.Name:SetShown(settings.showMacroText)
    end
  end

  local width = columns * size + (columns - 1) * gap
  local height = rows * size + (rows - 1) * gap
  bar:SetSize(width, height)
  ns.UpdateMoverSize(bar.info.key, width, height)
  return width, height
end

-- Bars you haven't moved yourself stack upwards from the main bar, each clear
-- of the one below whatever size the buttons are. Once you drag a bar, its
-- saved position wins and we leave it alone.
local STACK_GAP = 6
local STACK_ORDER = { "bar1", "bar2", "bar3" }

local function StackBars()
  local settings = Settings()
  local y = 34
  for _, key in ipairs(STACK_ORDER) do
    local bar = bars[key]
    if bar and bar:IsShown() then
      if not ns.db.movers[key] then
        ns.SetMoverDefault(key, { "BOTTOM", "BOTTOM", 0, y })
      end
      y = y + bar:GetHeight() + STACK_GAP + settings.spacing
    end
  end
end
module.StackBars = StackBars

---------------------------------------------------------------------------
-- Blizzard's bars
---------------------------------------------------------------------------

-- Everything Blizzard draws for the bottom bar, including the gryphons at
-- each end and the art strip behind the buttons. Names differ between game
-- versions, so anything missing is simply skipped and reported by /fui bars.
local BLIZZARD_BARS = {
  "MainMenuBar", "MainMenuBarArtFrame", "MainActionBar",
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",          -- the gryphons
  "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
  "MainMenuBarTextureExtender", "MainMenuBarMaxLevelBar",
  "MainMenuBarPerformanceBarFrame", "MainMenuBarPageNumber",
  "ActionBarUpButton", "ActionBarDownButton",
  "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
  "StanceBarFrame", "PossessBarFrame",
  -- The newer client's names: a druid's shapeshift bar, the pet bar and the
  -- possess bar are Edit Mode systems of their own, parked above the main
  -- bar. Left in place they sit invisibly over our buttons and eat clicks.
  "StanceBar", "PetActionBar", "PossessActionBar", "MultiBar5", "MultiBar6", "MultiBar7",
}

local MICRO_MENU = {
  -- The containers first: on clients that have them, hiding the container
  -- takes the buttons with it whatever they're individually called.
  "MicroButtonAndBagsBar", "MicroMenuContainer", "MicroMenu", "MicroButtonFrame",
  "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
  "SocialsMicroButton", "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton",
  "GuildMicroButton", "LFGMicroButton", "PVPMicroButton", "AchievementMicroButton",
  "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton", "MicroButtonPortrait",
}

-- The same list as a lookup, so the hide loop can tell a micro button from a
-- bar without searching.
local MICRO_NAMES = {}
for _, name in ipairs(MICRO_MENU) do
  MICRO_NAMES[name] = true
end
-- Blizzard's backpack button takes the micro bar's Bags clicks since 0.4.62
-- (forwarded, so the game opens its bags itself), so with the bag bar
-- hidden it is parked like a micro button rather than hidden: a hidden or
-- mouse-less button refuses a forwarded click, and Bags did nothing.
MICRO_NAMES.MainMenuBarBackpackButton = true

local BAG_BAR = {
  "BagsBar", "MainMenuBarBagsBar", "MicroButtonAndBagsBar",
  "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
  "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton", "MainMenuBarBagsBar",
}

local XP_BARS = {
  -- Classic Era rebuilt the XP and reputation bars as a managed container;
  -- older clients keep them as separate frames. Both are listed.
  "StatusTrackingBarManager", "MainStatusTrackingBarContainer",
  "SecondaryStatusTrackingBarContainer",
  "MainMenuExpBar", "ReputationWatchBar", "ExhaustionTick", "ExhaustionTickNormal",
  "MainMenuBarMaxLevelBar", "MainMenuXPBarTextureLeftCap", "MainMenuXPBarTextureRightCap",
  "MainMenuXPBarTextureMid", "ReputationWatchStatusBar",
}

-- The two above that belong to StatusTrackingBarManager (see HideBlizzardBars).
local XP_CONTAINERS = { MainStatusTrackingBarContainer = true, SecondaryStatusTrackingBarContainer = true }

-- Same approach as the other Blizzard frames: under a hidden parent, where
-- Blizzard's own Show() calls can't bring them back. Needs a /reload to undo.
-- Which groups the settings ask for, gathered into one list.
local PET_BAR = { PetActionBar = true, PetActionBarFrame = true }
local STANCE_BAR = { StanceBar = true, StanceBarFrame = true }

-- A Blizzard bar the settings leave standing (the pet bar, the stance bar).
local function KeptBar(name)
  local settings = Settings()
  return (settings.showPetBar ~= false and PET_BAR[name]) or (settings.showStanceBar and STANCE_BAR[name]) or false
end
module.KeptBar = KeptBar

local function WantedFrames()
  local settings = Settings()
  local wanted = {}
  local function add(list)
    for _, name in ipairs(list) do
      if not KeptBar(name) then
        wanted[#wanted + 1] = name
      end
    end
  end
  if settings.hideBlizzardBars then add(BLIZZARD_BARS) end
  if settings.hideMicroMenu then add(MICRO_MENU) end
  if settings.hideBags then add(BAG_BAR) end
  if settings.hideXpBar then add(XP_BARS) end
  return wanted
end

local function HideBlizzardBars()
  hiddenParent = hiddenParent or CreateFrame("Frame")
  hiddenParent:Hide()
  local hidden, missing = {}, {}
  local results = {}
  for _, name in ipairs(WantedFrames()) do
    local frame = _G[name]
    if frame and XP_CONTAINERS[name] then
      -- The XP and reputation bar containers are NEVER moved under our
      -- hidden frame: each one asks its parent to re-lay itself out
      -- (StatusTrackingManager.lua:228, self:GetParent():CheckForLayoutChange),
      -- and under ours that was "attempt to call a nil value" the moment
      -- Edit Mode opened (Altiokis on CurseForge, 30 Sept 2026). Hidden with
      -- the manager above them when that went; otherwise faded where they are.
      if results.StatusTrackingBarManager ~= "hidden" then
        if frame.SetAlpha then frame:SetAlpha(0) end
        if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
        if not rawget(frame, "fuiKeptFaded") and hooksecurefunc then
          frame.fuiKeptFaded = true
          -- Blizzard fades the bar back in on its own; keep it at nothing.
          hooksecurefunc(frame, "SetAlpha", function(self, a)
            if a ~= 0 and Settings().hideXpBar then self:SetAlpha(0) end
          end)
        end
      end
      hidden[#hidden + 1] = name
    elseif frame then
      -- Frames the game repositions for you come back unless they're taken
      -- off that list first.
      if UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS[name] = nil
      end
      -- Protected frames are faded rather than re-parented: re-parenting one
      -- is blocked, and being blocked taints us so our own buttons stop
      -- casting. Textures can't be re-parented either; hiding is enough.
      if MICRO_NAMES[name] then
        -- Blizzard's micro buttons are parked rather than hidden, and keep
        -- their mouse: our own micro bar hands its clicks to them, and the
        -- game refuses to forward a click to a button that is hidden or
        -- cannot be clicked. Parked, they are invisible and thousands of
        -- pixels off screen, but still there to be clicked.
        --
        -- They are deliberately NOT deafened either, for the same reason.
        -- Doing both is what left every button on the micro bar dead.
        ns.Skin.Park(frame)
      else
        results[name] = ns.Skin.Conceal(frame, hiddenParent)
        -- A bar the game puts back brings its buttons with it, invisible,
        -- one frame level above ours, and they eat the click -- which is
        -- what made keys 7 and 8 on the main bar unclickable while looking
        -- perfectly normal. Taking the mouse off the buttons themselves
        -- holds even when the bar comes back, and needs doing only once.
        ns.Skin.Deafen(frame)
      end
      hidden[#hidden + 1] = name
    else
      missing[#missing + 1] = name
    end
  end
  module.hidden, module.missing = hidden, missing
  return hidden, missing
end
module.HideBlizzardBars = HideBlizzardBars

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

-- Empty slots draw an outline unless the game is told otherwise. This is a
-- game setting rather than something we can style away.
local function ApplyEmptyButtons()
  local show = Settings().showEmptyButtons and "1" or "0"
  ns.SetCVar("alwaysShowActionBars", show)
  if module.ApplyEmptySlots then module.ApplyEmptySlots() end
end

-- The game setting only reaches Blizzard's own bars: ours are drawn flat,
-- with a tile and a border of their own, so an empty slot kept its outline
-- (and its keybind) whatever the switch said (goldfish117, 30 Sept 2026:
-- "Show empty button outlines doesn't work, keybinds show as well"). An
-- empty slot of ours is see-through when the switch is off -- and shows
-- again the moment you pick up a spell, so there is somewhere to drop it.
-- Alpha only: allowed in a fight, and the button stays where it is.
local function HasActionIn(button)
  local action = button and button.GetAttribute and button:GetAttribute("action")
  if type(action) ~= "number" or not HasAction then return true end
  local ok, has = pcall(HasAction, action)
  if not ok then return true end
  local okTest, yes = pcall(function() return has and true or false end)
  return not okTest or yes
end
module.HasActionIn = HasActionIn

function module.ApplyEmptySlots()
  local showAll = Settings().showEmptyButtons or module.IsCarrying and module.IsCarrying()
    or module.IsEditing and module.IsEditing()
  for _, bar in pairs(bars) do
    for _, button in ipairs(bar.buttons or {}) do
      if button.SetAlpha then
        button:SetAlpha((showAll or HasActionIn(button)) and 1 or 0)
      end
    end
  end
end

local function VisibleBars()
  local settings = Settings()
  for key, bar in pairs(bars) do
    -- A bar a saved profile has never heard of (5-8 arrived in 0.4.35)
    -- takes its default, off, rather than turning up unasked.
    local on = settings.bars[key]
    if on == nil then on = module.defaults.bars[key] end
    bar:SetShown(on ~= false)
  end
end

-- Bindings also change from Blizzard's own key bindings window, so the text
-- follows the game rather than only our own keybind mode.
local bindingWatcher

---------------------------------------------------------------------------
-- Why isn't this button clicking?
---------------------------------------------------------------------------
--
-- A click that does nothing has a short list of causes: something invisible
-- is on top, the button has had its mouse turned off, the game is refusing
-- the action, or the bars are in a mode. Rather than guess at which, this
-- reports what the game itself says is under the cursor.

local MouseFocus = ns.Skin.MouseFocus
module.MouseFocus = MouseFocus

local function Describe(frame)
  if not frame then
    return "nothing"
  end
  local name = (frame.GetName and frame:GetName()) or "(unnamed)"
  local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "?"
  local level = frame.GetFrameLevel and frame:GetFrameLevel() or 0
  return ("%s [%s %d]"):format(name, strata, level)
end

-- Everything that decides whether a click casts, written to saved variables
-- at login so it can be read off disk rather than copied out of chat. Three
-- different causes have hidden behind the same symptom already; this stops
-- the guessing.
function module.Snapshot()
  local bar = bars.bar1
  local button = bar and bar.buttons and bar.buttons[1]
  if not button then
    ns.db.diagnostics = { built = false, when = date and date() or "?" }
    return ns.db.diagnostics
  end

  local name = button:GetName()
  local action = button:GetAttribute("action")
  local function ask(fn, ...)
    local ok, value = pcall(fn, ...)
    return ok and value or nil
  end

  local snapshot = {
    when = date and date() or "?",
    built = true,
    bars = 0,
    name = name,
    template = button.fuiTemplate,
    kind = ask(button.GetObjectType, button),
    shown = button:IsShown() and true or false,
    visible = ask(button.IsVisible, button),
    mouse = ask(button.IsMouseEnabled, button),
    protected = ask(button.IsProtected, button),
    strata = ask(button.GetFrameStrata, button),
    level = ask(button.GetFrameLevel, button),
    points = ask(button.GetNumPoints, button),
    parent = bar and bar:GetName() or "?",
    attrType = tostring(button:GetAttribute("type")),
    action = tostring(action),
    actionKind = type(action),
    hasAction = issecurevariable and tostring(ask(HasAction, action)) or "?",
    -- If the attribute is insecure, the game refuses the cast and says nothing.
    actionSecure = issecurevariable and tostring(select(1, issecurevariable(button, "action"))) or "?",
    onClick = button:GetScript("OnClick") ~= nil,
    onMouseDown = button:GetScript("OnMouseDown") ~= nil,
    clicks = button.fuiClicks,
    binding = GetBindingKey and GetBindingKey("CLICK " .. (name or "") .. ":LeftButton") or "",
    page = module.page,
    mode = tostring(mode),
    carrying = carrying and true or false,
    moversShown = ns.MoversShown() and true or false,
    inCombat = InCombatLockdown() and true or false,
    lockActionBars = GetCVar and GetCVar("lockActionBars") or "?",
    alwaysShowActionBars = GetCVar and GetCVar("alwaysShowActionBars") or "?",
    useKeyDown = GetCVar and GetCVar("ActionButtonUseKeyDown") or "?",
    hiddenBlizzard = module.hidden and #module.hidden or 0,
    missingBlizzard = module.missing and table.concat(module.missing, ",") or "",
  }
  for _ in pairs(bars) do
    snapshot.bars = snapshot.bars + 1
  end
  ns.db.diagnostics = snapshot
  return snapshot
end

-- What the mouse is over, and everything above it. Sampled a few seconds
-- after the command so the cursor has been moved onto the thing that isn't
-- clicking -- reading it while you are still typing in chat says "nothing"
-- and teaches us not a thing.
function module.SampleCursor()
  local focus, all = MouseFocus()
  if not focus then
    ns.Print("nothing under the cursor - move it over the button and try again.")
    ns.Print(("|cff888888(GetMouseFoci %s, GetMouseFocus %s)|r"):format(
      GetMouseFoci and "yes" or "no", GetMouseFocus and "yes" or "no"))
    return nil
  end
  if #all > 1 then
    ns.Print(("%d frames under the cursor; the top one takes the click:"):format(#all))
  end
  ns.Print(("under the cursor: |cff4dc3ff%s|r"):format(Describe(focus)))

  -- Whose is it? Walking up names the frame that is actually taking the click.
  local frame, depth = focus, 0
  while frame and depth < 8 do
    local name = frame.GetName and frame:GetName()
    if name then
      ns.Print(("   in %s%s"):format(Describe(frame),
        name:find("^ForeverUI") and " |cff4dc3ff(ours)|r" or ""))
    end
    frame = frame.GetParent and frame:GetParent()
    depth = depth + 1
  end

  local bar = bars.bar1
  local button = bar and bar.buttons and bar.buttons[1]
  if button and focus ~= button then
    ns.Print(("button 1 is at %s - if that isn't what you were over, the click is landing elsewhere."):format(
      Describe(button)))
  end
  return focus
end

function module.Diagnose()
  local bar = bars.bar1
  local button = bar and bar.buttons and bar.buttons[1]
  if not button then
    ns.Print("no bars built yet.")
    return false
  end

  local focus = MouseFocus()
  ns.Print(("mouse is over: |cff4dc3ff%s|r"):format(Describe(focus)))
  if focus and focus ~= button and bar.buttons[1] then
    ns.Print("  hover a bar button and run this again to see what's on top of it.")
  end

  ns.Print(("button 1: %s"):format(Describe(button)))
  ns.Print(("  shown=%s mouse=%s clicks=%s"):format(
    tostring(button:IsShown()),
    tostring(button.IsMouseEnabled and button:IsMouseEnabled()),
    tostring(button.fuiClicks or "not registered")))
  ns.Print(("  type=%s action=%s"):format(
    tostring(button:GetAttribute("type")), tostring(button:GetAttribute("action"))))
  ns.Print(("bars are %s; cursor %s carrying"):format(
    mode and ("in " .. mode .. " mode") or "locked",
    carrying and "is" or "is not"))
  if ns.MoversShown() then
    ns.Print("|cffff6666move mode is on|r - the drag handles are above everything and take every click. /fui move to finish.")
  end
  if InCombatLockdown() then
    ns.Print("in combat: frames can't be rebuilt until it ends.")
  end

  ns.Print("|cff4dc3ffmove the mouse over the button that won't click|r - reading it in 3 seconds.")
  if C_Timer and C_Timer.After then
    C_Timer.After(3, module.SampleCursor)
  else
    module.SampleCursor()
  end
  return true
end

---------------------------------------------------------------------------
-- Paging
---------------------------------------------------------------------------

local pageWatcher

local function ApplyPage()
  local bar = bars.bar1
  if not bar then
    return nil
  end
  if InCombatLockdown() then
    -- Attributes can't be set in combat; do it the moment the fight ends
    -- (once, however many stance or page changes the fight brings).
    if not module.pagePending then
      module.pagePending = true
      ns.WhenOutOfCombat(function() module.pagePending = false; ApplyPage() end)
    end
    return nil
  end
  local page = CurrentPage()
  for index, button in ipairs(bar.buttons) do
    button:SetAttribute("action", SlotFor(page, index))
  end
  module.page = page
  return page
end
module.ApplyPage = ApplyPage

local PAGE_EVENTS = {
  -- A slot filled or emptied: whether it shows (ApplyEmptySlots).
  "ACTIONBAR_SLOT_CHANGED",
  "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
  "UPDATE_VEHICLE_ACTIONBAR", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
  -- The moment combat starts is the last chance to wrap a cooldown before it
  -- is asked to draw a secret start time.
  "PLAYER_REGEN_DISABLED",
}

local function WatchPaging()
  pageWatcher = pageWatcher or CreateFrame("Frame")
  for _, event in ipairs(PAGE_EVENTS) do
    pcall(pageWatcher.RegisterEvent, pageWatcher, event)
  end
  pageWatcher:SetScript("OnEvent", function(_, event)
    if event == "ACTIONBAR_SLOT_CHANGED" then
      -- Only whether a slot shows; the page hasn't moved.
      module.ApplyEmptySlots()
      return nil
    end
    -- Before the page moves, not after: a bar that has just been paged in
    -- redraws its cooldowns immediately.
    GuardBlizzardCooldowns()
    local page = ApplyPage()
    module.ApplyEmptySlots()
    return page
  end)
  module.pageWatcher = pageWatcher
  return pageWatcher
end

function module:OnInit()
  bindingWatcher = bindingWatcher or CreateFrame("Frame")
  -- Not every client has every event, and registering one it doesn't know
  -- raises -- which used to abort the rest of this function.
  for _, event in ipairs({
    "UPDATE_BINDINGS", "CURSOR_UPDATE", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID",
    "CURSOR_CHANGED",
  }) do
    pcall(bindingWatcher.RegisterEvent, bindingWatcher, event)
  end
  bindingWatcher:SetScript("OnEvent", function(_, event)
    -- Sitting out for the controller: the game's own bars are in use, and
    -- the lock is theirs to keep.
    if ns.ControllerSuspended and ns.ControllerSuspended("ActionBars") then return end
    if event == "UPDATE_BINDINGS" then
      UpdateAllHotkeys()
    else
      CursorChanged()
    end
  end)
  module.bindingWatcher = bindingWatcher
end

function module:OnEnable()
  ns.WhenOutOfCombat(function()
    for _, info in ipairs(BARS) do
      if not bars[info.key] then
        BuildBar(info)
      end
    end
    for _, bar in pairs(bars) do
      LayoutBar(bar)
    end
    VisibleBars()
    StackBars()
    HideBlizzardBars()
    ApplyEmptyButtons()
    AlignBindingSet()   -- put the game on the binding set the profile chose
    module.ApplySavedKeybinds()   -- and our own copy of the binds back on the bars
    ApplyMode()
    WatchPaging()
    ApplyPage()
    -- Local patch (4 Oct 2026): out of the game's shared button loops before
    -- the world is entered and Blizzard's first ActionBarController_UpdateAll
    -- walks them (see OwnButtons.lua).
    GuardRegisteredButtons()
    module.Snapshot()
    QueueCooldownNumbers()
  end)
end

function module:OnDisable()
  ns.WhenOutOfCombat(function()
    for _, bar in pairs(bars) do
      bar:Hide()
    end
  end)
end

module.needsReload = true -- Blizzard's bars only come back on a reload, which we do ourselves

function module:Refresh()
  -- Not inside WhenOutOfCombat: a cooldown frame Blizzard only makes when a
  -- spell first ticks can appear mid-fight, and wrapping it is a plain Lua
  -- assignment on a frame we have already tainted -- nothing secure, nothing
  -- the game refuses in combat.
  GuardBlizzardCooldowns()
  QueueCooldownNumbers()
  ns.WhenOutOfCombat(function()
    for _, bar in pairs(bars) do
      LayoutBar(bar)
      for _, button in ipairs(bar.buttons or {}) do
        GuardButtonCooldowns(button)
      end
    end
    VisibleBars()
    StackBars()
    HideBlizzardBars()
    ApplyEmptyButtons()
    ApplyMode()
  end)
end

module.bars = bars
module.PageCondition = PageCondition
module.LayoutBar = LayoutBar

local _, ns = ...

-- Raid markers at your fingertips (owner, 25 Sept 2026, after his first
-- dungeon as a tank: "within a pack, as a tank, I need the ability to put a
-- skull on the head ... an X as my secondary ... moon ... at my fingertips,
-- pretty simple").
--
-- A small bar of the eight marks and a clear button: left-click puts that
-- mark on your target, right-click takes your target's mark off. Every one
-- is also a key, under ForeverUI in the game's Key Bindings - skull, cross
-- and moon on keys you already reach is the whole point.
--
-- How, and why not the obvious way: on Forever SetRaidTarget is restricted
-- for addons and which marks are in use comes back secret, so an addon can't
-- reliably place marks itself in a dungeon. The secure button template has
-- its own "raidtarget" action (Blizzard_FrameXML/SecureTemplates.lua,
-- forever branch) that marks a unit when the button is clicked, in combat
-- too - so every button here is a secure button of that type and the game
-- does the marking. (The first cut ran "/tm 8" as macro text; clicking the
-- skull did nothing in the owner's first try, 25 Sept 2026.)
--
-- The keys have buttons of their own, hidden, so they can mark either your
-- target or whatever is under the mouse (a mob, or its nameplate) - hover
-- the thing chewing on your healer and press the skull key.

local module = ns.RegisterModule({
  name = "Markers",
  title = "Raid Markers",
})

-- Skull first: the order a tank calls kills in.
module.MARKS = {
  { index = 8, label = "Skull" }, { index = 7, label = "Cross" }, { index = 6, label = "Square" },
  { index = 5, label = "Moon" }, { index = 4, label = "Triangle" }, { index = 3, label = "Diamond" },
  { index = 2, label = "Circle" }, { index = 1, label = "Star" },
}

-- The key names the game's Key Bindings window shows (Bindings.xml).
for _, mark in ipairs(module.MARKS) do
  _G["BINDING_NAME_CLICK ForeverUIMarkKey" .. mark.index .. ":LeftButton"] = "Mark: " .. mark.label
end
_G["BINDING_NAME_CLICK ForeverUIMarkKeyClear:LeftButton"] = "Clear mark"
_G["BINDING_NAME_CLICK ForeverUIMarkSmart:LeftButton"] = "Smart mark: skull, then cross, then square..."

-- The smart key's order: the order a tank calls kills in.
module.SMART_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
local SMART_IDLE = 30   -- seconds without a press before it starts over at skull

module.defaults = {
  show = "group",      -- group | always | never
  size = 26,
  spacing = 3,
  vertical = false,
  showClear = true,
  -- What the keys mark: mouseover | target. Under the mouse is how people
  -- mark a pack - hover, press (owner, 25 Sept 2026: "that should be the
  -- standard ... it ships as that").
  keyUnit = "mouseover",
}

local function Settings()
  return ns.db.modules.Markers
end

local bar
local buttons = {}
local keyButtons = {}
module.buttons, module.keyButtons = buttons, keyButtons

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function KeyFor(index)
  return module.KeyFor("ForeverUIMarkKey" .. (index > 0 and index or "Clear"))
end

-- The template's own mark action: type "raidtarget", which mark, and whether
-- to set it or clear it, on the button's unit.
local function MarkAttributes(button, suffix, index, unit)
  button:SetAttribute("type" .. suffix, "raidtarget")
  button:SetAttribute("marker" .. suffix, tostring(index))
  button:SetAttribute("action" .. suffix, index > 0 and "set" or "clear")
  button:SetAttribute("unit" .. suffix, unit)
end
module.MarkAttributes = MarkAttributes

local function MakeButton(name, texture, index, label)
  local button = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
  button:RegisterForClicks("AnyUp")
  -- Act on the release: on this client the "cast on key down" option makes a
  -- secure button wait for a press that a mouse click here never sends.
  button:SetAttribute("useOnKeyDown", false)
  MarkAttributes(button, "1", index, "target")   -- left: this mark on your target
  MarkAttributes(button, "2", 0, "target")       -- right: take your target's mark off
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexture(texture)
  local hover = button:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.2)
  button.label, button.markIndex = label, index
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.label)
    if self.markIndex > 0 then
      GameTooltip:AddLine("Left-click: on your target", 1, 1, 1)
      GameTooltip:AddLine("Right-click: clear your target's mark", 0.8, 0.8, 0.8)
    else
      GameTooltip:AddLine("Click: clear your target's mark", 1, 1, 1)
    end
    local key = KeyFor(self.markIndex)
    GameTooltip:AddLine(key and ("Key: " .. key) or "No key yet - Key Bindings > ForeverUI",
      0.3, 0.76, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return button
end

local function Build()
  bar = CreateFrame("Frame", "ForeverUIMarkerBar", UIParent, "SecureHandlerStateTemplate")
  bar:SetFrameStrata("MEDIUM")
  ns.Skin.Panel(bar, { square = true })
  for i, mark in ipairs(module.MARKS) do
    buttons[i] = MakeButton("ForeverUIMark" .. mark.index, ICON .. mark.index, mark.index, mark.label)
  end
  buttons[#module.MARKS + 1] = MakeButton("ForeverUIMarkClear", CLEAR_ICON, 0, "Clear mark")
  -- The keys' own buttons: never shown, clicked by the key bindings.
  local marks = {}
  for _, mark in ipairs(module.MARKS) do marks[#marks + 1] = mark.index end
  marks[#marks + 1] = 0
  for i, index in ipairs(marks) do
    local key = CreateFrame("Button", "ForeverUIMarkKey" .. (index > 0 and index or "Clear"), UIParent,
      "SecureActionButtonTemplate")
    key:RegisterForClicks("AnyUp", "AnyDown")
    key:Hide()
    key.markIndex = index
    keyButtons[i] = key
  end
  -- Over the party frames' usual spot, where a tank's eyes already are.
  ns.RegisterMover("markers", "Raid markers", bar, { "TOP", "TOP", 0, -140 })
  module.bar = bar
end

-- Size, order and which way the bar runs. Secure buttons: out of combat only.
local function Layout()
  local s = Settings()
  local size, gap = s.size or 26, s.spacing or 3
  local shown = 0
  for i, button in ipairs(buttons) do
    local wanted = i <= #module.MARKS or s.showClear ~= false
    button:SetShown(wanted)
    if wanted then
      button:SetSize(size, size)
      button:ClearAllPoints()
      local offset = 4 + shown * (size + gap)
      if s.vertical then
        button:SetPoint("TOP", bar, "TOP", 0, -offset)
      else
        button:SetPoint("LEFT", bar, "LEFT", offset, 0)
      end
      shown = shown + 1
    end
  end
  local length = 8 + shown * size + (shown - 1) * gap
  local width, height = length, size + 8
  if s.vertical then width, height = size + 8, length end
  bar:SetSize(width, height)
  if ns.UpdateMoverSize then ns.UpdateMoverSize("markers", width, height) end
end

local DRIVERS = { group = "[group] show; hide", always = "show", never = "hide" }

local function ApplyVisibility()
  local rule = DRIVERS[Settings().show or "group"] or DRIVERS.group
  if not module.enabledNow then rule = "hide" end
  if RegisterStateDriver then
    RegisterStateDriver(bar, "visibility", rule)
  else
    bar:SetShown(rule == "show")
  end
  module.visibility = rule
end

---------------------------------------------------------------------------
-- The smart key: skull on the first mob, cross on the next, and so on
---------------------------------------------------------------------------
--
-- Owner, 25 Sept 2026. A secure button again ("raidtarget", action
-- "set-unmarked": a mob that already has a mark keeps it), whose mark moves
-- on to the next after each mob it marks. Moving on means changing the
-- button's attribute, which the game only allows out of combat - so it runs
-- through the order while you mark a pack before the pull; in a fight it
-- keeps the mark it is on. It starts over at skull when a fight ends, or
-- after half a minute without a press.
local smart
local smartStep, smartLast = 1, 0

local function Unmarked(unit)
  if not (UnitExists and ns.Secrets.Bool(UnitExists(unit), false)) then return false end
  local ok, index = pcall(GetRaidTargetIndex, unit)
  if not ok then return false end
  return index == nil
end

local function SmartMark(step)
  smartStep = step
  if smart and not InCombatLockdown() then
    smart:SetAttribute("marker", tostring(module.SMART_ORDER[step]))
  end
end
module.SmartMark = SmartMark

local function BuildSmart()
  smart = CreateFrame("Button", "ForeverUIMarkSmart", UIParent, "SecureActionButtonTemplate")
  smart:RegisterForClicks("AnyDown")
  smart:SetAttribute("useOnKeyDown", true)
  smart:SetAttribute("type", "raidtarget")
  smart:SetAttribute("action", "set-unmarked")
  smart:Hide()
  smart:SetScript("PreClick", function(self)
    local now = GetTime and GetTime() or 0
    if now - smartLast > SMART_IDLE then SmartMark(1) end
    self.fuiWasUnmarked = Unmarked(self:GetAttribute("unit") or "target")
  end)
  smart:SetScript("PostClick", function(self)
    smartLast = GetTime and GetTime() or 0
    if self.fuiWasUnmarked then
      SmartMark(smartStep % #module.SMART_ORDER + 1)
    end
  end)
  SmartMark(1)
  local reset = CreateFrame("Frame")
  reset:RegisterEvent("PLAYER_REGEN_ENABLED")
  reset:SetScript("OnEvent", function() SmartMark(1) end)
  module.smart, module.smartReset = smart, reset
end
module.SmartStep = function() return smartStep end

-- What the keys mark: your target, or whatever the mouse is over.
local function ApplyKeys()
  local unit = Settings().keyUnit == "target" and "target" or "mouseover"
  for _, key in ipairs(keyButtons) do
    MarkAttributes(key, "", key.markIndex, unit)
  end
  if smart then smart:SetAttribute("unit", unit) end
  module.keyUnit = unit
end

---------------------------------------------------------------------------
-- Setting a key from the window: click a tile, press the key
---------------------------------------------------------------------------
--
-- Bound as a click on the mark's hidden button, and written into ForeverUI's
-- own store of keys as well (ActionBars), because this client does not
-- reliably read the game's saved bindings back - the login restore puts
-- these back with the bar keys.
local capture, capturing
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
  LMETA = true, RMETA = true }

local function Command(buttonName)
  return "CLICK " .. buttonName .. ":LeftButton"
end

function module.KeyFor(buttonName)
  if not GetBindingKey then return nil end
  local ok, key = pcall(GetBindingKey, Command(buttonName))
  return ok and key ~= "" and key or nil
end

local function Bars()
  return ns.GetModule("ActionBars")
end

function module.ClearKey(buttonName)
  if InCombatLockdown() then return false end
  local key = module.KeyFor(buttonName)
  while key do
    SetBinding(key, nil)
    key = module.KeyFor(buttonName)
  end
  local bars = Bars()
  if bars and bars.RecordUnbind then bars.RecordUnbind(buttonName) end
  if bars and bars.SaveKeybinds then bars.SaveKeybinds() end
  return true
end

function module.SetKey(buttonName, key)
  if InCombatLockdown() or not SetBindingClick then return false end
  local bars = Bars()
  if bars and bars.PROTECTED_KEYS and bars.PROTECTED_KEYS[key:match("[^-]+$") or key] then
    ns.Print(("%s can't be bound; the game needs it."):format(key))
    return false
  end
  module.ClearKey(buttonName)
  SetBindingClick(key, buttonName, "LeftButton")
  if bars and bars.RecordBind then bars.RecordBind(buttonName, key) end
  if bars and bars.SaveKeybinds then bars.SaveKeybinds() end
  return true
end

local function StopCapture()
  capturing = nil
  if capture then
    capture:EnableKeyboard(false)
    capture:Hide()
  end
  if ns.RefreshOptions then ns.RefreshOptions() end
end
module.StopCapture = StopCapture

function module.StartCapture(buttonName, label)
  if InCombatLockdown() then
    ns.Print("keys can't be set in a fight.")
    return false
  end
  if not capture then
    capture = CreateFrame("Frame", "ForeverUIMarkKeyCapture", UIParent)
    capture:SetFrameStrata("FULLSCREEN_DIALOG")
    capture:SetScript("OnKeyDown", function(self, key)
      if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, false) end
      module.CaptureKey(key)
    end)
  end
  capturing = { button = buttonName, label = label }
  capture:Show()
  capture:EnableKeyboard(true)
  ns.Print(("press a key for |cffffd100%s|r (Esc cancels, Backspace clears)."):format(label))
  if ns.RefreshOptions then ns.RefreshOptions() end
  return true
end

-- What a key press does while a tile is waiting for one.
function module.CaptureKey(key)
  if not capturing or MODIFIER_KEYS[key] then return end
  local target = capturing
  if key == "ESCAPE" then
    StopCapture()
    return
  end
  if key == "BACKSPACE" or key == "DELETE" then
    module.ClearKey(target.button)
    ns.Print(("%s: no key."):format(target.label))
    StopCapture()
    return
  end
  if IsShiftKeyDown and IsShiftKeyDown() then key = "SHIFT-" .. key end
  if IsControlKeyDown and IsControlKeyDown() then key = "CTRL-" .. key end
  if IsAltKeyDown and IsAltKeyDown() then key = "ALT-" .. key end
  if module.SetKey(target.button, key) then
    ns.Print(("%s is now |cffffd100%s|r."):format(target.label, key))
  end
  StopCapture()
end

function module.Capturing()
  return capturing and capturing.button or nil
end

-- A tile for the window: "Skull: F", click to set.
function module.KeyTile(buttonName, label, texture)
  return {
    type = "action", width = 200, texture = texture,
    desc = "Click, then press a key. Esc cancels, Backspace clears.",
    labelFor = function()
      if module.Capturing() == buttonName then return label .. ": press a key..." end
      local key = module.KeyFor(buttonName)
      return ("%s: %s"):format(label, key or "no key")
    end,
    isSelected = function() return module.Capturing() == buttonName end,
    onClick = function() module.StartCapture(buttonName, label) end,
  }
end

function module.KeyTiles()
  return {
    module.KeyTile("ForeverUIMarkSmart", "Smart mark", ICON .. "8"),
    module.KeyTile("ForeverUIMarkKey8", "Skull", ICON .. "8"),
    module.KeyTile("ForeverUIMarkKey7", "Cross", ICON .. "7"),
    module.KeyTile("ForeverUIMarkKey5", "Moon", ICON .. "5"),
    module.KeyTile("ForeverUIMarkKey6", "Square", ICON .. "6"),
    module.KeyTile("ForeverUIMarkKeyClear", "Clear mark", CLEAR_ICON),
  }
end

local function Apply()
  ns.WhenOutOfCombat(function()
    if not bar then
      Build()
      BuildSmart()
      -- The login restore ran before these buttons existed: run it again.
      local bars = ns.GetModule("ActionBars")
      if bars and bars.ApplySavedKeybinds then pcall(bars.ApplySavedKeybinds) end
    end
    Layout()
    ApplyVisibility()
    ApplyKeys()
  end)
end
module.Apply = Apply

function module:OnEnable()
  module.enabledNow = true
  -- Profiles from the first day were saved with "your target" as the
  -- default: moved to the new standard once. A later choice sticks.
  if ns.db and not ns.db.markersMouseDefault then
    ns.db.markersMouseDefault = true
    Settings().keyUnit = "mouseover"
  end
  Apply()
end

function module:OnDisable()
  module.enabledNow = false
  if bar then Apply() end
end

function module:Refresh()
  Apply()
end

local SHOW_CHOICES = function()
  return {
    { label = "When I'm in a group", value = "group" },
    { label = "Always", value = "always" },
    { label = "Never (keys still work)", value = "never" },
  }
end

module.options = {
  { type = "heading", label = "Raid Markers", subtitle = "Skull, cross, moon - on your target in one press",
    icon = "target" },
  { type = "checkbox", switch = true, key = "enabled", label = "Raid markers",
    get = function() return ns.IsModuleEnabled("Markers") end,
    set = function(on) ns.SetModuleEnabled("Markers", on) end },
  { type = "cycler", key = "show", label = "Show the marker bar", choices = SHOW_CHOICES },
  { type = "stepper", key = "size", label = "Icon size", min = 16, max = 48, step = 2 },
  { type = "stepper", key = "spacing", label = "Spacing", min = 0, max = 12, step = 1 },
  { type = "cycler", key = "keyUnit", label = "The keys mark",
    desc = "Under the mouse (the standard): hover the mob or its nameplate and press the key. Your target: press it on whatever you have targeted.",
    choices = function()
      return { { label = "What's under the mouse", value = "mouseover" }, { label = "Your target", value = "target" } }
    end },
  { type = "checkbox", key = "vertical", label = "Run down instead of across" },
  { type = "checkbox", key = "showClear", label = "A clear button at the end" },
  { type = "note", label = "Left-click an icon: that mark on your target. Right-click: clear it. Every mark is also a key: Esc > Options > Keybindings > ForeverUI (\"Mark: Skull\" and so on). On the Tanking grid, a click can put a mark on what that player is fighting (Tank window > Click-casting > Skull / Cross / Moon). Move the bar with /fui move. In a raid you need to be leader or assistant to mark." },
}

-- The keys, set right here: click a tile, press the key.
module.options[#module.options + 1] = { type = "heading", label = "Your keys", columns = 3, icon = "keybinds" }
for _, tile in ipairs(module.KeyTiles()) do
  module.options[#module.options + 1] = tile
end

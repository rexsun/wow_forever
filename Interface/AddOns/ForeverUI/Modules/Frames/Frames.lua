local ADDON_NAME, FUI = ...   -- ForeverUI's addon name + shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- The one global: XML scripts in Frames.xml call into it.
ForeverUIFrames = ns -- luacheck: ignore 131  -- global bridge for Frames.xml button scripts

-- Files, in load order:
--   HealForever.lua      settings, reading + drawing a unit, events, slash command
--   Indicators.lua  incoming heals, dispellable debuffs, HoTs
--   Layout.lua      the drag anchor, party + raid headers, previews, scale
--   Bindings.lua    click-casting
--   Options.lua     the /hf panel

-- Everything that names the addon's folder goes through these two. The folder
-- is not always called HealForever: one client has been seen refusing to
-- restore saved variables for an addon of that exact name while restoring
-- them happily for the same code under any other, so the install may differ.
ns.FOLDER = ADDON_NAME
ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Modules\\Frames\\Media\\"
-- The painted bar backgrounds (ChatGPT art): Media/bg-<name>.tga.
ns.BAR_BG_PATH = ns.MEDIA .. "bg-"

local TICK_INTERVAL = 0.2 -- seconds between range checks and HoT countdown updates
local GREY = 0.35
local PREFIX = "|cff33ff99ForeverUI frames|r"

-- Plain clicks do what Blizzard's frames do until you bind something else.
ns.DEFAULT_BINDINGS = {
  ["1"] = { kind = "target" },
  ["2"] = { kind = "menu" },
}

ns.DEFAULTS = {
  -- Which role these frames are set up for. "healer" is today's HealForever
  -- exactly; "tank" turns on the threat tools below. DPS is not built yet.
  mode = "healer",
  position = { "LEFT", "LEFT", 300, 100 }, -- point, relativePoint, x, y on UIParent
  locked = true,
  bindings = ns.DEFAULT_BINDINGS,
  scale = 1,
  rangeAlpha = 0.4,        -- alpha for out-of-range members
  frameWidth = 120,        -- one unit frame, in pixels
  frameHeight = 36,
  barTexture = ns.MEDIA .. "bar-smooth",
  barBackground = "dark",  -- dark | black | class | none: behind the health fill
  showRole = true,         -- T/H/D marker in the corner
  tanksFirst = false,      -- main tanks stacked at the top whatever the sort
  fontSize = 10,
  frameStyle = "bar",      -- bar (name left, text right) | grid (name top, big % centred)
  healthText = "percent",  -- percent | deficit | current | none
  powerBarHeight = 5,      -- thin mana/energy bar under the health bar; 0 hides it
  classColorNames = false, -- colour the name by class
  barColor = "green",      -- green (every bar the same) | class | role (the grid's colour) | custom
  barCustomColor = { 0.18, 0.72, 0.26 },  -- used when barColor is "custom"
  healthColor = false,     -- blend the bar green -> yellow -> red as health drops
  lowHealthThreshold = 0,  -- percent: at or below it the bar turns lowHealthColor; 0 = off
  lowHealthColor = { 0.95, 0.78, 0.10 },
  critHealthThreshold = 0, -- percent: at or below it the bar turns critHealthColor; 0 = off
  critHealthColor = { 0.90, 0.12, 0.12 },
  barBackgroundColor = { 0.12, 0.12, 0.12 },  -- the "Solid" background
  barGradient = false,     -- shade the fill, lighter at the top
  showLoss = false,        -- the empty part of the bar (health lost) shows in dark red
  animateHeal = false,     -- the bar glides to its new value instead of jumping
  healthAlpha = 100,       -- percent: how solid the health fill is
  nameText = "name",       -- name | class (say "Warrior" instead of who) | none
  nameAnchor = "left",     -- bar style: left | center | right
  healthAnchor = "right",  -- bar style: where the health text sits along the bottom
  nameLength = 0,          -- characters; 0 = the whole name
  healthFontSize = 0,      -- 0 = the same as fontSize
  borderSize = 1,          -- 0 | 1 | 2 pixels of edge around each frame
  borderColor = "black",   -- black | class | white | role (the grid's own colour)
  barOpacity = 100,        -- percent: the background behind the bar
  fillDirection = "left",  -- left | right | up (a standing bar, VuhDo's vertical)
  groupLabels = false,     -- "Group 3" over each raid group
  showMissingBuffs = true, -- a red-edged icon for a buff of yours someone lacks
  missingBuffs = {},       -- ["Spell"] = true|false, overriding the class list
  showThreat = true,       -- red border on whoever a mob is attacking
  roleOrder = { "TANK", "MELEE", "HEALER", "RANGED" }, -- top to bottom when sorting "roles"
  manualRoles = {},        -- ["Player name"] = "TANK" | "HEALER" | "DAMAGER", set by hand
  groupsPerRow = 8,        -- raid groups side by side before wrapping
  horizontal = false,      -- a group is a row of 5 instead of a column
  sortMode = "index",      -- index | name | class | group | role
  sortReverse = false,
  showPets = false,        -- pets alongside the party frames
  useRaidFrames = true,    -- in a raid, show all groups (off: just your own party)
  soloAllGrids = false,    -- solo: every grid you switched on, not just your role's (wixer5851, 27 Sept 2026)
  showIncoming = true,
  -- The overheal lane: the last slice of the bar is kept back so that a heal
  -- bigger than the hole it fills has somewhere to spill. What lands in the
  -- lane IS the waste -- nothing is measured or calculated, which is the only
  -- way to show it while the beta keeps health and incoming heals secret.
  overhealLane = false,
  overhealLanePercent = 15,
  -- The shell: the coloured border and title strip around a grid ("Healing",
  -- "Tanking", "DPS"). Some people want the bars and nothing else.
  showChrome = true,
  -- "cursor" (the game's own), "frame" (beside the grid) or "off".
  frameTooltip = "cursor",
  clickTooltip = true,     -- the tooltip lists what each click casts (HealBot-style)
  showOverheal = true,     -- the part of a heal that lands on a full bar
  showDispel = true,
  showHots = true,
  hotMaxDuration = 60,     -- longest aura that counts as a HoT, in seconds
  auraWatch = {},          -- spells you chose to watch, in priority order
  manualSpells = {},       -- spells you typed in, for clients we can't read
  showRanks = false,       -- list every rank, so a click can cast a lower one
  showTargetDebuffs = true,  -- your own debuffs on whatever you're attacking
  targetIconSize = 30,
  targetPosition = { "CENTER", "CENTER", 0, -180 },
  showWatch = true,        -- the four corner auras from the watch list
  -- How the watched auras and the HoT row are drawn (per role: Modes.lua
  -- LOOK_KEYS). A watched spell can override the size and the timer.
  -- The role marker: a badge or a letter, where, and how big.
  roleStyle = "icon",      -- "icon" or "letter"
  rolePosition = "TOPLEFT", -- a key of ns.ROLE_PLACES (inside or beside the frame)
  roleSize = 12,
  auraSize = 13,           -- pixels, square
  auraTimer = "down",      -- "down", "up" or "off"
  auraTimerSize = 9,       -- the timer's text size
  hotRowCorner = 3,        -- where the HoT row sits: an index into WATCH_CORNERS
  showTargetBorder = true, -- white edge on whoever you have targeted
  fadeRange = true,        -- dim players who are out of range
  -- macOS reverses the wheel by default ("natural scrolling"), and the game
  -- follows it: rolling DOWN arrives as Wheel Up. With this on, the direction
  -- you roll is the binding that fires. On by default on a Mac.
  reverseWheel = (IsMacClient and IsMacClient()) and true or false,
  gameDispels = true,      -- have the game itself draw dispellable debuffs (works in combat)
  gameBuffs = false,       -- have the game draw everyone's buffs/HoTs too (on trial, GameAuras.lua)
  gameHots = true,         -- the HoT row drawn by the game, in combat too (GameHots.lua)
  gameBuffsCombatOnly = true, -- ...only while in combat (ours say more the rest of the time)
  gameBuffsCount = 4,
  gameBuffsSize = 14,
  gameBuffsCorner = "TOPRIGHT",
  inferHots = true,        -- in combat, time my HoTs from my own casts
  learnedDurations = {},   -- ["Renew"] = 15, written down whenever it can be read
  focusScale = 1.3,        -- the focus group, relative to the main frames
  showFocus = true,        -- the separate focus group
  focusNames = {},         -- players picked for it, in order
  focusPosition = { "CENTER", "CENTER", 260, -60 },
  -- Tank-mode settings. Present always, but only tank mode reads them.
  showThreatMeter = true,  -- a thin bar on every frame: their threat on YOUR target
  showThreatPercent = true, -- ...with the number
  looseList = true,        -- loose players stacked at the top, worst first, clickable
  loosePosition = { "CENTER", "CENTER", -300, 160 },
  threatAlert = true,      -- the big AGGRO line in the middle of the screen
  threatSound = true,      -- a warning sound when someone new pulls a mob
  alertLostTarget = true,  -- say so when what you are hitting is on someone else
  alertPosition = { "CENTER", "CENTER", 0, 210 },
  -- DPS: "IT'S ON YOU" when your target turns on you in a group (OnYou.lua).
  onYouAlert = false,
  onYouSound = true,
  onYouPosition = { "CENTER", "CENTER", 0, 170 },
  showTheirTarget = true,  -- who each player is fighting, written on their frame
  minimapButton = false,  -- ForeverUI has its own minimap button; open frame settings via /fui frames
  minimapAngle = 200,      -- where it sits around the minimap
  hideBlizzardParty = true,   -- ForeverUI's frames replace them (owner, 3 Oct 2026)
  hideBlizzardRaid = false,  -- the frames only; Blizzard's raid tools panel stays
  previewRaid = false,     -- unlocked preview shows a 40-player raid instead of a party
}

-- WoW has wipe(); spell it out so the addon doesn't depend on it.
function ns.Wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

function ns.CopyTable(t)
  if type(t) ~= "table" then
    -- Callers pass whatever a settings table held, and most of those
    -- values are plain booleans and numbers. Returning them beats
    -- "bad argument #1 to pairs" from two layers down.
    return t
  end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = type(v) == "table" and ns.CopyTable(v) or v
  end
  return copy
end

-- GetAddOnMetadata moved under C_AddOns on newer clients; Forever has both,
-- older Classic only the global.
function ns.Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return get and get(ADDON_NAME, "Version") or "?"
end

-- What the window shows. The "v" is load-bearing: ForeverUI hides any frame
-- whose text looks like map coordinates, and a bare "0.14.1" does.
function ns.VersionLabel()
  return "v" .. ns.Version()
end

function ns.Print(...)
  print(PREFIX, ...)
end

-- unit -> { [button] = true }. A SET, not one button: with the Healing,
-- Tanking and DPS grids all up, every unit has a button in each, and keeping
-- only the last one meant the other two grids were never refreshed on
-- health events or restyled when a setting changed (found 22 Sept 2026:
-- "player" was tracked for the DPS grid alone).
local buttonsByUnit = {}
-- The focus group shows people who already have a frame in the main group, so
-- a unit can have more than one button. These are the second ones.
local extraButtons = {}

---------------------------------------------------------------------------
-- Combat lockdown: secure frames can't be created, moved or reconfigured
-- in combat. Anything that touches them goes through here.
---------------------------------------------------------------------------

local pending = {}

function ns.WhenOutOfCombat(fn)
  if InCombatLockdown() then
    pending[#pending + 1] = fn
  else
    fn()
  end
end

function ns.HasPending()
  return #pending > 0
end

-- Each job on its own: one that throws is reported and the rest still run
-- (it used to stop the loop, and every job queued after it was dropped).
local function RunPending()
  local queued = pending
  pending = {}
  for i = 1, #queued do
    local ok, err = pcall(queued[i])
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

---------------------------------------------------------------------------
-- Reading a unit and drawing a button are separate so the preview can draw
-- made-up data through exactly the same code as the real frames.
---------------------------------------------------------------------------

function ns.FormatDeficit(missing)
  if missing <= 0 then
    return ""
  elseif missing < 1000 then
    return ("-%d"):format(missing)
  end
  return ("-%.1fk"):format(missing / 1000)
end

-- The alpha a frame should have for range - an alpha, deliberately, not a
-- yes/no. UnitInRange returns a SECRET boolean once you're in a group on
-- Forever, and branching on it (`inRange or not checked`) threw on every
-- refresh. So nothing here ever looks at the answer: a readable one is used
-- directly, a secret one is handed to the game to turn into a number, and if
-- neither works the frame simply isn't faded.
local function RangeAlpha(unit)
  if ns.db.fadeRange == false then
    return 1
  end
  local fade = ns.db.rangeAlpha or 0.4
  if ns.Secrets.Bool(UnitIsUnit(unit, "player"), false) then
    return 1
  end
  local ok, inRange, checkedRange = pcall(UnitInRange, unit)
  if not ok then
    return 1
  end
  -- checkedRange is false when the game can't tell (e.g. different zone);
  -- don't fade in that case.
  if ns.Secrets.Bool(checkedRange, true) == false then
    return 1
  end
  return ns.Secrets.Choose(inRange, 1, fade, 1)
end
ns.RangeAlpha = RangeAlpha

-- Alpha may itself be a secret number, which a widget accepts and Lua must
-- not inspect; a widget that refuses it just stays fully visible.
local function SetRangeAlpha(bar, alpha, button)
  if not pcall(bar.SetAlpha, bar, alpha) then
    bar:SetAlpha(1)
  end
  -- The border and the mana bar hang off the button, not the health bar, so
  -- fading the bar alone left them at full strength: on the healing grid (a
  -- role-coloured border, a mana bar) a player across the room still looked
  -- in range (owner's first dungeon, 25 Sept 2026). They fade with it.
  if button then
    for _, part in ipairs({ button.edge, button.power }) do
      if part and not pcall(part.SetAlpha, part, alpha) then part:SetAlpha(1) end
    end
  end
end

-- Fills `s` in place: this runs on every health tick, so no new tables.
function ns.ReadUnit(unit, s)
  local _, class = UnitClass(unit)
  s.unit = unit
  s.name = UnitName(unit) or "?"
  s.class = class
  s.health = UnitHealth(unit)
  s.healthMax = UnitHealthMax(unit)
  -- Any of these can come back secret in a group; none may be branched on raw.
  local B = ns.Secrets.Bool
  s.offline = not B(UnitIsConnected(unit), true)
  s.ghost = B(UnitIsGhost(unit), false)
  s.dead = not s.ghost and B(UnitIsDead(unit), false)
  s.isTarget = B(UnitIsUnit(unit, "target"), false)
  s.rangeAlpha = RangeAlpha(unit)
  -- Forever can hand back health as a secret value: fine to show on a bar,
  -- fatal to do arithmetic on. This says which we're allowed to do.
  s.canMeasure = ns.Secrets.CanMeasureHealth(unit)
  ns.ReadRole(unit, s)
  ns.ReadThreat(unit, s)
  ns.ReadPower(unit, s)
  ns.ReadIncoming(unit, s)
  ns.ReadDispellable(unit, s)
  ns.ReadHots(unit, s)
  ns.ReadWatched(unit, s)
  ns.ReadMissingBuffs(unit, s)
  if ns.ReadStatus then ns.ReadStatus(unit, s) end
  if ns.GetMode() == "tank" then
    ns.ReadTheirTarget(unit, s)
  end
  return s
end

-- Drawing a number we aren't allowed to read.
--
-- On Forever UnitHealth is secret unconditionally - there is no state in which
-- tainted code may do arithmetic on it. But a FontString will happily accept a
-- secret value (SetText and SetFormattedText are both "AllowedWhenTainted",
-- and Blizzard's own raid frames pass UnitHealth straight into one). So rather
-- than work the number out, ask the game for the finished quantity and hand it
-- over untouched: UnitHealthPercent for a percentage, UnitHealthMissing for a
-- deficit, UnitHealth for the raw figure.
--
-- Returns true when it managed to draw something.
function ns.DrawSecretHealth(fontString, unit, mode)
  if not unit or mode == "none" then
    return false
  end
  if mode == "percent" and UnitHealthPercent then
    -- Diagnostic: show the raw figure, so what the client actually returns
    -- can be read off the screen rather than guessed at.
    if ns.db.debugPercent then
      fontString:SetFormattedText("%.3f", UnitHealthPercent(unit))
      return true
    end
    local curve = ns.Secrets.PercentCurve()
    if curve then
      fontString:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
    else
      fontString:SetFormattedText("%.0f%%", UnitHealthPercent(unit))
    end
    return true
  elseif mode == "current" and UnitHealth then
    fontString:SetText(UnitHealth(unit))
    return true
  elseif mode == "deficit" and UnitHealthMissing then
    -- TruncateWhenZero gives an empty string at full health, which is what a
    -- deficit should read as - and it takes a secret value to do it.
    local truncate = C_StringUtil and C_StringUtil.TruncateWhenZero
    if truncate then
      fontString:SetText(truncate(UnitHealthMissing(unit)))
      return true
    end
  end
  return false
end

-- One colour for everyone is the healer's default: a bar is health, and
-- health is green. Class colours are there for whoever prefers them.
local HEALTH_GREEN = { 0.18, 0.72, 0.26 }

function ns.BarColor(s, button)
  local mode = ns.db.barColor
  if mode == "class" then
    local r, g, b = ns.ClassColor(s.class)
    if r then
      return r, g, b
    end
  elseif mode == "role" then
    -- The grid's own colour: healing green, tanking orange, DPS purple.
    local chrome = ns.ROLE_CHROME and ns.ROLE_CHROME[ns.ButtonGrid(button)]
    local c = chrome and chrome.color
    if c then return c[1], c[2], c[3] end
  elseif mode == "custom" then
    local c = ns.db.barCustomColor
    if type(c) == "table" then return c[1] or 0, c[2] or 0, c[3] or 0 end
  end
  return HEALTH_GREEN[1], HEALTH_GREEN[2], HEALTH_GREEN[3]
end

-- A colour curve: `low` at or below `threshold` percent, `base` above it.
-- Health can't be read on Forever, so the game is handed the curve and the
-- bar takes whatever colour it answers (the unit frames do the same).
local stepCurves = {}
local function StepCurve(threshold, low, base)
  if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
    return nil
  end
  local key = ("%d:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f"):format(threshold, low[1], low[2], low[3], base[1], base[2], base[3])
  if stepCurves[key] ~= nil then
    return stepCurves[key] or nil
  end
  local ok, curve = pcall(function()
    local c = C_CurveUtil.CreateColorCurve()
    local t = threshold / 100
    c:AddPoint(0, CreateColor(low[1], low[2], low[3], 1))
    c:AddPoint(t, CreateColor(low[1], low[2], low[3], 1))
    c:AddPoint(math.min(1, t + 0.001), CreateColor(base[1], base[2], base[3], 1))
    c:AddPoint(1, CreateColor(base[1], base[2], base[3], 1))
    return c
  end)
  stepCurves[key] = ok and curve or false
  return ok and curve or nil
end
ns.StepCurve = StepCurve

-- Three stages: full health in the bar's colour, "low" at or below one
-- threshold, "critical" at or below a lower one. Either can be off (0).
local stageCurves = {}
local function StageCurve(stages, base)
  if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
    return nil
  end
  local parts = { ("%.2f,%.2f,%.2f"):format(base[1], base[2], base[3]) }
  for _, st in ipairs(stages) do
    parts[#parts + 1] = ("%d:%.2f,%.2f,%.2f"):format(st[1], st[2][1], st[2][2], st[2][3])
  end
  local key = table.concat(parts, "|")
  if stageCurves[key] ~= nil then
    return stageCurves[key] or nil
  end
  local ok, curve = pcall(function()
    local c = C_CurveUtil.CreateColorCurve()
    -- stages run lowest threshold first; each colour holds up to its threshold
    local from = 0
    for _, st in ipairs(stages) do
      local t, col = st[1] / 100, st[2]
      c:AddPoint(from, CreateColor(col[1], col[2], col[3], 1))
      c:AddPoint(t, CreateColor(col[1], col[2], col[3], 1))
      from = math.min(1, t + 0.001)
    end
    c:AddPoint(from, CreateColor(base[1], base[2], base[3], 1))
    c:AddPoint(1, CreateColor(base[1], base[2], base[3], 1))
    return c
  end)
  stageCurves[key] = ok and curve or false
  return ok and curve or nil
end

local function HealthStages()
  local stages = {}
  local crit, low = ns.db.critHealthThreshold or 0, ns.db.lowHealthThreshold or 0
  if crit > 0 then stages[#stages + 1] = { crit, ns.db.critHealthColor or { 0.9, 0.12, 0.12 } } end
  if low > 0 and low > crit then stages[#stages + 1] = { low, ns.db.lowHealthColor or { 0.95, 0.78, 0.1 } } end
  return stages
end

-- The bar in its usual colour, or the low / critical colour.
local function PaintLowHealth(bar, s, button)
  local stages = HealthStages()
  if #stages == 0 or s.dead then
    return false
  end
  local r, g, b = ns.BarColor(s, button)
  local curve = UnitHealthPercent and s.unit and StageCurve(stages, { r, g, b })
  if curve then
    bar:SetStatusBarColor(UnitHealthPercent(s.unit, true, curve):GetRGB())
    return true
  end
  -- Readable health (anywhere but Forever): throws on a secret, caught above.
  local pct = s.health / s.healthMax * 100
  for _, st in ipairs(stages) do
    if pct <= st[1] then
      bar:SetStatusBarColor(st[2][1], st[2][2], st[2][3])
      return true
    end
  end
  bar:SetStatusBarColor(r, g, b)
  return true
end

-- Green that turns yellow, then red, as health drops. Health can't be read on
-- Forever, so the game is handed a colour curve and the bar is handed whatever
-- it answers; where health CAN be read the same blend is done by hand. If
-- neither works the bar is simply green.
local function PaintByHealth(bar, s)
  local curve = UnitHealthPercent and s.unit and ns.Secrets.HealthColorCurve()
  if curve then
    local color = UnitHealthPercent(s.unit, true, curve)
    bar:SetStatusBarColor(color:GetRGB())
    return
  end
  local fraction = s.health / s.healthMax -- throws on a secret: caught by the caller
  bar:SetStatusBarColor(ns.Secrets.HealthColorAt(fraction))
end

function ns.PaintBar(bar, s, button)
  if ns.db.healthColor and pcall(PaintByHealth, bar, s) then
    return
  end
  local ok, painted = pcall(PaintLowHealth, bar, s, button)
  if ok and painted then
    return
  end
  bar:SetStatusBarColor(ns.BarColor(s, button))
end

-- "Warrior" rather than "Bigaxe" when what you care about is what they are.
local function ClassLabel(class)
  if issecretvalue and issecretvalue(class) then
    return nil   -- a group member's class can't be looked up (secret): the caller shows the name
  end
  local names = LOCALIZED_CLASS_NAMES_MALE
  if class and names and names[class] then
    return names[class]
  end
  if not class then
    return "?"
  end
  return class:sub(1, 1) .. class:sub(2):lower()
end

-- Trim to n characters without cutting a multi-byte one in half. A secret
-- name (anyone else, in a group) can be shown but not measured or cut --
-- gmatch on it threw and stopped the frame drawing -- so it is shown whole.
function ns.TrimName(name, n)
  if (issecretvalue and issecretvalue(name)) or not name or not n or n <= 0 then
    return name
  end
  local out, count = {}, 0
  for char in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    count = count + 1
    if count > n then
      return table.concat(out)
    end
    out[#out + 1] = char
  end
  return name
end

function ns.NameText(s)
  local mode = ns.db.nameText
  if mode == "none" then
    return ""
  elseif mode == "class" then
    return ns.TrimName(ClassLabel(s.class) or s.name, ns.db.nameLength)
  end
  return ns.TrimName(s.name, ns.db.nameLength)
end

-- The edge's colour when nothing is asking for it (a dispel takes it over).
function ns.EdgeColor(button, s)
  local mode = ns.db.borderColor
  if mode == "class" and s and s.class and ns.ClassColor(s.class) then
    return ns.ClassColor(s.class)
  elseif mode == "white" then
    return 0.9, 0.9, 0.92
  elseif mode == "role" then
    local chrome = ns.ROLE_CHROME and ns.ROLE_CHROME[ns.ButtonGrid(button)]
    if chrome then
      return chrome.color[1], chrome.color[2], chrome.color[3]
    end
  end
  return 0, 0, 0
end

-- Names off, or back to whatever they said before (name or class).
function ns.SetNamesShown(shown)
  if shown then
    ns.SetSetting("nameText", ns.db.nameTextBefore or "name")
  else
    if ns.db.nameText ~= "none" then
      ns.db.nameTextBefore = ns.db.nameText
    end
    ns.SetSetting("nameText", "none")
  end
  return shown
end

-- The health number off, or back to what it said before (percent, deficit...).
function ns.SetHealthTextShown(shown)
  if shown then
    ns.SetSetting("healthText", ns.db.healthTextBefore or "percent")
  else
    if ns.db.healthText ~= "none" then
      ns.db.healthTextBefore = ns.db.healthText
    end
    ns.SetSetting("healthText", "none")
  end
  return shown
end

-- Both at once: nothing written on the bar at all. Clean if either is showing.
function ns.ToggleCleanBars()
  local clean = ns.db.nameText ~= "none" or ns.db.healthText ~= "none"
  ns.SetNamesShown(not clean)
  ns.SetHealthTextShown(not clean)
  return clean
end

-- What the right-hand number says, per the "Health text" setting.
function ns.HealthText(s)
  local mode = ns.db.healthText
  if mode == "none" then
    return "" -- before any arithmetic: the values may be secret
  end
  local max = math.max(s.healthMax or 0, 1)
  if mode == "percent" then
    -- 100% included: a bar with nothing written on it reads as broken.
    return ("%d%%"):format(math.floor(s.health / max * 100 + 0.5))
  elseif mode == "current" then
    return s.health >= 1000 and ("%.1fk"):format(s.health / 1000) or tostring(s.health)
  end
  return ns.FormatDeficit(max - s.health)
end

local function GridPercent(s)
  local max = math.max(s.healthMax or 0, 1)
  return ("%d%%"):format(math.floor(s.health / max * 100 + 0.5))
end

-- "bar": name on the left, health text on the right, like a unit frame.
-- "grid": name across the top, big percentage in the middle, like Grid or Healbot.
local function ApplyStyle(button, s)
  local bar = button.health
  local grid = ns.db.frameStyle == "grid"
  bar.big:SetShown(grid)
  bar.status:SetShown(not grid)
  bar.name:ClearAllPoints()
  if grid then
    bar.name:SetPoint("TOPLEFT", 3, -2)
    bar.name:SetPoint("TOPRIGHT", -3, -2)
    bar.name:SetJustifyH("CENTER")
    local alive = not (s.offline or s.dead or s.ghost)
    if s.offline then
      bar.big:SetText("|cff999999off|r")
    elseif not alive then
      bar.big:SetText("|cffbb3333dead|r")
    elseif ns.db.healthText == "none" then
      -- "Show health text" off means off in this style too: the big number
      -- used to ignore it. Dead and offline above still show - those you need.
      bar.big:SetText("")
    else
      -- The percentage is arithmetic, so it runs protected and falls back to
      -- asking the game for a percentage it won't let us calculate. Even
      -- max health can be a secret value, so nothing is touched up here.
      local ok, text = false, nil
      if s.canMeasure ~= false and not button.measureFailed then
        ok, text = pcall(GridPercent, s)
      end
      if ok then
        bar.big:SetText(text)
      elseif not ns.DrawSecretHealth(bar.big, s.unit, "percent") then
        bar.big:SetText("")
      end
    end
  else
    local at = ns.db.nameAnchor or "left"
    bar.name:SetPoint("TOPLEFT", (at == "left" and ns.db.showRole) and 16 or 4, -4)
    bar.name:SetPoint("TOPRIGHT", at == "right" and -4 or -18, -4)
    bar.name:SetJustifyH(({ left = "LEFT", center = "CENTER", right = "RIGHT" })[at] or "LEFT")
  end
end

local RenderLook
-- Each grid draws with its own role's look (Modes.lua WithLook).
function ns.Render(button, s)
  return ns.WithLook(ns.ButtonGrid(button), RenderLook, button, s)
end

RenderLook = function(button, s)
  local bar = button.health
  bar.name:SetText(ns.NameText(s))
  if ns.db.classColorNames then
    local nr, ng, nb = ns.ClassColor(s.class)
    if nr then
      bar.name:SetTextColor(nr, ng, nb)
    else
      bar.name:SetTextColor(1, 1, 1)
    end
  else
    bar.name:SetTextColor(1, 1, 1)
  end

  if s.offline then
    ns.Secrets.SetBar(bar, s.healthMax, s.healthMax)
    bar:SetStatusBarColor(GREY, GREY, GREY)
    bar.status:SetText(PLAYER_OFFLINE or "Offline")
  elseif s.dead or s.ghost then
    if not (ns.PaintDead and ns.PaintDead(bar, s)) then
      ns.Secrets.SetBar(bar, 0, s.healthMax)
    end
    bar.status:SetText(s.ghost and "Ghost" or (DEAD or "Dead"))
  else
    ns.Secrets.SetBar(bar, s.health, s.healthMax, ns.db.animateHeal)
    ns.PaintBar(bar, s, button)
    -- Asking the client isn't enough: current health can be secret even when
    -- the query says otherwise, so the sum runs protected and a frame that
    -- fails once stops trying.
    if s.canMeasure == false or button.measureFailed then
      if not ns.DrawSecretHealth(bar.status, s.unit, ns.db.healthText) then
        bar.status:SetText("")
      end
    else
      local ok, text = pcall(ns.HealthText, s)
      if ok then
        bar.status:SetText(text)
      else
        button.measureFailed = true
        if not ns.DrawSecretHealth(bar.status, s.unit, ns.db.healthText) then
          bar.status:SetText("")
        end
      end
    end
  end

  ApplyStyle(button, s)
  if ns.db.barBackground == "class" then
    ns.StyleBackground(button, s.class)
  end
  local alive = not (s.offline or s.dead or s.ghost)
  ns.RenderPower(button, s, ns.db.powerBarHeight)
  ns.RenderRole(bar, s, ns.db.showRole)
  if ns.RenderStatus then ns.RenderStatus(button, s) end
  ns.RenderThreat(button, s, ns.db.showThreat)
  -- Incoming heals are drawn by the widgets from the game's own values, so
  -- they need no measuring and don't follow the health text's rule. They did
  -- until 28 Sept 2026: on Forever health is always secret, the percentage
  -- text failed, and that switched the heals off on every frame (CurseForge:
  -- an undead priest, "I do not see it on frames still").
  local canShowIncoming = alive and ns.db.showIncoming and true or false
  if not pcall(ns.RenderIncoming, bar, s, canShowIncoming) then
    pcall(ns.RenderIncoming, bar, s, false)
  end
  -- The lane sits beside the bar, so it is drawn whether or not the frame is
  -- allowed to measure: it never measures anything itself.
  ns.RenderOverhealLane(button, bar, s, canShowIncoming and true or false)
  ns.RenderDispel(button, s, ns.db.showDispel)
  -- The game draws the row when it can (GameHots.lua); ours stays empty then.
  local gameHots = ns.RenderGameHots and ns.RenderGameHots(button, bar, s, alive and ns.db.showHots,
    alive and ns.db.showWatch ~= false)
  ns.RenderHots(bar, s, alive and ns.db.showHots and not gameHots, GetTime())
  ns.RenderWatched(bar, s, alive and ns.db.showWatch ~= false, GetTime())
  ns.PlaceAuras(bar, s)
  if ns.UpdateHotBars then ns.UpdateHotBars(button, GetTime()) end
  ns.RenderMissingBuffs(bar, s, alive and ns.db.showMissingBuffs)
  if ns.GetMode() == "tank" then
    ns.RenderTheirTarget(bar, s, alive and ns.db.showTheirTarget)
  end

  -- Fade the bar, not the secure button itself.
  -- Live frames carry an alpha; the preview's fake units carry a plain flag.
  if s.rangeAlpha ~= nil then
    SetRangeAlpha(bar, s.rangeAlpha, button)
  else
    SetRangeAlpha(bar, s.inRange ~= false and 1 or ns.db.rangeAlpha, button)
  end
  bar.targetBorder:SetShown(ns.db.showTargetBorder ~= false and s.isTarget and true or false)
end

-- A refresh must never throw. It runs from the secure header's attribute path
-- and from every unit event, so one surprise from the client - a new kind of
-- secret value, say - used to mean the same error hundreds of times a second
-- on the player's screen. Now it is recorded once per distinct message, the
-- frame keeps whatever it last drew, and everything else carries on.
local refreshErrors = {}

-- Read AND draw with this frame's own grid's settings. Reading used to run
-- with whichever role was current, so a fight in tank mode read every grid's
-- HoTs with the tank's "keep HoTs showing in combat" (off by default) - and
-- the healer grid went blank in combat while working fine out of it.
local function ReadAndRender(button)
  RenderLook(button, ns.ReadUnit(button.unit, button.state))
end

local function DoRefresh(button)
  ns.WithLook(ns.ButtonGrid(button), ReadAndRender, button)
end

function ns.Refresh(button)
  if not button.unit then
    return
  end
  local ok, err = pcall(DoRefresh, button)
  if not ok then
    local key = tostring(err)
    if not refreshErrors[key] then
      refreshErrors[key] = true
      if ns.RecordError then
        ns.RecordError("frames refresh: " .. key, debugstack and debugstack(2) or "")
      end
    end
  end
end

function ns.ForEachButton(fn)
  for unit, set in pairs(buttonsByUnit) do
    for button in pairs(set) do
      fn(button, unit)
    end
  end
  for button in pairs(extraButtons) do
    fn(button, button.unit)
  end
end

function ns.RefreshAll()
  ns.ForEachButton(function(button) ns.Refresh(button) end)
  if ns.GetMode() == "tank" and ns.UpdateThreatAlert then
    ns.UpdateThreatAlert()
  end
end

-- The cheap, frequent part: range fading and HoT countdown numbers.
local function Tick()
  local now = GetTime()
  local tank = ns.GetMode() == "tank"
  -- The threat meter and pulse belong to the TANK GRID's frames, with the
  -- tank grid's settings, whichever role you're playing: it used to follow
  -- the role you played, so every grid got meters while you tanked and the
  -- tank grid none while you healed.
  local fighting
  ns.ForEachButton(function(button, unit)
    local tankGrid = ns.ButtonGrid(button) == "tank"
    if tankGrid then
      if fighting == nil then fighting = ns.HaveThreatTarget and ns.HaveThreatTarget() or false end
      ns.WithLook("tank", ns.UpdateThreatMeter, button, fighting)
    end
    SetRangeAlpha(button.health, RangeAlpha(unit), button)
    if ns.db.showHots and (button.state.hotCount or 0) > 0 then
      ns.UpdateHotTimers(button.health, button.state, now)
    end
    -- A HoT timed from your cast ends without any event to say so.
    if button.state.inferredUntil and button.state.inferredUntil <= now then
      button.state.inferredUntil = nil
      ns.Refresh(button)
    end
    if button.state.watch then
      ns.UpdateWatchTimers(button.health, button.state, now)
    end
    if ns.UpdateHotBars then ns.UpdateHotBars(button, now) end
    if tankGrid then
      ns.WithLook("tank", ns.PulseThreat, button, now)
    end
  end)
  if tank and ns.TickLooseList then
    ns.TickLooseList()
  end
  ns.UpdateTargetTimers(now)
end

-- Settings that only take effect on the tick (the threat meter) apply at once.
function ns.TickNow()
  Tick()
end

---------------------------------------------------------------------------
-- Button scripts (wired up in Frames.xml)
---------------------------------------------------------------------------

function ns.Button_OnLoad(button)
  button.state = {}
  ns.EnableDrag(button)
  if ns.StyleButton then
    ns.StyleButton(button) -- fonts, shadows, textures: frames are made after login too
  end
end

-- Drag any frame to move them all: the anchor is what actually moves.
function ns.EnableDrag(button)
  if InCombatLockdown() then
    return -- a protected frame mid-combat; it gets picked up when the fight ends
  end
  button:RegisterForDrag("LeftButton")
end

-- Drag the thing that was dragged.
--
-- These used to move ns.anchor -- the grid being CONFIGURED -- so grabbing
-- the tanking grid's handle moved the healing grid instead, and wrote the
-- healing grid's position. With one grid on screen the two were always the
-- same frame; with three they almost never are. `self` is the handle or
-- anchor the player actually took hold of, and it carries its own role.
local function GridOfHandle(self)
  return (self and self.gridRole) or ns.activeGrid or ns.GetMode()
end

function ns.StartMovingFrames(self)
  if ns.db.locked or InCombatLockdown() then
    return
  end
  local target = (self and self.movesGrid) or ns.anchor
  if target then
    target:StartMoving()
  end
end

-- Write down where the frames actually are. Used at the end of a drag, and
-- again before saving: a save that re-applied the stored position would drag
-- the frames back to wherever they were last written, which is exactly what
-- someone who just moved them does not want.
function ns.CapturePosition(frame, role)
  frame = frame or ns.anchor
  if not frame then
    return
  end
  local point, _, relativePoint, x, y = frame:GetPoint()
  if not (point and x and y) then
    return
  end
  local spot = { point, relativePoint, x, y }
  role = role or ns.activeGrid or ns.GetMode()
  -- Written to the grid that moved. The live ns.db.position belongs to the
  -- grid being configured, and is only the same one by coincidence.
  if role == (ns.db.mode or "healer") then
    ns.db.position = spot
  end
  ns.db.modes = ns.db.modes or {}
  ns.db.modes[role] = ns.db.modes[role] or {}
  ns.db.modes[role].position = spot
end

function ns.StopMovingFrames(self)
  local target = (self and self.movesGrid) or ns.anchor
  if not target then
    return
  end
  target:StopMovingOrSizing()
  ns.CapturePosition(target, GridOfHandle(self))
end

-- The group headers tell each button who it shows by setting its "unit"
-- attribute, including mid-combat as people join and leave.
-- Which grid a button belongs to. Stamped on its header when the header was
-- made, so it survives everything: the button can be handed a unit at any
-- moment, including while another grid's settings are loaded.
function ns.ButtonGrid(button)
  if not button then
    return ns.GetMode()
  end
  if not button.gridRole then
    local parent = button.GetParent and button:GetParent()
    local role = parent and parent.gridRole
    if not role then
      -- Not on a grid (the focus frame, a panel button): it is the role
      -- you're playing, asked fresh each time. Caching it kept the old
      -- role's clicks and look after a role switch.
      return ns.PlayingRole()
    end
    button.gridRole = role
  end
  return button.gridRole
end

function ns.Button_OnAttributeChanged(button, name, value)
  if name ~= "unit" then
    return
  end
  -- Bind it here too, rather than trusting the header to have done it: a
  -- frame that draws but doesn't cast is the single worst failure this addon
  -- has, and it reads to everyone as "my settings didn't save".
  ns.BindButton(button)
  local old = button.unit and buttonsByUnit[button.unit]
  if old then
    old[button] = nil
    if not next(old) then buttonsByUnit[button.unit] = nil end
  end
  extraButtons[button] = nil
  button.unit = value
  -- A real unit from a real header: the game-drawn HoT row may serve it.
  button.gameHotsEligible = value ~= nil
  if ns.AttachGameAuras then
    ns.AttachGameAuras(button, value) -- nil detaches
  end
  if value then
    if (ns.IsFocusButton and ns.IsFocusButton(button))
      or (ns.IsPanelUnitButton and ns.IsPanelUnitButton(button)) then
      extraButtons[button] = true
    else
      buttonsByUnit[value] = buttonsByUnit[value] or {}
      buttonsByUnit[value][button] = true
    end
    -- Frames the header creates are XML-sized; match the setting when we can,
    -- at the size of the grid this button belongs to.
    if not InCombatLockdown() and ns.FrameSize then
      button:SetSize(ns.WithLook(ns.ButtonGrid(button), ns.FrameSize))
    end
    ns.Refresh(button)
  end
end

-- Where the unit tooltip goes when you hover a frame. "cursor" is the game's
-- own behaviour (it follows the mouse, which on a grid means it sits on top
-- of the frame you are trying to read); "frame" pins it beside the grid
-- instead; "off" never shows one.
-- What your clicks do on this frame, for the modifiers held right now:
--   Clicks
--   Left            Rejuvenation
--   Right           Regrowth
--   Wheel Up        Lifebloom
--   Hold Shift, Ctrl or Alt for more
-- HealBot's click tooltip (asked for on CurseForge, 23 Sept 2026). Redrawn
-- the moment a modifier goes up or down. Returns how many clicks it listed.
function ns.AddClickLines(tooltip, button)
  local bindings = ns.BindingsFor and ns.BindingsFor(ns.ButtonGrid(button)) or ns.db.bindings or {}
  local prefix = ns.ModifierPrefix()
  local lines = {}
  for _, suffix in ipairs(ns.BINDING_SUFFIXES or {}) do
    local binding = bindings[prefix .. suffix]
    if binding then
      local what = ns.BindingText and ns.BindingText(binding) or (binding.spell or binding.kind or "?")
      if what ~= "" then
        what = what:sub(1, 1):upper() .. what:sub(2)
        lines[#lines + 1] = { ns.DescribeKey(suffix), what }
      end
    end
  end
  -- Anything bound with a modifier: worth a hint when none is held.
  local others = false
  for key in pairs(bindings) do
    if type(key) == "string" and key:find("-", 1, true) then
      others = true
      break
    end
  end
  local held = prefix == "" and "Clicks"
    or (ns.DescribeKey(prefix .. "x"):gsub(" %+ x$", "") .. " + clicks")
  tooltip:AddLine(" ")
  tooltip:AddLine(held, 0.3, 0.76, 1)
  if #lines == 0 then
    tooltip:AddLine("nothing bound", 0.6, 0.6, 0.6)
  end
  for _, line in ipairs(lines) do
    tooltip:AddDoubleLine(line[1], line[2], 0.85, 0.85, 0.85, 1, 0.82, 0)
  end
  if prefix == "" and others then
    tooltip:AddLine("Hold Shift, Ctrl or Alt for more", 0.6, 0.6, 0.6)
  end
  return #lines
end

local hovered
function ns.Button_OnEnter(button)
  button.health.hover:Show()
  hovered = button
  local where = ns.db.frameTooltip or "cursor"
  local clicks = ns.db.clickTooltip ~= false and not button.isWheelButton
  if not button.unit or (where == "off" and not clicks) then
    return
  end
  if where == "frame" or where == "off" then
    -- Beside the button, on whichever side has room, so the grid stays clear.
    local right = button:GetRight() or 0
    local middle = (UIParent:GetWidth() or 0) / 2
    GameTooltip:SetOwner(button, right > middle and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
  else
    GameTooltip_SetDefaultAnchor(GameTooltip, button)
  end
  if where ~= "off" then
    GameTooltip:SetUnit(button.unit)
  end
  if clicks then
    pcall(ns.AddClickLines, GameTooltip, button)
  end
  GameTooltip:Show()
end

function ns.Button_OnLeave(button)
  button.health.hover:Hide()
  if hovered == button then hovered = nil end
  GameTooltip:Hide()
end

-- Shift, Ctrl or Alt pressed or let go over a frame: its click list follows.
local modifierWatch = CreateFrame("Frame")
pcall(modifierWatch.RegisterEvent, modifierWatch, "MODIFIER_STATE_CHANGED")
modifierWatch:SetScript("OnEvent", function()
  local button = hovered
  if button and ns.db and ns.db.clickTooltip ~= false and GameTooltip:IsOwned(button) then
    ns.Button_OnEnter(button)
  end
end)
ns.modifierWatch = modifierWatch

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local UNIT_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_CONNECTION = true,
  UNIT_FLAGS = true,
  UNIT_NAME_UPDATE = true,
  UNIT_HEAL_PREDICTION = true,
  UNIT_POWER_UPDATE = true,
  UNIT_MAXPOWER = true,
  UNIT_DISPLAYPOWER = true,
  UNIT_AURA = true,
  UNIT_THREAT_SITUATION_UPDATE = true,
  UNIT_THREAT_LIST_UPDATE = true,   -- tank mode: mob count / loose detection
  UNIT_TARGET = true,               -- tank mode: what each player is fighting
}

local driver = CreateFrame("Frame")

-- Whether a value is secret depends on the UNIT, not on the frame, so a frame
-- that gave up measuring has to get another go when the roster changes under
-- it. Without this, one refused read stopped that frame ever showing an
-- incoming heal again for the rest of the session. Done before dispatch so it
-- never steals the branch that does the real work for these events.
local RETRY_MEASURE_ON = {
  GROUP_ROSTER_UPDATE = true,
  PLAYER_ENTERING_WORLD = true,
  PLAYER_REGEN_ENABLED = true,
}

driver:SetScript("OnEvent", function(self, event, arg1)
  if ns.booted and RETRY_MEASURE_ON[event] and ns.ForEachButton then
    ns.ForEachButton(function(button) button.measureFailed = nil end)
  end
  if not ns.booted and event ~= "ADDON_LOADED" then
    -- Nothing exists yet and ns.db is a scratch table: anything an event
    -- wrote now (a class default on SPELLS_CHANGED, say) would be lost when
    -- the real profile arrives at PLAYER_LOGIN. Wait for the module to boot.
    return
  end
  if UNIT_EVENTS[event] then
    for button in pairs(buttonsByUnit[arg1] or {}) do
      ns.Refresh(button)
    end
    for extra in pairs(extraButtons) do
      -- "focus" and "party2" can be the same person: the event names one of them.
      if extra.unit == arg1 or (UnitIsUnit and ns.Secrets.Bool(UnitIsUnit(extra.unit, arg1), false)) then
        ns.Refresh(extra)
      end
    end
    if arg1 == "target" and event == "UNIT_AURA" then
      ns.RenderTargetDebuffs()
    end
    if ns.GetMode() == "tank" and ns.UpdateThreatAlert
      and (event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE"
        or event == "UNIT_TARGET") then
      ns.UpdateThreatAlert()
    end
    -- Your target turned on someone: every frame's "has your target" mark
    -- (grouped, threat hidden) is about THAT, and no frame's unit is "target".
    if arg1 == "target" and (event == "UNIT_TARGET" or event == "UNIT_THREAT_LIST_UPDATE") then
      ns.RefreshAll()
    end
  elseif event == "ADDON_LOADED" then
    if arg1 ~= ADDON_NAME then
      return
    end
    self:UnregisterEvent("ADDON_LOADED")
    -- Nothing is built here. The frames boot as a ForeverUI module
    -- (Integration.lua) once ForeverUI has settled which profile this
    -- character is on, so the settings land in that profile and nowhere else.
  elseif event == "PLAYER_LOGOUT" then
    -- The last thing that happens before the game writes the file.
    ns.CapturePosition()
    ns.CaptureTargetPosition()
    ns.CaptureFocusPosition()
    if ns.CapturePanelPositions then ns.CapturePanelPositions() end
    if ns.CaptureBuffWatchPosition then ns.CaptureBuffWatchPosition() end
    if ns.CaptureAlertPosition then ns.CaptureAlertPosition() end
    if ns.CaptureLoosePosition then ns.CaptureLoosePosition() end
  elseif event == "PLAYER_ROLES_ASSIGNED" then
    -- A role picked in the game (Set Role, role check) replaces yours.
    if ns.AdoptGameRole then ns.AdoptGameRole() end
    if ns.db and ns.db.sortMode == "roles" then ns.ApplySorting() end
    ns.RefreshAll()
    if ns.RefreshOptions then ns.RefreshOptions() end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED"
    or event == "PLAYER_TALENT_UPDATE" then
    -- Role changed within the class: ask whether to switch tank <-> healer.
    if ns.CheckRoleFlip then
      ns.CheckRoleFlip()
    end
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
    ns.ForgetBuffList()
    ns.ForgetSpellbook() -- a new rank or a new spell changes what's worth asking for
    -- The spellbook is readable by now, so a healer who has never bound
    -- anything gets their heal on left click instead of a frame that only
    -- targets. Runs once per class per profile and never overrides a choice.
    local spell = ns.ApplyClassDefaults(false)
    if spell then
      ns.Print(("left click casts %s. Change it any time in the Healer window."):format(spell))
    end
    local watched = ns.ApplyStarterWatch(false)
    if watched then
      ns.Print(("watching %d spells on the frames to start with - see the Healer window, Auras."):format(watched))
    end
  elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
    -- The game says outright when auras and cooldowns lock and unlock. Fired
    -- before a restriction bites and after it lifts, so redraw either way.
    ns.Secrets.UnblockAuras()
    ns.RefreshAll()
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns.WheelCombat(true)
    if ns.GameBuffsCombat then ns.GameBuffsCombat() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.WheelCombat(false)
    if ns.GameBuffsCombat then ns.GameBuffsCombat() end
    RunPending()
    ns.ApplyFrameSize() -- catch frames created during the fight
    -- The client can hide health while the fight is on and hand it back
    -- afterwards, so a frame that gave up measuring gets one more go now.
    ns.ForEachButton(function(button) button.measureFailed = nil end)
    -- Anyone who joined mid-fight got a frame that couldn't be bound directly
    -- (attributes are forbidden in combat), so bind everything now.
    ns.ApplyBindings()
    ns.Secrets.UnblockAuras()
    ns.RefreshAll()
    if ns.RefreshOptions then ns.RefreshOptions() end
  else
    -- Roster, target or zone changed: redraw everything.
    if ns.db and ns.db.sortMode == "roles" and event ~= "PLAYER_TARGET_CHANGED" then
      ns.ApplySorting() -- the name list has to name whoever just joined
    end
    ns.RefreshAll()
    ns.RenderTargetDebuffs()
  end
end)

-- HealForever runs on two clients that don't agree on which events exist:
-- LEARNED_SPELL_IN_TAB is gone from Forever, ADDON_RESTRICTION_STATE_CHANGED
-- only exists there. Registering an unknown event throws, so every one of
-- them goes through here, and what the client refused is recorded for
-- /hf selftest rather than thrown in someone's face.
ns.missingEvents = {}

function ns.RegisterEvent(frame, event)
  -- Ask first: a refused registration is reported to the error catchers
  -- even inside pcall (BugGrabber, owner's first dungeon, 25 Sept 2026).
  if C_EventUtils and C_EventUtils.IsEventValid then
    local okAsk, valid = pcall(C_EventUtils.IsEventValid, event)
    if okAsk and valid == false then
      ns.missingEvents[#ns.missingEvents + 1] = event
      return false
    end
  end
  local ok = pcall(frame.RegisterEvent, frame, event)
  if not ok then
    ns.missingEvents[#ns.missingEvents + 1] = event
  end
  return ok
end

for _, event in ipairs({
  "ADDON_LOADED",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "PLAYER_TARGET_CHANGED",
  "PLAYER_FOCUS_CHANGED",
  "PLAYER_LOGIN",
  "PLAYER_LOGOUT",
  "SPELLS_CHANGED",
  "LEARNED_SPELL_IN_TAB",              -- Classic Era only
  "ADDON_RESTRICTION_STATE_CHANGED",   -- Forever only
  "PLAYER_SPECIALIZATION_CHANGED",     -- role flip: ask to switch frames
  "ACTIVE_TALENT_GROUP_CHANGED",       -- dual-spec swap
  "PLAYER_TALENT_UPDATE",
  "PLAYER_ROLES_ASSIGNED",             -- Set Role / role check: the grids follow
}) do
  ns.RegisterEvent(driver, event)
end
for event in pairs(UNIT_EVENTS) do
  ns.RegisterEvent(driver, event)
end

local sinceTick = 0
driver:SetScript("OnUpdate", function(_, elapsed)
  sinceTick = sinceTick + elapsed
  if sinceTick >= TICK_INTERVAL then
    sinceTick = 0
    Tick()
  end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

-- Reached through ForeverUI's own /fui (see Core/Commands.lua): /fui frames,
-- /fui role, etc. The engine no longer registers /hf -- one addon, one door.
function ns.HandleSlash(msg)
  local cmd = (msg or ""):match("^%s*(%S*)"):lower()
  if cmd == "gamebuffs" then
    -- /fui frames gamebuffs [on|off|always|combat]: the game-drawn buffs trial.
    local word = ((msg or ""):match("^%s*%S+%s+(%S+)") or ""):lower()
    if word == "always" then
      ns.SetSetting("gameBuffsCombatOnly", false)
      ns.SetSetting("gameBuffs", true)
    elseif word == "combat" then
      ns.SetSetting("gameBuffsCombatOnly", true)
      ns.SetSetting("gameBuffs", true)
    else
      ns.SetSetting("gameBuffs", word == "on" or (word ~= "off" and not ns.db.gameBuffs))
    end
    local g = ns.gameBuffStats or {}
    ns.Print(("game-drawn buffs %s%s. The game agreed on %d frame%s, refused %d%s."):format(
      ns.db.gameBuffs and "ON" or "off",
      ns.db.gameBuffs and (ns.db.gameBuffsCombatOnly and " (shown in combat)" or " (shown always)") or "",
      g.granted or 0, (g.granted or 0) == 1 and "" or "s", g.refused or 0,
      g.lastError and (" - " .. tostring(g.lastError):sub(1, 80)) or ""))
    return
  elseif cmd == "form" or cmd == "forms" then
    ns.Print("following your form has been replaced by the grids: Healing, Tanking and DPS are independent, any combination is on screen at once, and nothing switches when you shapeshift. /fui grids.")
  elseif cmd == "grids" or cmd == "grid" then
    -- Which grids are ON SCREEN. Not which one you are configuring: a druid
    -- keeps healing and tanking both up and edits whichever he is looking at.
    local word = (msg or ""):match("^%s*%S+%s+(%S+)")
    local pick = ({ heal = "healer", healer = "healer", healing = "healer",
                    tank = "tank", tanking = "tank",
                    dps = "dps", damage = "dps" })[(word or ""):lower()]
    if pick then
      -- Up means on screen now, solo too (ns.GridState).
      local on = not ns.IsGridShown(pick)
      ns.SetGridState(pick, on and "always" or "off")
      ns.Print(("%s grid %s."):format(ns.RoleLabel(pick), on and "up" or "down"))
    elseif word == "status" then
      for _, line in ipairs(ns.GridStatus()) do
        ns.Print(line)
      end
    elseif word == "space" or word == "spread" then
      ns.Print(("spaced %d grids out."):format(ns.SpaceGrids()))
    elseif word == "all" then
      for _, role in ipairs(ns.ROLES) do ns.SetGridState(role, "always") end
      ns.SpaceGrids()
      ns.Print("all three grids up and spaced out.")
    elseif word then
      ns.Print("say /fui grids heal, tank, dps, all, space, or status.")
    end
    local up = {}
    for _, role in ipairs(ns.ShownGrids()) do
      up[#up + 1] = ns.RoleLabel(role)
    end
    ns.Print(#up > 0 and ("up: " .. table.concat(up, ", ")) or "no grids are up.")
  elseif cmd == "" or cmd == "bind" or cmd == "binds" then
    ns.ToggleOptions("bindings")
  elseif cmd == "layout" or cmd == "options" then
    ns.ToggleOptions("layout")
  elseif cmd == "auras" or cmd == "watch" or cmd == "hots" then
    ns.ToggleOptions("auras")
  elseif cmd == "tools" or cmd == "status" or cmd == "panels" or cmd == "buffs" or cmd == "looks"
    or cmd == "appearance" or cmd == "general" or cmd == "indicators" then
    -- Straight to a page: /fui frames panels (and the rest of the VuhDo pages).
    ns.ToggleOptions(cmd)
  elseif cmd == "profile" or cmd == "profiles" then
    -- The frames have no profiles of their own any more: ForeverUI's is theirs.
    if FUI.OpenOptions then
      FUI.OpenOptions("profiles")
    else
      ns.Print(("the frames save into your ForeverUI profile \"%s\" -- /fui profiles to manage it."):format(ns.ActiveProfileName()))
    end
  elseif cmd == "selftest" or cmd == "test" then
    ns.SelfTest()
  elseif cmd == "names" or cmd == "name" then
    local shown = ns.SetNamesShown(ns.db.nameText == "none")
    ns.Print(shown and "names are back on the frames." or "names removed from the frames. /fui frames names puts them back.")
  elseif cmd == "text" or cmd == "numbers" then
    local shown = ns.SetHealthTextShown(ns.db.healthText == "none")
    ns.Print(shown and "health text is back on the bars." or "health text removed. /fui frames text puts it back.")
  elseif cmd == "clean" then
    ns.Print(ns.ToggleCleanBars() and "clean bars: no names, no numbers. /fui frames clean puts them back."
      or "names and health text are back.")
  elseif cmd == "percent" then
    ns.db.debugPercent = not ns.db.debugPercent
    ns.RefreshAll()
    ns.Print(ns.db.debugPercent
      and "health text now shows the raw figure the client returns. Tell me what it reads - 0.873 means a fraction, 87.300 means a percentage. /fui frames percent again to stop."
      or "back to normal health text.")
  elseif cmd == "role" or cmd == "roles" then
    local who, what = (msg or ""):match("^%s*%S+%s+(.-)%s+(%a+)%s*$")
    local roles = { tank = "TANK", healer = "HEALER", heal = "HEALER", melee = "MELEE",
      ranged = "RANGED", caster = "RANGED", dps = "DAMAGER", damage = "DAMAGER",
      auto = false, clear = false, none = false }
    local role = what and roles[what:lower()]
    if not who or role == nil then
      ns.ToggleOptions("roles")
    else
      who = ns.ResolveGroupName(who)
      ns.SetManualRole(who, role or nil)
      ns.Print(role and ("%s is now marked %s."):format(who, what:lower())
        or ("%s is back to automatic."):format(who))
    end
  elseif cmd == "focus" then
    local who = (msg or ""):match("^%s*%S+%s+(.-)%s*$")
    if not who or who == "" then
      ns.ToggleOptions("roles")
    elseif who:lower() == "clear" then
      ns.ClearFocusNames()
      ns.Print("focus group emptied.")
    else
      ns.Print(ns.ToggleFocusName(who) and ("%s added to the focus group."):format(who)
        or ("%s taken out of the focus group."):format(who))
    end
  elseif cmd == "group" or cmd == "sim" then
    -- A pretend group for testing solo (Simulate.lua). Here too, so the
    -- standalone builds have it as /hf group and /tf group.
    local arg = (msg or ""):match("^%s*%S+%s+(%S+)")
    arg = arg and arg:lower() or ""
    if arg == "off" or arg == "stop" then
      ns.StopSimulating()
    else
      ns.SimulateGroup(tonumber(arg) or 5)
    end
  elseif cmd == "trace" then
    -- The flight recorder, for the settings-not-saving hunt. The first line
    -- of a session is the one that matters: it says how many bindings were
    -- on disk BEFORE anything touched them.
    local rest = (msg or ""):match("^%s*%S+%s+(%S+)")
    rest = rest and rest:lower() or ""
    if rest == "off" then
      ns.traceOff = true
      ns.Print("trace off.")
    elseif rest == "on" then
      ns.traceOff = false
      ns.Print("trace on.")
    elseif not (ns.ClearTrace and ns.ShowTrace) then
      ns.Print("the trace isn't part of this build.")   -- the standalone HealForever/TankForever
    elseif rest == "clear" then
      ns.ClearTrace()
    else
      ns.ShowTrace()
    end
  elseif cmd == "why" then
    ns.db.debugHide = not ns.db.debugHide
    ns.Print(ns.db.debugHide
      and "now saying in chat what closes the options window. /fui frames why again to stop."
      or "no longer reporting window closes.")
  elseif cmd == "check" or cmd == "diag" then
    -- The diagnostic. It used to be "status", which the Status page (raid
    -- marker, ready check) already answers to, so it could never run.
    local bound = 0
    for _ in pairs(ns.db.bindings or {}) do bound = bound + 1 end
    local inProfile = FUI.db and FUI.db.frames == ns.db
    ns.Print(("%s mode | %d bindings | saving into ForeverUI profile \"%s\" for %s%s"):format(
      ns.RoleLabel and ns.RoleLabel(ns.GetMode()) or ns.GetMode(), bound,
      ns.ActiveProfileName(), ns.CharacterKey(),
      inProfile and "" or " | NOT WIRED to the profile -- say so, this is the bug"))
  elseif cmd == "debug" then
    -- Which frames exist, who they show and how big they are.
    ns.Print(("profile %s, %dx%d, locked=%s, preview=%s"):format(
      ns.ActiveProfileName(), ns.db.frameWidth, ns.db.frameHeight,
      tostring(ns.db.locked), tostring(not ns.db.locked)))
    for _, header in ipairs(ns.AllHeaders()) do
      local i, child, line = 1, header:GetAttribute("child1"), {}
      while child do
        line[#line + 1] = ("%s(%dx%d)"):format(child:GetAttribute("unit") or "-",
          math.floor(child:GetWidth() + 0.5), math.floor(child:GetHeight() + 0.5))
        i = i + 1
        child = header:GetAttribute("child" .. i)
      end
      ns.Print(("%s: shown=%s, frames: %s"):format(header:GetName() or "?",
        tostring(header:IsShown()), #line > 0 and table.concat(line, " ") or "none"))
    end
  elseif cmd == "move" then
    if InCombatLockdown() then
      ns.Print("can't move frames in combat.")
      return
    end
    ns.SetLockedEverywhere(not ns.db.locked)
    ns.Print(ns.db.locked and "frames locked."
      or "drag the blue box to move the frames; right-click it to reset. /fui frames move when you're done.")
  elseif cmd == "unlock" or cmd == "lock" or cmd == "reset" then
    if InCombatLockdown() then
      ns.Print("can't move frames in combat.")
      return
    end
    if cmd == "reset" then
      ns.ResetPosition()
      ns.Print("position reset.")
    else
      ns.SetLockedEverywhere(cmd == "lock")
      ns.Print(cmd == "lock" and "locked." or "unlocked - drag the green bar.")
    end
  else
    ns.Print("commands: /fui frames (click-casting) | layout | roles | profile | unlock | lock | move | reset | status | percent | why | debug | trace | group | selftest")
  end
end

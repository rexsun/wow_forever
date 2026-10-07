local _, ns = ...

-- Nameplates: the bar over a unit's head, and everything you might want to
-- say about who gets one.
--
-- Three things decide what you see:
--
--   * WHICH UNITS. Friendly players, enemy players and NPCs each have their
--     own rule -- always, only in combat, only when targeted, or never --
--     and a set of filters on top (critters, pets, the dead, anything you
--     can't attack, a name list of your own). What the game itself is asked
--     for goes through CVars; what we decide is ours to show or hide.
--   * HOW IT LOOKS. One box: a name row, a health bar with the percentage
--     inside it, a cast bar with the spell's icon under it. Sizes, colours,
--     fonts and positions are all settings, and each category may have its
--     own colour and scale.
--   * WHAT IT SAYS ON TOP. Your own debuffs (drawn by the game, see below),
--     a threat edge, the classification of an elite or a boss, and the
--     units you single out -- target, focus, bosses, elites -- given their
--     own size and colour.
--
-- Two hard rules on this client run through the whole file. Health is a
-- SECRET VALUE: it can be shown on a bar but not added up, so every sum sits
-- inside ns.Secrets.Measure and the text simply says nothing when the client
-- refuses. And AURAS CANNOT BE READ IN COMBAT, which is exactly when they
-- matter -- so the game's own aura list is moved onto our plate and the game
-- goes on drawing it. We never read one.

local module = ns.RegisterModule({
  name = "Nameplates",
  title = "Nameplates",
})

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- The four answers to "when does this get a plate?".
local RULES = { "always", "combat", "target", "never" }
module.RULES = RULES

-- Kick priority colours (cast bars and KICK tags).
local KICK_HEAL = { 0.25, 0.95, 0.40 }
local KICK_IMPORTANT = { 1.00, 0.25, 0.20 }

module.defaults = {
  enabled = true,

  -- Who gets a plate
  showFriendly   = "always",   -- always | combat | target | never
  showEnemy      = "always",
  showNPC        = "always",
  showMinor      = true,       -- the game's "minor" mobs - many starting-zone ones
  showTotems     = true,
  showPersonal   = false,      -- the personal resource plate under your feet
  viewDistance   = 60,
  maxPlates      = 40,
  hideInCombat   = false,
  hideInInstances = false,
  hideWithUI     = true,       -- follow Alt-Z: ours are under the world frame

  -- Fading
  fadeNonTargets = true,
  nonTargetAlpha = 60,
  outOfRangeAlpha = 35,

  -- The box
  width = 150,
  height = 20,
  verticalOffset = 0,

  -- Text
  fontSize = 10,
  outline = "",                -- "" | OUTLINE | THICKOUTLINE
  showName = true,
  nameInside = false,          -- the name inside the bar rather than above it
  showLevel = true,
  showClassification = true,   -- + for an elite, R for a rare, B for a boss
  truncateNames = true,
  nameLength = 18,
  showPercent = true,

  -- The health bar
  classColor = true,           -- colour players by class
  lowHealthThreshold = 20,
  flashLowHealth = true,
  healthPrediction = true,
  friendlyColor   = { 0.31, 0.65, 0.35 },
  neutralColor    = { 0.85, 0.77, 0.36 },
  unfriendlyColor = { 0.82, 0.45, 0.22 },
  enemyColor      = { 0.78, 0.25, 0.25 },
  showTapped      = true,
  tappedColor     = { 0.45, 0.45, 0.48 },

  -- The cast bar
  castBars = true,
  castHeight = 18,
  castShowName = true,
  castShowTime = true,
  castShowIcon = true,
  castShowUninterruptible = true,
  castKickPriority = true,   -- heals green, important red, with a KICK tag on the plate
  latency = 0.15,

  -- On top
  showDebuffs = true,          -- your own, drawn by the game
  auraScale = 1.0,
  showThreat = true,

  -- Name-only
  friendlyNameOnly = false,
  -- Altiokis on CurseForge, 28 Sept 2026: "How do we get the job roles back
  -- on the nameplates ... can't tell the hunter trainer from the druid
  -- trainer." The <Hunter Trainer> line under an NPC's plate.
  npcTitles = true,
  -- Gnatz_0815 on CurseForge: "a counter on the nameplate how many kills are
  -- left". The count beside a mob your quests still need, from QuestForever.
  questProgress = true,

  -- Filters
  hideCritters = true,
  hidePets = false,
  hideDead = true,
  hideUnattackable = false,
  onlyTarget = false,
  blacklist = "",
  whitelist = "",

  -- Singled out
  targetScale = 1.15,
  targetBorder = true,
  focusScale = 1.10,
  bossScale = 1.20,
  eliteScale = 1.10,
  friendlyScale = 1.00,
  enemyScale = 1.00,
  npcScale = 1.00,

  preset = nil,
  stoodDown = nil,   -- the nameplate addon we stepped aside for, once

  mockupDone = true,
}

local plates = {}   -- unit token -> our frame
local driver

local function Settings()
  return ns.db.modules.Nameplates
end

---------------------------------------------------------------------------
-- Asking the game for the right plates
---------------------------------------------------------------------------

-- Everything the game itself decides is a CVar. Each one is set inside a
-- pcall: a client that has never heard of one raises rather than shrugging,
-- and half of these come and go between builds.
local function Set(cvar, value)
  ns.SetCVar(cvar, value)
end

local function Read(cvar)
  if not GetCVar then return nil end
  local ok, value = pcall(GetCVar, cvar)
  if ok then return value end
  return nil
end

-- What each CVar said before we ever touched it, remembered once. Turning
-- the module off puts these back, so a client handed to Plater is the
-- client Plater would have found.
local CVARS = {
  "nameplateShowFriends", "nameplateShowEnemies", "nameplateShowFriendlyNpcs",
  "nameplateShowEnemyMinus", "nameplateShowEnemyTotems", "nameplateShowFriendlyTotems",
  "nameplateShowSelf", "nameplateMaxDistance", "nameplateAuraScale",
}
module.CVARS = CVARS

local function RememberCVars()
  if module.savedCVars then
    return module.savedCVars
  end
  local saved = {}
  for _, cvar in ipairs(CVARS) do
    saved[cvar] = Read(cvar)
  end
  module.savedCVars = saved
  return saved
end

function module.ApplyCVars()
  -- Off means off: a disabled module must not keep steering the game, or
  -- whatever took the job would find its own settings quietly rewritten.
  if not ns.IsModuleEnabled("Nameplates") then
    return false
  end
  RememberCVars()
  local settings = Settings()
  local function on(rule) return rule ~= "never" and "1" or "0" end
  Set("nameplateShowFriends", on(settings.showFriendly))
  Set("nameplateShowEnemies", on(settings.showEnemy))
  Set("nameplateShowFriendlyNpcs", settings.showNPC ~= "never" and "1" or "0")
  Set("nameplateShowEnemyMinus", settings.showMinor and "1" or "0")
  Set("nameplateShowEnemyTotems", settings.showTotems and "1" or "0")
  Set("nameplateShowFriendlyTotems", settings.showTotems and "1" or "0")
  Set("nameplateShowSelf", settings.showPersonal and "1" or "0")
  Set("nameplateMaxDistance", tostring(settings.viewDistance or 60))
  Set("nameplateAuraScale", tostring(settings.auraScale or 1))
  return true
end

function module.RestoreCVars()
  local saved = module.savedCVars
  if not saved then
    return false
  end
  for _, cvar in ipairs(CVARS) do
    if saved[cvar] ~= nil then
      Set(cvar, saved[cvar])
    end
  end
  module.savedCVars = nil
  return true
end

-- A plate that belongs to a thing, not a creature: a mining vein, a herb,
-- a chest. The game gives those plates when you can interact with them (the
-- controller turns that on), and ForeverUI drew them as a mob with a health
-- bar (Altiokis on CurseForge, 28 Sept 2026: "mining node has the nameplate
-- of a monster, instead of what kind of mining node it is"). They show as
-- their name alone.
local function IsObject(unit)
  if not (unit and UnitIsGameObject) then return false end
  local ok, value = pcall(UnitIsGameObject, unit)
  return ok and ns.Secrets.Bool(value, false) or false
end
module.IsObject = IsObject

-- Friendly player, enemy player, or NPC: the three the rules are written
-- for. Read through the guard -- in a group these can come back secret.
local function Category(unit)
  local isPlayer = ns.Secrets.Bool(UnitIsPlayer and UnitIsPlayer(unit), false)
  if not isPlayer then
    return "npc"
  end
  if ns.Secrets.Bool(UnitIsFriend and UnitIsFriend("player", unit), false) then
    return "friendly"
  end
  return "enemy"
end
module.Category = Category

local function Rule(category)
  local settings = Settings()
  if category == "friendly" then return settings.showFriendly end
  if category == "enemy" then return settings.showEnemy end
  return settings.showNPC
end

-- A list of names typed into a filter box: "Gnoll, Training Dummy".
local function Matches(list, name)
  if not list or list == "" or not name then
    return false
  end
  local lowered = name:lower()
  for raw in list:gmatch("[^,]+") do
    local piece = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if piece ~= "" and lowered:find(piece, 1, true) then
      return true
    end
  end
  return false
end
module.Matches = Matches

local function Query(fn, ...)
  if not fn then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- Everything that can send a plate away, in the order it costs least to
-- ask. Returns false and the reason, which /fui plates prints.
function module.ShouldShow(unit)
  if not unit then
    return false, "no unit"
  end
  local settings = Settings()
  local name = ns.Secrets.String(Query(UnitName, unit))

  -- A name on the whitelist is shown whatever else is true.
  if type(name) == "string" and Matches(settings.whitelist, name) then
    return true, "whitelisted"
  end
  if type(name) == "string" and Matches(settings.blacklist, name) then
    return false, "blacklisted"
  end

  if settings.hideInCombat and InCombatLockdown() then
    return false, "hidden in combat"
  end
  if settings.hideInInstances and IsInInstance and select(1, Query(IsInInstance)) then
    return false, "hidden in instances"
  end
  if settings.onlyTarget and not ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(unit, "target"), false) then
    return false, "not your target"
  end

  local classification = ns.Secrets.String(Query(UnitClassification, unit))
  -- A critter is a Critter. "Minus" is the game's minor mobs, which include
  -- many starting-zone quest mobs: those follow "Show minor units", not the
  -- critter switch (owner, Deathknell, 26 Sept 2026).
  if settings.hideCritters then
    local creature = ns.Secrets.String(Query(UnitCreatureType, unit))
    if creature == "Critter" then
      return false, "critter"
    end
  end
  if not settings.showMinor and classification == "minus" then
    return false, "minor unit"
  end
  if settings.hidePets and ns.Secrets.Bool(UnitPlayerControlled and UnitPlayerControlled(unit), false)
    and not ns.Secrets.Bool(UnitIsPlayer and UnitIsPlayer(unit), false) then
    return false, "someone's pet"
  end
  if settings.hideDead and ns.Secrets.Bool(UnitIsDead and UnitIsDead(unit), false) then
    return false, "dead"
  end
  if settings.hideUnattackable and UnitCanAttack
    and not ns.Secrets.Bool(UnitCanAttack("player", unit), true) then
    return false, "can't be attacked"
  end

  local rule = Rule(Category(unit))
  if rule == "never" then
    return false, "rule: never"
  elseif rule == "combat" and not InCombatLockdown()
    and not ns.Secrets.Bool(UnitAffectingCombat and UnitAffectingCombat(unit), false) then
    return false, "rule: only in combat"
  elseif rule == "target" and not ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(unit, "target"), false) then
    return false, "rule: only when targeted"
  end
  return true, "shown"
end

---------------------------------------------------------------------------
-- Colour and size
---------------------------------------------------------------------------

-- Pure black is treated as "not set".
--
-- A health bar is drawn on a near-black background, so black is
-- indistinguishable from broken -- and it HAS been broken: a bad standard
-- shipped every colour as {0,0,0} and that black was then saved into real
-- profiles, leaving every nameplate uncoloured with no error anywhere.
-- Nobody chooses black here, so a saved black falls through to the default
-- and the profile heals itself the next time a plate is drawn.
local function Colour(key, fallback)
  local c = Settings()[key]
  if type(c) == "table" and c[1] then
    local black = (c[1] == 0) and ((c[2] or 0) == 0) and ((c[3] or 0) == 0)
    if not black then
      return c[1], c[2] or 0, c[3] or 0
    end
  end
  return ns.Colors.Get("reaction", fallback)
end

-- What colour a plate's bar is, and why.
--
-- The game grades a unit's attitude on its own scale, and the answer is only
-- useful if it is read the same way the game reads it:
--
--   5 and up  friendly     green
--   4         neutral      yellow    leave it alone, it leaves you alone
--   3         unfriendly   orange    it won't start anything; you can
--   1-2       hostile      red       it attacks on sight
--
-- Two things sit on top of that. A unit somebody else hit first goes grey,
-- because there is no experience and no loot left in it for you -- that is
-- what the game's own grey bar means, and it is worth knowing before you
-- spend a fight on it. And a player is drawn in their class colour instead,
-- if you asked for that.
--
-- Collapsing the middle of the scale is what made a Cloudrunner red: it is
-- unfriendly, not hostile, and it never had any intention of attacking.
-- Nothing here guesses "hostile" any more. When the attitude cannot be read
-- at all the questions that CAN be answered decide it, and the last resort
-- is neutral, which claims the least.
local function Reason(unit)
  local settings = Settings()

  if settings.showTapped ~= false
    and not ns.Secrets.Bool(UnitIsPlayer and UnitIsPlayer(unit), false)
    and ns.Secrets.Bool(UnitIsTapDenied and UnitIsTapDenied(unit), false) then
    return "tappedColor", "tapped", "someone else hit it first"
  end

  if settings.classColor and ns.Secrets.Bool(UnitIsPlayer and UnitIsPlayer(unit), false) then
    local _, class = UnitClass(unit)
    if class then
      return nil, class, "player, class coloured"
    end
  end

  local reaction = ns.Secrets.Number(Query(UnitReaction, "player", unit))
  if reaction then
    if reaction >= 5 then
      return "friendlyColor", "friendly", "reaction " .. reaction .. ", friendly"
    elseif reaction == 4 then
      return "neutralColor", "neutral", "reaction 4, neutral"
    elseif reaction == 3 then
      return "unfriendlyColor", "unfriendly", "reaction 3, unfriendly"
    end
    return "enemyColor", "hostile", "reaction " .. reaction .. ", hostile"
  end

  -- The attitude is not on offer. Ask what is.
  if ns.Secrets.Bool(UnitIsEnemy and UnitIsEnemy("player", unit), false) then
    return "enemyColor", "hostile", "no reaction, but it is an enemy"
  end
  if ns.Secrets.Bool(UnitIsFriend and UnitIsFriend("player", unit), false) then
    return "friendlyColor", "friendly", "no reaction, but it is a friend"
  end
  if UnitCanAttack and ns.Secrets.Bool(UnitCanAttack("player", unit), false) then
    return "neutralColor", "neutral", "no reaction, attackable but not an enemy"
  end
  return "neutralColor", "neutral", "nothing could be read"
end
module.Reason = Reason

local function BarColor(unit)
  local key, fallback = Reason(unit)
  if not key then
    return ns.Colors.Class(fallback, true)   -- a player, in their class colour (painted only)
  end
  return Colour(key, fallback)
end
module.BarColor = BarColor

-- What a plate actually resolved to, for when the bars come out the wrong
-- colour and the code all reads correctly. Reports the unit's category, the
-- colour key Reason picked, the three numbers that reached the bar, and what
-- the bar is drawn with -- a StatusBar with no texture shows nothing however
-- good its colour is.
function module.Probe(unit)
  unit = unit or "target"
  local lines = {}
  if not (UnitExists and UnitExists(unit)) then
    return { "nothing is targeted -- target something and try again." }
  end
  local name = (UnitName and UnitName(unit)) or "?"
  local key, fallback, why = Reason(unit)
  local r, g, b = BarColor(unit)
  lines[#lines + 1] = ("%s [%s]: key=%s fallback=%s (%s)"):format(
    name, tostring(Category(unit)), tostring(key), tostring(fallback), tostring(why))
  lines[#lines + 1] = ("colour -> r=%s g=%s b=%s"):format(
    tostring(r), tostring(g), tostring(b))
  lines[#lines + 1] = ("setting[%s] = %s"):format(
    tostring(key), type(key and Settings()[key]))

  -- Plates are keyed by nameplate token, not by "target", so find the one
  -- whose unit IS this one.
  local plate
  for token, candidate in pairs(plates) do
    if UnitIsUnit and UnitIsUnit(token, unit) then
      plate = candidate
      break
    end
  end
  if plate and plate.health then
    local min, max = plate.health:GetMinMaxValues()
    lines[#lines + 1] = ("bar: value=%s range=%s..%s size=%dx%d shown=%s"):format(
      tostring(plate.health:GetValue()), tostring(min), tostring(max),
      plate.health:GetWidth() or 0, plate.health:GetHeight() or 0,
      tostring(plate.health:IsShown()))
    local tex = plate.health.GetStatusBarTexture and plate.health:GetStatusBarTexture()
    lines[#lines + 1] = ("texture: %s path=%s"):format(
      tex and "yes" or "NONE",
      tostring(ns.Media.StatusBarTexture()))
    if tex and tex.GetVertexColor then
      local tr, tg, tb, ta = tex:GetVertexColor()
      lines[#lines + 1] = ("texture colour: %s %s %s alpha %s"):format(
        tostring(tr), tostring(tg), tostring(tb), tostring(ta))
    end
  else
    lines[#lines + 1] = "no ForeverUI plate is attached to that unit right now."
  end
  return lines
end

-- How big this one plate is: its category's size, and then whatever it is
-- singled out as -- your target, your focus, a boss, an elite. The biggest
-- claim wins rather than multiplying them together.
local CLASSIFICATION_MARK = {
  elite = "+", rareelite = "R+", rare = "R", worldboss = "B",
}

function module.ScaleFor(unit)
  local settings = Settings()
  local category = Category(unit)
  local scale = (category == "friendly" and settings.friendlyScale)
    or (category == "enemy" and settings.enemyScale)
    or settings.npcScale or 1
  local classification = ns.Secrets.String(Query(UnitClassification, unit))
  if classification == "worldboss" then
    scale = math.max(scale, settings.bossScale or 1)
  elseif classification == "elite" or classification == "rareelite" then
    scale = math.max(scale, settings.eliteScale or 1)
  end
  if ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(unit, "focus"), false) then
    scale = math.max(scale, settings.focusScale or 1)
  end
  if ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(unit, "target"), false) then
    scale = math.max(scale, settings.targetScale or 1)
  end
  return scale
end

---------------------------------------------------------------------------
-- Building one plate
---------------------------------------------------------------------------

local NAME_ROW = 16
local PAD = 4

-- One dark box with the blue edge: the name on the left and the level on
-- the right of a top row, a flat health bar under them with the percentage
-- inside it, and below the box a cast bar -- spell name left, time right --
-- with the spell's icon in its own small box beside it.
local function Build(parent)
  local ui = ns.Colors.ui
  local plate = CreateFrame("Frame", nil, parent)
  ns.Skin.Panel(plate, { color = { 0.03, 0.03, 0.05, 0.92 }, borderColor = ui.accent, square = true })

  plate.name = plate:CreateFontString(nil, "OVERLAY")
  plate.name:SetJustifyH("LEFT")
  plate.level = plate:CreateFontString(nil, "OVERLAY")
  plate.level:SetJustifyH("RIGHT")
  -- An NPC's job, <Hunter Trainer>, under the plate as the game shows it.
  plate.title = plate:CreateFontString(nil, "OVERLAY")
  plate.title:SetJustifyH("CENTER")
  plate.title:SetPoint("TOP", plate, "BOTTOM", 0, -1)
  plate.title:Hide()
  -- Quest progress (QuestForever): "3/10" right of the plate, on a mob your
  -- quests still need.
  plate.quest = plate:CreateFontString(nil, "OVERLAY")
  plate.quest:SetJustifyH("LEFT")
  plate.quest:SetPoint("LEFT", plate, "RIGHT", 4, 0)
  plate.quest:Hide()
  -- The raid mark, left of the plate where a tank's eye finds it.
  plate.raidMark = plate:CreateTexture(nil, "OVERLAY")
  plate.raidMark:SetSize(22, 22)
  plate.raidMark:SetPoint("RIGHT", plate, "LEFT", -3, 0)
  plate.raidMark:Hide()

  plate.health = CreateFrame("StatusBar", nil, plate)
  plate.health.bg = plate.health:CreateTexture(nil, "BACKGROUND")
  plate.health.bg:SetAllPoints()
  plate.health.bg:SetColorTexture(0.10, 0.10, 0.12, 1)

  -- The heal coming in, drawn ahead of the fill in a lighter shade.
  plate.incoming = plate.health:CreateTexture(nil, "ARTWORK")
  plate.incoming:SetColorTexture(0.35, 1.00, 0.45, 0.35)
  plate.incoming:Hide()

  plate.percent = plate.health:CreateFontString(nil, "OVERLAY")
  plate.percent:SetPoint("RIGHT", plate.health, "RIGHT", -4, 0)
  plate.percent:SetJustifyH("RIGHT")

  plate.cast = CreateFrame("StatusBar", nil, plate)
  plate.cast:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, -4)
  ns.Skin.Panel(plate.cast, { color = { 0.03, 0.03, 0.05, 0.92 }, borderColor = ui.accent, square = true })
  plate.cast.text = plate.cast:CreateFontString(nil, "OVERLAY")
  plate.cast.text:SetPoint("LEFT", plate.cast, "LEFT", 6, 0)
  plate.cast.text:SetJustifyH("LEFT")
  plate.cast.timer = plate.cast:CreateFontString(nil, "OVERLAY")
  plate.cast.timer:SetPoint("RIGHT", plate.cast, "RIGHT", -6, 0)
  plate.cast.timer:SetJustifyH("RIGHT")
  plate.cast.text:SetPoint("RIGHT", plate.cast.timer, "LEFT", -4, 0)
  -- The bit of the cast you can no longer interrupt: your latency, drawn at
  -- the end of the bar so you know when to stop trying.
  plate.cast.lag = plate.cast:CreateTexture(nil, "OVERLAY")
  plate.cast.lag:SetColorTexture(0.9, 0.3, 0.3, 0.45)
  plate.cast.lag:Hide()
  plate.cast.iconBox = CreateFrame("Frame", nil, plate.cast)
  plate.cast.iconBox:SetPoint("TOPLEFT", plate.cast, "TOPRIGHT", 4, 0)
  ns.Skin.Panel(plate.cast.iconBox, { color = { 0.03, 0.03, 0.05, 0.92 }, borderColor = ui.accent, square = true })
  plate.cast.icon = plate.cast.iconBox:CreateTexture(nil, "ARTWORK")
  plate.cast.icon:SetPoint("TOPLEFT", 1, -1)
  plate.cast.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  plate.cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- Kick priority tags, left of the cast bar: one for heals, one for
  -- important casts (outer: not a heal, inner: important - alphas multiply),
  -- faded in and out by the game's own secret answers (KickPriority below).
  local function Tag(color)
    local outer = CreateFrame("Frame", nil, plate.cast)
    outer:SetPoint("RIGHT", plate.cast, "LEFT", -4, 0)
    outer:SetSize(40, 18)
    local inner = CreateFrame("Frame", nil, outer)
    inner:SetAllPoints()
    local bg = inner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(color[1], color[2], color[3], 0.95)
    local text = inner:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", 0, 0)
    ns.Media.SetFont(text, "aura")
    text:SetTextColor(0, 0, 0)
    text:SetText("KICK")
    outer.inner = inner
    outer:SetAlpha(0)
    return outer
  end
  plate.cast.kickHeal = Tag(KICK_HEAL)
  plate.cast.kickImportant = Tag(KICK_IMPORTANT)
  plate.cast:Hide()

  return plate
end
module.Build = Build

---------------------------------------------------------------------------
-- Blizzard's plate, and the auras we borrow from it
---------------------------------------------------------------------------

-- YOUR DEBUFFS. An addon can't read auras in a fight on Forever, but
-- Blizzard's plate still can: its AurasFrame goes on listing your Moonfire
-- and Faerie Fire on a hidden frame. So that one child is moved onto our
-- plate -- the game keeps drawing it, we only say where -- and hung above
-- the box. The unit frames are pooled and reused, so this is done again on
-- every plate that appears, and Blizzard's own re-anchor is followed by ours.
local function AnchorDebuffs(auras, plate)
  local list = auras and rawget(auras, "DebuffListFrame")
  if not list or not plate or not list.SetPoint then return end
  pcall(list.ClearAllPoints, list)
  pcall(list.SetPoint, list, "BOTTOMLEFT", plate, "TOPLEFT", 0, 4)
end

-- Blizzard's plate is made invisible, never Hidden. Hide() from here runs
-- the plate's own OnHide (CompactUnitFrame_OnHide) inside our call, and that
-- re-registers the plate's unit events -- health, threat, range -- as ours.
-- From then on every one of those events reached Blizzard's code wearing
-- ForeverUI's name, and the first threat update in a fight compared a secret
-- colour: "CompactUnitFrame.lua:699: attempt to compare local 'oldR' (a
-- secret number value, while execution tainted by 'ForeverUI')", and the
-- range check's "secret boolean" after it (BAP2521 on CurseForge, 1 Oct
-- 2026: "Entering combat, seems to be when the enemy targets me"). Alpha is
-- a plain C call with no script behind it. Blizzard paints alpha back on its
-- range check, so every SetAlpha it makes is followed by ours, back to 0.
local zeroing = false
local function KeepClear(self)
  if zeroing or not rawget(self, "fuiHidden") then
    return
  end
  zeroing = true
  pcall(self.SetAlpha, self, 0)
  zeroing = false
end
module.KeepClear = KeepClear

local function HideBlizzardPlate(base, plate)
  local blizzard = base and rawget(base, "UnitFrame")
  if not blizzard or not blizzard.SetAlpha then
    return false
  end
  blizzard.fuiHidden = true
  if hooksecurefunc and not rawget(blizzard, "fuiAlphaHook") then
    blizzard.fuiAlphaHook = true
    hooksecurefunc(blizzard, "SetAlpha", KeepClear)
  end
  KeepClear(blizzard)
  local auras = rawget(blizzard, "AurasFrame")
  if auras and plate then
    if Settings().showDebuffs ~= false then
      if auras.SetParent then pcall(auras.SetParent, auras, plate) end
      auras.fuiPlate = plate
      AnchorDebuffs(auras, plate)
      if auras.SetAlpha then auras:SetAlpha(1) end
      if hooksecurefunc and blizzard.ApplyFrameOptions and not rawget(blizzard, "fuiAuraHook") then
        blizzard.fuiAuraHook = true
        hooksecurefunc(blizzard, "ApplyFrameOptions", function(self)
          local a = rawget(self, "AurasFrame")
          if a and rawget(a, "fuiPlate") then AnchorDebuffs(a, a.fuiPlate) end
        end)
      end
    elseif rawget(auras, "fuiPlate") then
      if auras.SetParent then pcall(auras.SetParent, auras, blizzard) end
      auras.fuiPlate = nil
    end
  end
  return true
end
module.HideBlizzardPlate = HideBlizzardPlate

-- The other direction, and the whole point of the off switch: hand the
-- plate back exactly as it was found. Blizzard's frame is shown again at
-- full alpha, the aura list goes home, and the hook that re-anchors it is
-- told to stand down by clearing the plate it was pointing at. What is left
-- behind is a plate the game -- or Plater, or anything else -- can own.
local function RestoreBlizzardPlate(base, plate)
  if plate then
    plate:Hide()
  end
  local blizzard = base and rawget(base, "UnitFrame")
  if not blizzard then
    return false
  end
  local auras = rawget(blizzard, "AurasFrame")
  if auras and rawget(auras, "fuiPlate") then
    auras.fuiPlate = nil            -- the ApplyFrameOptions hook now does nothing
    if auras.SetParent then pcall(auras.SetParent, auras, blizzard) end
    -- Its list goes back above Blizzard's own name; Blizzard's next
    -- ApplyFrameOptions (it runs one for every plate it hands out) fine-tunes
    -- it. Not called from here: that is Blizzard's code under our name.
    local list = rawget(auras, "DebuffListFrame")
    if list and list.SetPoint then
      pcall(list.ClearAllPoints, list)
      pcall(list.SetPoint, list, "BOTTOM", blizzard, "TOP", 0, 0)
    end
  end
  -- Never hidden, only made invisible (see HideBlizzardPlate): visible again.
  blizzard.fuiHidden = nil
  if blizzard.SetAlpha then blizzard:SetAlpha(1) end
  return true
end
module.RestoreBlizzardPlate = RestoreBlizzardPlate

---------------------------------------------------------------------------
-- Standing down for another addon
---------------------------------------------------------------------------

-- The nameplate addons people already run. If one of these is loaded there
-- is no sense in two of us drawing over the same units, so ForeverUI steps
-- aside once and says so; turning it back on afterwards sticks.
local RIVALS = {
  { "Plater", "Plater" },
  { "TidyPlates", "TidyPlates" },
  { "NeatPlates", "NeatPlates" },
  { "Kui_Nameplates", "Kui Nameplates" },
  { "TidyPlates_ThreatPlates", "Threat Plates" },
  { "ThreatPlates", "Threat Plates" },
  { "SimplePlates", "SimplePlates" },
  { "NamePlateFilter", "NamePlateFilter" },
}
module.RIVALS = RIVALS

function module.RivalAddOn()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not loaded then
    return nil
  end
  -- In list order, so the answer is the same every time rather than
  -- whichever one pairs() happened to reach first.
  for _, entry in ipairs(RIVALS) do
    local ok, isLoaded = pcall(loaded, entry[1])
    if ok and isLoaded then
      return entry[2]
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Laying one plate out
---------------------------------------------------------------------------

local function Layout(plate)
  local settings = Settings()
  local unit = plate.unit
  local scale = plate.previewScale or (unit and module.ScaleFor(unit)) or 1
  local nameRow = (settings.showName ~= false and not settings.nameInside) and NAME_ROW or 0
  if settings.showLevel and not settings.nameInside then nameRow = NAME_ROW end

  plate:SetSize(settings.width, settings.height + nameRow + PAD * 2)
  plate:SetScale(scale)

  plate.health:ClearAllPoints()
  plate.health:SetPoint("TOPLEFT", plate, "TOPLEFT", PAD, -(nameRow + PAD))
  plate.health:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -PAD, PAD)
  plate.health:SetStatusBarTexture(ns.Media.StatusBarTexture())

  -- The name sits above the bar, or inside it when you ask for the shorter
  -- plate: the game's own look, and half the height.
  plate.name:ClearAllPoints()
  plate.level:ClearAllPoints()
  if settings.nameInside then
    plate.name:SetPoint("LEFT", plate.health, "LEFT", 4, 0)
    plate.level:SetPoint("RIGHT", plate.health, "RIGHT", -4, 0)
  else
    plate.name:SetPoint("TOPLEFT", plate, "TOPLEFT", PAD + 2, -3)
    plate.level:SetPoint("TOPRIGHT", plate, "TOPRIGHT", -(PAD + 2), -3)
  end
  plate.name:SetPoint("RIGHT", plate.level, "LEFT", -4, 0)

  plate.cast:SetStatusBarTexture(ns.Media.StatusBarTexture())
  local castH = math.max(10, settings.castHeight or 18)
  plate.cast:SetSize(settings.width - castH - 4, castH)
  plate.cast.iconBox:SetSize(castH, castH)
  plate.cast.iconBox:SetShown(settings.castShowIcon ~= false)

  local path, _, outline = ns.Media.Role("unitName")
  local flags = settings.outline ~= "" and settings.outline or (outline or "")
  plate.name:SetFont(path, settings.fontSize or 10, flags)
  plate.level:SetFont(path, settings.fontSize or 10, flags)
  plate.percent:SetFont(path, math.max(7, (settings.fontSize or 10) - 1), flags)
  if plate.title then plate.title:SetFont(path, math.max(7, (settings.fontSize or 10) - 1), flags) end
  if plate.quest then plate.quest:SetFont(path, (settings.fontSize or 10) + 1, flags ~= "" and flags or "OUTLINE") end
  ns.Media.SetFont(plate.cast.text, "aura")
  ns.Media.SetFont(plate.cast.timer, "aura")
end
module.Layout = Layout

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

-- Kick priority (the owner, 25 Sept 2026: "keep it on the enemy and change
-- its colour"). An enemy's cast is secret to addons on Forever, so we can't
-- look the spell up. C_Spell.IsSpellHelpful (cast on friends: a heal or a
-- buff) and C_Spell.IsSpellImportant (Blizzard's "lethal if not
-- interrupted") take the secret spell ID and answer with a secret yes/no,
-- and C_CurveUtil turns that into a colour or an alpha the game applies.
-- Nothing here branches on the answer.
local function Secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

-- Is there an answer? A secret one counts, and is never tested itself.
local function Present(v)
  if Secret(v) then return true end
  return v ~= nil
end

function module.KickAnswers(spellID)
  local spell = C_Spell
  if not spell or not Present(spellID) then return nil, nil end
  local helpful, important
  if spell.IsSpellHelpful then
    local ok, v = pcall(spell.IsSpellHelpful, spellID)
    if ok then helpful = v end
  end
  if spell.IsSpellImportant then
    local ok, v = pcall(spell.IsSpellImportant, spellID)
    if ok then important = v end
  end
  return helpful, important
end

local function Pick(bool, yes, no)
  -- A secret yes/no to one of two values, through the game; plain ones directly.
  if issecretvalue and issecretvalue(bool) then
    local util = C_CurveUtil
    if type(yes) == "table" and util and util.EvaluateColorFromBoolean then
      local ok, c = pcall(util.EvaluateColorFromBoolean, bool, yes, no)
      if ok then return c end
    elseif util and util.EvaluateColorValueFromBoolean then
      local ok, v = pcall(util.EvaluateColorValueFromBoolean, bool, yes, no)
      if ok then return v end
    end
    return no
  end
  if bool then return yes end
  return no
end
module.KickPick = Pick

local function KickColors()
  if not module.kickColors and CreateColor then
    module.kickColors = {
      heal = CreateColor(KICK_HEAL[1], KICK_HEAL[2], KICK_HEAL[3], 1),
      important = CreateColor(KICK_IMPORTANT[1], KICK_IMPORTANT[2], KICK_IMPORTANT[3], 1),
    }
  end
  return module.kickColors
end

-- Colour one plate's cast bar and fade its KICK tags from the game's
-- answers. Every value Pick returns may be secret, so none is ever tested
-- (no `x and y or z` on them) - only handed to the game.
local function KickPriority(plate, spellID, normal)
  local cast = plate.cast
  local helpful, important = module.KickAnswers(spellID)
  local colors = KickColors()
  if not colors or not (Present(helpful) or Present(important)) then
    cast.kickHeal:SetAlpha(0)
    cast.kickImportant:SetAlpha(0)
    return false
  end
  local color = normal
  if Present(important) then color = Pick(important, colors.important, color) end
  if Present(helpful) then color = Pick(helpful, colors.heal, color) end
  pcall(function() cast:SetStatusBarColor(color:GetRGBA()) end)
  if Present(helpful) then
    cast.kickHeal:SetAlpha(Pick(helpful, 1, 0))
    cast.kickImportant:SetAlpha(Pick(helpful, 0, 1))
  else
    cast.kickHeal:SetAlpha(0)
    cast.kickImportant:SetAlpha(1)
  end
  if Present(important) then
    cast.kickImportant.inner:SetAlpha(Pick(important, 1, 0))
  else
    cast.kickImportant.inner:SetAlpha(0)
  end
  return true
end
module.KickPriority = KickPriority

local function UpdateCast(plate)
  local settings = Settings()
  local unit = plate.unit
  if not settings.castBars or not unit then
    plate.cast:Hide()
    return false
  end
  local name, _, icon, startTime, endTime, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
  local channelling = false
  if not name and UnitChannelInfo then
    name, _, icon, startTime, endTime, _, notInterruptible, spellID = UnitChannelInfo(unit)
    channelling = name ~= nil
  end
  if not name then
    plate.cast:Hide()
    return false
  end
  -- A secret boolean throws on a plain `if`; read it through the guard.
  local safe = ns.Secrets.Bool(notInterruptible, false)
  if safe and settings.castShowUninterruptible == false then
    plate.cast:Hide()
    return false
  end

  local now = GetTime and GetTime() * 1000 or startTime or 0
  local ok = ns.Secrets.Measure(function()
    plate.cast:SetMinMaxValues(startTime or 0, endTime or 1)
    plate.cast:SetValue(now)
  end)
  local okTimer, timer = ns.Secrets.Measure(function()
    local total = (endTime - startTime) / 1000
    local elapsed = (now - startTime) / 1000
    if channelling then elapsed = total - elapsed end
    return ("%.1f / %.1f"):format(math.max(0, elapsed), total)
  end)
  plate.cast.timer:SetText(settings.castShowTime ~= false and okTimer and timer or "")
  plate.cast.text:SetText(settings.castShowName ~= false and name or "")

  if safe then
    plate.cast:SetStatusBarColor(ns.Colors.Get("status", "uninterruptible"))
    plate.cast.kickHeal:SetAlpha(0)
    plate.cast.kickImportant:SetAlpha(0)
  else
    local r, g, b = ns.Colors.Get("status", channelling and "channeling" or "casting")
    plate.cast:SetStatusBarColor(r, g, b)
    local painted = false
    if settings.castKickPriority ~= false and CreateColor then
      painted = KickPriority(plate, spellID, CreateColor(r, g, b, 1))
    end
    if not painted then
      plate.cast.kickHeal:SetAlpha(0)
      plate.cast.kickImportant:SetAlpha(0)
    end
  end

  -- The last slice of the bar is the part your interrupt can't reach.
  local lag = settings.latency or 0
  if lag > 0 and not safe then
    ns.Secrets.Measure(function()
      local total = (endTime - startTime) / 1000
      if total > 0 then
        local width = plate.cast:GetWidth() * math.min(1, lag / total)
        plate.cast.lag:ClearAllPoints()
        plate.cast.lag:SetPoint("TOPRIGHT", plate.cast, "TOPRIGHT", -1, -1)
        plate.cast.lag:SetPoint("BOTTOMRIGHT", plate.cast, "BOTTOMRIGHT", -1, 1)
        plate.cast.lag:SetWidth(math.max(1, width))
        plate.cast.lag:Show()
      end
    end)
  else
    plate.cast.lag:Hide()
  end

  plate.cast.icon:SetTexture(icon)
  plate.cast.iconBox:SetShown(settings.castShowIcon ~= false and icon ~= nil)
  plate.cast:Show()
  return ok ~= false
end
module.UpdateCast = UpdateCast

-- The name, shortened if you asked and marked with what the unit is.
local function NameText(unit)
  local settings = Settings()
  if settings.showName == false then
    return ""
  end
  local name = Query(UnitName, unit)
  if type(name) ~= "string" then
    return ""
  end
  -- A secret name can be shown but not measured: shown whole.
  if not ns.Secrets.String(name) then
    return name
  end
  if settings.truncateNames and #name > (settings.nameLength or 18) then
    name = name:sub(1, settings.nameLength or 18) .. "..."
  end
  return name
end
module.NameText = NameText

-- An NPC's title -- "Hunter Trainer", "Innkeeper" -- from the game's own
-- tooltip for it: the line under the name, unless that line is its level
-- (an NPC without a title). Cached by name; a secret answer (the game hiding
-- it) shows nothing rather than guessing.
local titles = {}
module.titleCache = titles
function module.NPCTitle(unit)
  if not unit or Category(unit) ~= "npc" or IsObject(unit) then return nil end
  local name = Query(UnitName, unit)
  local plainName = type(name) == "string" and ns.Secrets.String(name) and name or nil
  if plainName and titles[plainName] ~= nil then return titles[plainName] or nil end
  local data = C_TooltipInfo and C_TooltipInfo.GetUnit and Query(C_TooltipInfo.GetUnit, unit)
  local line = type(data) == "table" and type(data.lines) == "table" and data.lines[2]
  local text = type(line) == "table" and line.leftText
  local title = nil
  if type(text) == "string" and ns.Secrets.String(text) and text ~= "" and text ~= plainName then
    local level = (LEVEL or "Level")
    if text:sub(1, #level) ~= level then title = text end
  end
  if plainName then titles[plainName] = title or false end
  return title
end

-- What a mob still counts for in your quest log: "3/10", from QuestForever
-- (with ForeverUI it loads only when you switch it on; without it, nothing).
-- Matched by name, as its tooltips are -- in a group the game can hide names,
-- and then there is no count rather than a guess. QuestForever says when the
-- log, a kill or a loot changes, and the plates are redrawn then.
local questHooked = false
function module.QuestProgress(unit)
  local qf = rawget(_G, "QuestForever")
  if not (unit and type(qf) == "table" and qf.PlateProgress) then return nil end
  if not questHooked and qf.OnChange then
    questHooked = true
    qf.OnChange(function()
      if ns.ModuleRunning and ns.ModuleRunning("Nameplates") then module.UpdateAll() end
    end)
  end
  if Category(unit) ~= "npc" or IsObject(unit) then return nil end
  local name = Query(UnitName, unit)
  if type(name) ~= "string" or not ns.Secrets.String(name) then return nil end
  local ok, text = pcall(qf.PlateProgress, name)
  return ok and type(text) == "string" and text ~= "" and text or nil
end

local function LevelText(unit)
  local settings = Settings()
  local parts = {}
  if settings.showLevel then
    local level = ns.Secrets.Number(Query(UnitLevel, unit))
    if level and level > 0 then
      parts[#parts + 1] = tostring(level)
    elseif level then
      parts[#parts + 1] = "??"
    end
  end
  if settings.showClassification then
    local mark = CLASSIFICATION_MARK[ns.Secrets.String(Query(UnitClassification, unit)) or ""]
    if mark then parts[#parts + 1] = mark end
  end
  return table.concat(parts, " ")
end
module.LevelText = LevelText

-- How threatened you are by this unit, 0-3, or nil when the client won't
-- say. Never compared without going through the guard first.
local function Threat(unit)
  if not UnitThreatSituation then
    return nil
  end
  return ns.Secrets.Number(Query(UnitThreatSituation, "player", unit))
end
module.Threat = Threat

local function Update(plate)
  local unit = plate.unit
  if not unit or not UnitExists(unit) then
    return false
  end
  local settings = Settings()

  -- Whether this one is wanted at all.
  local wanted, reason = module.ShouldShow(unit)
  plate.hiddenReason = not wanted and reason or nil
  plate:SetShown(wanted)
  if not wanted then
    return false
  end

  -- Sizing and textures first: setting a status bar's texture clears its
  -- colour, so colouring before this would be undone.
  Layout(plate)

  plate.name:SetText(NameText(unit))
  plate.name:SetTextColor(1, 1, 1)
  plate.name:SetShown(settings.showName ~= false)
  if plate.title then
    local title = settings.npcTitles ~= false and module.NPCTitle(unit) or nil
    plate.title:SetText(title and ("<" .. title .. ">") or "")
    plate.title:SetTextColor(0.85, 0.85, 0.85)
    plate.title:SetShown(title ~= nil)
  end
  if plate.quest then
    local progress = settings.questProgress ~= false and module.QuestProgress(unit) or nil
    plate.quest:SetText(progress or "")
    plate.quest:SetTextColor(1, 0.82, 0)
    plate.quest:SetShown(progress ~= nil)
  end

  local level = LevelText(unit)
  plate.level:SetText(level)
  plate.level:SetTextColor(1, 0.82, 0)
  plate.level:SetShown(level ~= "")
  if plate.raidMark then ns.Secrets.PaintRaidMark(plate.raidMark, unit) end

  local r, g, b = BarColor(unit)
  plate.health:SetStatusBarColor(r, g, b)

  -- Friendly players can be a name and nothing else -- the quietest a plate
  -- gets without turning it off.
  local object = IsObject(unit)
  local nameOnly = object or (settings.friendlyNameOnly and Category(unit) == "friendly")
  plate.health:SetShown(not nameOnly)
  plate.nameOnly = nameOnly or nil
  plate.isObject = object or nil
  if nameOnly then
    if object then
      -- A thing has no level or reaction colour: its name, in the game's
      -- interact gold.
      plate.name:SetTextColor(1, 0.82, 0.3)
      plate.level:SetText("")
      plate.level:Hide()
      plate.percent:SetText("")
      if plate.raidMark then plate.raidMark:Hide() end
    else
      plate.name:SetTextColor(r, g, b)
    end
    plate.cast:Hide()
    return true
  end

  -- The bar can always be set from the game's own values; only the text
  -- needs arithmetic, and that is what may be refused.
  local ok, percent = ns.Secrets.Measure(function()
    local maximum = UnitHealthMax(unit)
    local current = UnitHealth(unit)
    if not maximum or maximum <= 0 then
      return nil
    end
    return current / maximum * 100
  end)
  ns.Secrets.Measure(function()
    ns.Secrets.SetBar(plate.health, UnitHealth(unit), UnitHealthMax(unit))
  end)
  if ok and percent and settings.showPercent then
    plate.percent:SetText(("%d%%"):format(math.floor(percent + 0.5)))
  else
    plate.percent:SetText("")
  end
  plate.measureFailed = not ok

  -- Low health: the bar goes the colour of a warning rather than shouting.
  if ok and percent and settings.flashLowHealth
    and percent <= (settings.lowHealthThreshold or 0) then
    plate.health:SetStatusBarColor(ns.Colors.Get("status", "healthLow"))
    plate.low = true
  else
    plate.low = nil
  end

  -- Incoming heals, as far ahead of the fill as they will reach.
  local showIncoming = false
  if settings.healthPrediction and UnitGetIncomingHeals then
    ns.Secrets.Measure(function()
      local incoming = UnitGetIncomingHeals(unit) or 0
      local maximum = UnitHealthMax(unit)
      local current = UnitHealth(unit)
      if incoming > 0 and maximum and maximum > 0 then
        local width = plate.health:GetWidth() * math.min(1, incoming / maximum)
        local start = plate.health:GetWidth() * math.min(1, current / maximum)
        plate.incoming:ClearAllPoints()
        plate.incoming:SetPoint("TOPLEFT", plate.health, "TOPLEFT", start, 0)
        plate.incoming:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", start, 0)
        plate.incoming:SetWidth(math.max(1, width))
        showIncoming = true
      end
    end)
  end
  plate.incoming:SetShown(showIncoming)

  -- The edge says what has aggro on you: yours, slipping, or someone else's.
  local edge = ns.Colors.ui.accent
  local threat = settings.showThreat and Threat(unit) or nil
  if threat and threat >= 2 then
    edge = { 0.85, 0.20, 0.20 }
  elseif threat == 1 then
    edge = { 0.95, 0.70, 0.25 }
  elseif settings.targetBorder and ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(unit, "target"), false) then
    edge = { 1, 1, 1 }
  end
  ns.Skin.SetBorderColor(plate, edge)

  -- Fading: out of range first, then anything that isn't your target.
  local alpha = 1
  if UnitInRange and ns.Secrets.Bool(UnitIsPlayer and UnitIsPlayer(unit), false) then
    -- UnitInRange answers with a secret boolean in a group, and only speaks
    -- for people in your group at all: assume in range unless told otherwise.
    local asked, inRange = ns.Secrets.Measure(function()
      return ns.Secrets.Bool(UnitInRange(unit), true)
    end)
    if asked and inRange == false then
      alpha = (settings.outOfRangeAlpha or 100) / 100
    end
  end
  if settings.fadeNonTargets and UnitExists and UnitExists("target")
    and not ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(unit, "target"), false) then
    alpha = math.min(alpha, (settings.nonTargetAlpha or 100) / 100)
  end
  plate:SetAlpha(alpha)

  UpdateCast(plate)
  return true
end
module.Update = Update

-- Only so many at once: the ones you are actually fighting beat the ones at
-- the back of the room, and your target always keeps its plate.
local function ApplyCap()
  local cap = Settings().maxPlates or 40
  local shown = 0
  local ordered = {}
  for unit, plate in pairs(plates) do
    ordered[#ordered + 1] = { unit = unit, plate = plate }
  end
  table.sort(ordered, function(a, b)
    local at = ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(a.unit, "target"), false) and 1 or 0
    local bt = ns.Secrets.Bool(UnitIsUnit and UnitIsUnit(b.unit, "target"), false) and 1 or 0
    if at ~= bt then return at > bt end
    return a.unit < b.unit
  end)
  for _, entry in ipairs(ordered) do
    if entry.plate.hiddenReason == nil then
      shown = shown + 1
      if shown > cap then
        entry.plate:Hide()
        entry.plate.hiddenReason = "over the plate cap"
      end
    end
  end
  module.shownCount = math.min(shown, cap)
  return module.shownCount
end
module.ApplyCap = ApplyCap

local function UpdateAll()
  for _, plate in pairs(plates) do
    Update(plate)
  end
  ApplyCap()
end
module.UpdateAll = UpdateAll

---------------------------------------------------------------------------
-- The game hands plates out and takes them back
---------------------------------------------------------------------------

local function Added(unit)
  local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    and C_NamePlate.GetNamePlateForUnit(unit)
  if not base then
    return nil
  end
  local plate = rawget(base, "foreverPlate")
  if not plate then
    plate = Build(base)
    base.foreverPlate = plate
  end
  plate:ClearAllPoints()
  plate:SetPoint("CENTER", base, "CENTER", 0, Settings().verticalOffset or 0)
  HideBlizzardPlate(base, plate)
  plate.unit = unit
  plate:Show()
  plates[unit] = plate
  Update(plate)
  ApplyCap()
  return plate
end
module.Added = Added

local function Removed(unit)
  local plate = plates[unit]
  if plate then
    plate.unit = nil
    plate:Hide()
    plates[unit] = nil
  end
  return plate ~= nil
end
module.Removed = Removed

---------------------------------------------------------------------------
-- The preview, and the test plates
---------------------------------------------------------------------------

-- One of each, because the colours are the part that is easy to get wrong:
-- what attacks you, what only fights back, what ignores you, what somebody
-- else already claimed, and who is on your side.
local PREVIEW = {
  { name = "Riverpaw Gnoll", level = "12 +", percent = 87, colour = "enemyColor",
    threat = 2, note = "hostile", quest = "4/10" },
  { name = "Defias Bandit", level = "18", percent = 46, colour = "unfriendlyColor",
    note = "unfriendly", cast = { "Shadow Bolt", "1.6 / 2.0", 0.8 } },
  { name = "Young Forest Bear", level = "10", percent = 100, colour = "neutralColor",
    note = "neutral" },
  { name = "Cloudrunner", level = "6", percent = 34, colour = "tappedColor",
    note = "someone else's" },
  { name = "Constable Aonda", level = "20", percent = 100, colour = "friendlyColor",
    note = "friendly" },
}
module.PREVIEW = PREVIEW

-- The same plate the game gets, fed made-up numbers, so every setting on
-- this page can be seen before it is taken outside.
function module.PaintPreview(plate, sample)
  local settings = Settings()
  plate.unit = nil
  plate.previewScale = sample.scale or 1
  Layout(plate)
  plate.name:SetText(sample.name)
  if plate.quest then
    local quest = settings.questProgress ~= false and sample.quest or nil
    plate.quest:SetText(quest or "")
    plate.quest:SetTextColor(1, 0.82, 0)
    plate.quest:SetShown(quest ~= nil)
  end
  plate.name:SetTextColor(1, 1, 1)
  plate.name:SetShown(settings.showName ~= false)
  plate.level:SetText(settings.showLevel and sample.level or "")
  plate.level:SetTextColor(1, 0.82, 0)
  plate.level:SetShown(settings.showLevel and sample.level ~= "")
  local FALLBACK = {
    enemyColor = "hostile", unfriendlyColor = "unfriendly", neutralColor = "neutral",
    tappedColor = "tapped", friendlyColor = "friendly",
  }
  local r, g, b = Colour(sample.colour, FALLBACK[sample.colour] or "neutral")
  if settings.flashLowHealth and sample.percent <= (settings.lowHealthThreshold or 0) then
    r, g, b = ns.Colors.Get("status", "healthLow")
  end
  plate.health:Show()
  plate.health:SetStatusBarColor(r, g, b)
  plate.health:SetMinMaxValues(0, 100)
  plate.health:SetValue(sample.percent)
  plate.percent:SetText(settings.showPercent and ("%d%%"):format(sample.percent) or "")
  plate.incoming:Hide()

  local edge = ns.Colors.ui.accent
  if settings.showThreat and (sample.threat or 0) >= 2 then
    edge = { 0.85, 0.20, 0.20 }
  end
  ns.Skin.SetBorderColor(plate, edge)

  if sample.cast and settings.castBars then
    plate.cast:SetMinMaxValues(0, 1)
    plate.cast:SetValue(sample.cast[3])
    plate.cast:SetStatusBarColor(ns.Colors.Get("status", "casting"))
    plate.cast.text:SetText(settings.castShowName ~= false and sample.cast[1] or "")
    plate.cast.timer:SetText(settings.castShowTime ~= false and sample.cast[2] or "")
    plate.cast.icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowBolt")
    plate.cast.lag:Hide()
    plate.cast:Show()
  else
    plate.cast:Hide()
  end
end

-- How much room one preview plate needs: the box, plus the cast bar hanging
-- under it. Worked out from the settings rather than guessed, or the plates
-- sit on each other the moment the bars get taller.
local function PreviewStep()
  local settings = Settings()
  local box = settings.height + NAME_ROW + PAD * 2
  local cast = settings.castBars and (math.max(10, settings.castHeight or 18) + 4) or 0
  return box + cast + 16
end

-- Built into the options page by the `custom` row in the schema.
function module.BuildPreview(parent, x, y, width)
  local card = CreateFrame("Frame", nil, parent)
  card:SetPoint("TOPLEFT", x, y)
  card:SetWidth(width)
  ns.Skin.Panel(card, { color = { 0.04, 0.08, 0.13, 1 }, borderColor = ns.Colors.ui.accent })

  module.previewPlates = {}
  for i, sample in ipairs(PREVIEW) do
    local plate = Build(card)
    module.PaintPreview(plate, sample)
    module.previewPlates[i] = plate
  end
  module.previewCard = card
  return module.LayoutPreview() + 10
end

-- Spaces the plates out and sizes the card round them. Called again on every
-- refresh, so making the bars taller moves them apart instead of overlapping.
function module.LayoutPreview()
  local card = module.previewCard
  if not card then
    return 0
  end
  local step = PreviewStep()
  for i, plate in ipairs(module.previewPlates or {}) do
    plate:ClearAllPoints()
    plate:SetPoint("TOP", card, "TOP", 0, -14 - (i - 1) * step)
  end
  local height = 14 + step * math.max(1, #(module.previewPlates or {})) + 6
  card:SetHeight(height)
  return height
end

function module.RefreshPreview()
  for i, plate in ipairs(module.previewPlates or {}) do
    if PREVIEW[i] then
      module.PaintPreview(plate, PREVIEW[i])
    end
  end
  module.LayoutPreview()
end

-- "Test Nameplates": walk the samples through a fight, so the low-health
-- colour, the threat edge and the cast bar can all be seen at once.
function module.TestPlates()
  for _, sample in ipairs(PREVIEW) do
    sample.percent = math.random(5, 100)
    sample.threat = math.random(0, 3)
  end
  PREVIEW[2].cast = { "Shadow Bolt", ("%.1f / 2.0"):format(math.random() * 2), math.random() }
  module.RefreshPreview()
  ns.Print("test nameplates: the preview now shows a fight in progress.")
  return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local EVENTS = {
  "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
  "UNIT_HEALTH", "UNIT_MAXHEALTH", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
  "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_HEAL_PREDICTION",
  "RAID_TARGET_UPDATE",   -- a mark placed or moved: every plate redraws its icon
}

local function OnEvent(_, event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" then
    Added(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    Removed(unit)
  elseif unit and plates[unit] then
    Update(plates[unit])
  else
    UpdateAll()
  end
end

-- Alt-Z hides the interface, but our plates hang off the world frame and
-- would stay. Follow UIParent instead.
local function WatchUIVisibility()
  if not UIParent or not UIParent.HookScript then
    return
  end
  UIParent:HookScript("OnHide", function()
    if Settings().hideWithUI then
      for _, plate in pairs(plates) do plate:Hide() end
    end
  end)
  UIParent:HookScript("OnShow", function()
    if Settings().hideWithUI then UpdateAll() end
  end)
end

function module:OnInit()
  local settings = Settings()
  if settings and settings.mockupDone == nil then
    settings.enabled = true
    settings.width, settings.height = 150, 20
    settings.showName, settings.showLevel = true, true
    settings.mockupDone = true
  end

  -- Minor units were off as standard, and the game counts many starting-zone
  -- mobs as minor: a new character's first quest mobs had no plates, only
  -- small names (owner, Deathknell, 26 Sept 2026). On once for everyone;
  -- critters stay hidden by their own switch.
  if settings and not settings.minorOn then
    settings.showMinor = true
    settings.minorOn = true
  end

  -- Someone already has a nameplate addon. Step aside rather than fight it,
  -- once, and leave a line saying how to take the job back.
  if settings and not settings.stoodDown then
    local rival = module.RivalAddOn()
    if rival then
      settings.stoodDown = rival
      settings.enabled = false
      ns.Print(("%s is running, so ForeverUI is leaving the nameplates to it. "
        .. "Turn them back on under Nameplates if you'd rather ours drew them.")
        :format(rival))
    end
  end
end

function module:OnEnable()
  driver = driver or CreateFrame("Frame")
  for _, event in ipairs(EVENTS) do
    pcall(driver.RegisterEvent, driver, event)
  end
  driver:SetScript("OnEvent", OnEvent)
  module.driver = driver
  module.ApplyCVars()
  WatchUIVisibility()
  UpdateAll()
end

-- Turning nameplates off has to be a real handover, not just our frames
-- going quiet: the game's own plate comes back, its aura list goes home,
-- and every CVar we set is put back the way we found it. After this
-- another addon owns the nameplates outright.
function module:OnDisable()
  if driver then
    driver:UnregisterAllEvents()
  end
  local bases = (C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()) or {}
  for _, base in ipairs(bases) do
    RestoreBlizzardPlate(base, rawget(base, "foreverPlate"))
  end
  for unit, plate in pairs(plates) do
    plate.unit = nil
    plate:Hide()
    plates[unit] = nil
  end
  module.RestoreCVars()
  module.shownCount = 0
  return true
end

-- No reload needed: OnDisable puts back everything it took.
module.needsReload = false

function module:Refresh()
  if not ns.IsModuleEnabled("Nameplates") then
    return false
  end
  module.ApplyCVars()
  UpdateAll()
  module.RefreshPreview()
  return true
end

module.plates = plates

---------------------------------------------------------------------------
-- Presets
---------------------------------------------------------------------------

-- A whole nameplate setup under a name: "Raid", "World PvP", "Levelling".
-- These are NOT a second profile system -- ForeverUI keeps one profile per
-- character and that stays true. A preset is a saved copy of this one page,
-- stored inside that profile, that you can put back on with one click.

local function PresetStore()
  ns.db.nameplatePresets = ns.db.nameplatePresets or {}
  return ns.db.nameplatePresets
end
module.PresetStore = PresetStore

-- What a preset holds: every setting on this page except the ones that say
-- which preset you're on, so applying one can't rename itself.
local NOT_SAVED = { preset = true, mockupDone = true }

local function Snapshot()
  local copy = {}
  for key, value in pairs(Settings()) do
    if not NOT_SAVED[key] then
      copy[key] = type(value) == "table" and { value[1], value[2], value[3] } or value
    end
  end
  return copy
end

function module.PresetNames()
  local names = {}
  for name in pairs(PresetStore()) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function module.SavePreset(name)
  if type(name) ~= "string" then return false, "give the preset a name" end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return false, "give the preset a name" end
  PresetStore()[name] = Snapshot()
  Settings().preset = name
  return true
end

function module.ApplyPreset(name)
  local saved = PresetStore()[name]
  if type(saved) ~= "table" then
    return false, "there's no preset called " .. tostring(name)
  end
  local settings = Settings()
  for key, value in pairs(saved) do
    if not NOT_SAVED[key] then
      settings[key] = type(value) == "table" and { value[1], value[2], value[3] } or value
    end
  end
  settings.preset = name
  module:Refresh()
  if ns.RefreshOptions then ns.RefreshOptions() end
  return true
end

function module.DeletePreset(name)
  if PresetStore()[name] == nil then
    return false, "there's no preset called " .. tostring(name)
  end
  PresetStore()[name] = nil
  if Settings().preset == name then
    Settings().preset = nil
  end
  return true
end

-- The same readable blob ForeverUI uses for a whole profile, cut down to
-- this page, so a nameplate setup can be pasted between characters.
function module.ExportSettings()
  return ("ForeverUI-Nameplates:%s:%s"):format(ns.VERSION or "?", ns.Serialize(Snapshot()))
end

function module.ImportSettings(text)
  if type(text) ~= "string" then
    return false, "nothing to import"
  end
  local body = text:match("^ForeverUI%-Nameplates:[^:]*:(.+)$")
  if not body then
    return false, "that doesn't look like exported nameplate settings"
  end
  local chunk = loadstring and loadstring("return " .. body)
  if not chunk then
    return false, "the text is damaged"
  end
  if setfenv then setfenv(chunk, {}) end   -- no globals, no functions
  local ok, parsed = pcall(chunk)
  if not ok or type(parsed) ~= "table" then
    return false, "the text is damaged"
  end
  local settings = Settings()
  for key, value in pairs(parsed) do
    if module.defaults[key] ~= nil and not NOT_SAVED[key] then
      settings[key] = value
    end
  end
  module:Refresh()
  if ns.RefreshOptions then ns.RefreshOptions() end
  return true
end

-- One honest line about who is drawing the plates right now, under the
-- switch. It is worth saying out loud when two addons are both trying.
function module.StatusLine()
  local rival = module.RivalAddOn()
  if Settings().enabled == false then
    if rival then
      return ("Off. " .. rival .. " is drawing them instead, and ForeverUI is staying out of its way.")
    end
    return "Off. The game draws its own plates, and every nameplate setting ForeverUI had changed has been put back. Nothing below applies until you switch it on."
  end
  if rival then
    return ("On -- but " .. rival .. " is loaded as well. Two addons drawing the same plates will fight over them; turn one of the two off.")
  end
  return "On. Everything below is ForeverUI's to draw."
end

-- "/fui plates why": every plate on screen, what the game says about it, and
-- which colour that earned. When a plate looks like the wrong colour this
-- prints the number it was decided from, which beats guessing from a
-- screenshot.
local REACTION_WORD = {
  [1] = "hated", [2] = "hostile", [3] = "unfriendly", [4] = "neutral",
  [5] = "friendly", [6] = "honored", [7] = "revered", [8] = "exalted",
}

function module.Explain()
  local seen = 0
  for i = 1, 60 do
    local unit = "nameplate" .. i
    if UnitExists(unit) then
      seen = seen + 1
      local name = ns.Secrets.String(Query(UnitName, unit)) or "?"
      local reaction = ns.Secrets.Number(Query(UnitReaction, "player", unit))
      local _, _, why = Reason(unit)
      local wanted, rule = module.ShouldShow(unit)
      ns.Print(("%s -- %s (%s)%s"):format(
        name,
        why,
        reaction and (REACTION_WORD[reaction] or reaction) or "no reaction",
        wanted and "" or (", hidden: " .. tostring(rule))))
    end
  end
  if seen == 0 then
    ns.Print("no nameplates on screen to explain.")
  end
  return seen
end

---------------------------------------------------------------------------
-- The options page
---------------------------------------------------------------------------

local function RuleChoices()
  return {
    { label = "Always", value = "always" },
    { label = "In combat", value = "combat" },
    { label = "When targeted", value = "target" },
    { label = "Never", value = "never" },
  }
end

-- Two ways of saying a percentage: a plain 0-100 setting, and a multiplier
-- where 1 means "the size it already was".
local function Percent(v) return ("%d%%"):format(math.floor((v or 0) + 0.5)) end
local function Scale(v) return ("%d%%"):format(math.floor((v or 1) * 100 + 0.5)) end

module.options = {
  { type = "heading", label = "Nameplates", subtitle = "The bar over a unit's head, and who gets one." },
  { type = "note", label = "Every category -- friendly players, enemy players and NPCs -- has its own rule, colour and size. The filters and the units you single out are on the Advanced tab." },

  -- The off switch sits above the tab strip, not on a tab: handing the
  -- nameplates to another addon shouldn't be something you have to go
  -- looking for.
  { type = "heading", label = "Who draws them", icon = "nameplates" },
  { type = "checkbox", key = "enabled", label = "ForeverUI draws the nameplates",
    desc = "Off hands them straight back -- to the game, or to Plater and friends.",
    apply = function()
      local on = Settings().enabled ~= false
      Settings().stoodDown = nil   -- your own choice outranks the one-time step aside
      ns.SetModuleEnabled("Nameplates", on)
      ns.Print(on and "ForeverUI is drawing the nameplates again."
        or "nameplates handed back. ForeverUI has let go of the frames, the aura lists and every nameplate setting it changed.")
      if ns.RefreshOptions then ns.RefreshOptions() end
    end },
  { type = "note", labelFor = function() return module.StatusLine() end },

  ---------------------------------------------------------------- general
  { type = "heading", tab = "general", tabLabel = "General", label = "Visibility", columns = 2, icon = "eye" },
  { type = "stepper", tab = "general", key = "viewDistance", label = "View distance", desc = "How far away a plate still appears.", min = 20, max = 100, step = 5,
    apply = function() module.ApplyCVars() end },
  { type = "stepper", tab = "general", key = "maxPlates", label = "Max nameplates", desc = "Your target always keeps its own.", min = 5, max = 60, step = 5 },
  { type = "stepper", tab = "general", key = "nonTargetAlpha", label = "Non-target opacity", desc = "How faint everything that isn't your target goes.", min = 20, max = 100, step = 5, format = Percent },
  { type = "stepper", tab = "general", key = "outOfRangeAlpha", label = "Out-of-range opacity", desc = "Players you can't reach.", min = 10, max = 100, step = 5, format = Percent },
  { type = "checkbox", tab = "general", key = "fadeNonTargets", label = "Fade non-targets", desc = "Dim everything but the one you're on." },
  { type = "checkbox", tab = "general", key = "hideInCombat", label = "Hide in combat", desc = "For screenshots and cinematics." },
  { type = "checkbox", tab = "general", key = "hideInInstances", label = "Hide in instances", desc = "Dungeons and raids only." },
  { type = "checkbox", tab = "general", key = "hideWithUI", label = "Hide with the interface", desc = "Follow Alt-Z instead of floating on." },

  { type = "heading", tab = "general", label = "Preview", icon = "eye" },
  { type = "custom", tab = "general", build = function(parent, x, y, width) return module.BuildPreview(parent, x, y, width) end },

  { type = "heading", tab = "general", label = "Text & Layout", columns = 3, icon = "appearance" },
  { type = "stepper", tab = "general", key = "fontSize", label = "Font size", desc = "The name and the level.", min = 7, max = 20, step = 1 },
  { type = "cycler", tab = "general", key = "outline", label = "Outline", desc = "Readability over a bright floor.",
    choices = function()
      return {
        { label = "None", value = "" },
        { label = "Thin", value = "OUTLINE" },
        { label = "Thick", value = "THICKOUTLINE" },
      }
    end },
  { type = "stepper", tab = "general", key = "verticalOffset", label = "Vertical offset", desc = "Nudge every plate up or down.", min = -60, max = 60, step = 2 },
  { type = "checkbox", tab = "general", key = "showName", label = "Show the name" },
  { type = "checkbox", tab = "general", key = "nameInside", label = "Name inside the bar", desc = "A shorter plate." },
  { type = "checkbox", tab = "general", key = "showLevel", label = "Show level" },
  { type = "checkbox", tab = "general", key = "showClassification", label = "Show elite and boss marks", desc = "+ elite, R rare, B boss." },
  { type = "checkbox", tab = "general", key = "truncateNames", label = "Shorten long names" },
  { type = "stepper", tab = "general", key = "nameLength", label = "Name length", min = 6, max = 40, step = 1 },

  { type = "heading", tab = "general", label = "Health Bar", columns = 3, icon = "unitframes" },
  { type = "stepper", tab = "general", key = "width", label = "Width", min = 60, max = 300, step = 5 },
  { type = "stepper", tab = "general", key = "height", label = "Height", min = 6, max = 40, step = 1 },
  { type = "stepper", tab = "general", key = "lowHealthThreshold", label = "Low health at", desc = "Below this the bar turns red.", min = 0, max = 60, step = 5, format = Percent },
  { type = "checkbox", tab = "general", key = "showPercent", label = "Show health percent" },
  { type = "checkbox", tab = "general", key = "flashLowHealth", label = "Warn at low health" },
  { type = "checkbox", tab = "general", key = "healthPrediction", label = "Show incoming heals" },

  { type = "heading", tab = "general", label = "Cast Bar", columns = 3, icon = "castbar" },
  { type = "stepper", tab = "general", key = "castHeight", label = "Height", min = 10, max = 36, step = 1 },
  { type = "stepper", tab = "general", key = "latency", label = "Latency mark", desc = "The end you can no longer interrupt.", min = 0, max = 0.5, step = 0.05,
    format = function(v) return ("%.2fs"):format(v) end },
  { type = "checkbox", tab = "general", key = "castBars", label = "Show cast bars" },
  { type = "checkbox", tab = "general", key = "castShowName", label = "Show the spell's name" },
  { type = "checkbox", tab = "general", key = "castShowTime", label = "Show the cast time" },
  { type = "checkbox", tab = "general", key = "castShowIcon", label = "Show the spell's icon" },
  { type = "checkbox", tab = "general", key = "castShowUninterruptible", label = "Show uninterruptible casts" },
  { type = "checkbox", tab = "general", key = "castKickPriority",
    label = "Kick priority: heals green, important red, KICK tag",
    desc = "The game decides which casts are heals and which are important; ForeverUI only colours them." },

  { type = "heading", tab = "general", label = "Presets", subtitle = "A whole nameplate setup under a name, saved inside this character's profile.", columns = 4, icon = "profiles" },
  { type = "cycler", tab = "general", key = "preset", label = "Preset", desc = "The setup you're on.",
    choices = function()
      local list = {}
      for _, name in ipairs(module.PresetNames()) do
        list[#list + 1] = { label = name, value = name }
      end
      if #list == 0 then
        list[1] = { label = "(none saved yet)", value = nil }
      end
      return list
    end,
    apply = function()
      local name = Settings().preset
      if name then module.ApplyPreset(name) end
    end },
  { type = "action", tab = "general", label = "Save as...", icon = "plus", desc = "Under a new name.",
    onClick = function()
      ns.ShowTextPopup("Name this nameplate preset", Settings().preset or "", function(text)
        local ok, err = module.SavePreset(text)
        ns.Print(ok and ("preset \"" .. text .. "\" saved.") or err)
        if ns.RefreshOptions then ns.RefreshOptions() end
      end)
    end },
  { type = "action", tab = "general", label = "Copy", icon = "copy", desc = "Settings as text.",
    onClick = function() ns.ShowTextPopup("Nameplate settings", module.ExportSettings()) end },
  { type = "action", tab = "general", label = "Paste", icon = "clickcasting", desc = "Settings from text.",
    onClick = function()
      ns.ShowTextPopup("Paste nameplate settings", "", function(text)
        local ok, err = module.ImportSettings(text)
        ns.Print(ok and "nameplate settings imported." or err)
      end)
    end },
  { type = "action", tab = "general", label = "Delete", icon = "close", desc = "The one you're on.",
    onClick = function()
      local name = Settings().preset
      local ok, err = module.DeletePreset(name)
      ns.Print(ok and ("preset \"" .. tostring(name) .. "\" deleted.") or err)
      if ns.RefreshOptions then ns.RefreshOptions() end
    end },

  ---------------------------------------------------------------- friendly
  { type = "heading", tab = "friendly", tabLabel = "Friendly", label = "Friendly Players", columns = 2, icon = "heal" },
  { type = "cycler", tab = "friendly", key = "showFriendly", label = "Show friendly players", desc = "When their plates appear.",
    choices = RuleChoices, apply = function() module.ApplyCVars() end },
  { type = "color", tab = "friendly", key = "friendlyColor", label = "Bar colour", desc = "Unless class colours are on." },
  { type = "stepper", tab = "friendly", key = "friendlyScale", label = "Size", min = 0.6, max = 1.6, step = 0.05, format = Scale },
  { type = "checkbox", tab = "friendly", key = "friendlyNameOnly", label = "Name only", desc = "No bar, just who it is." },
  { type = "checkbox", tab = "friendly", key = "classColor", label = "Colour players by class", desc = "Applies to both sides." },

  ---------------------------------------------------------------- enemy
  { type = "heading", tab = "enemy", tabLabel = "Enemy", label = "Enemy Players", columns = 2, icon = "dps" },
  { type = "cycler", tab = "enemy", key = "showEnemy", label = "Show enemy players", desc = "When their plates appear.",
    choices = RuleChoices, apply = function() module.ApplyCVars() end },
  { type = "color", tab = "enemy", key = "enemyColor", label = "Hostile", desc = "Attacks you on sight." },
  { type = "color", tab = "enemy", key = "unfriendlyColor", label = "Unfriendly", desc = "Won't start it. You can." },
  { type = "stepper", tab = "enemy", key = "enemyScale", label = "Size", min = 0.6, max = 1.6, step = 0.05, format = Scale },

  { type = "heading", tab = "enemy", label = "What the plate tells you", columns = 2, icon = "auras" },
  { type = "checkbox", tab = "enemy", key = "showThreat", label = "Threat on the edge", desc = "Red when it's on you, amber when it's slipping." },
  { type = "checkbox", tab = "enemy", key = "showDebuffs", label = "Show my debuffs", desc = "Drawn by the game, so they work in combat." },
  { type = "stepper", tab = "enemy", key = "auraScale", label = "Aura size", min = 0.6, max = 2, step = 0.1, format = Scale,
    apply = function() module.ApplyCVars() end },

  ---------------------------------------------------------------- npc
  { type = "heading", tab = "npc", tabLabel = "NPC", label = "NPCs", columns = 2, icon = "nameplates" },
  { type = "cycler", tab = "npc", key = "showNPC", label = "Show NPCs", desc = "When their plates appear.",
    choices = RuleChoices, apply = function() module.ApplyCVars() end },
  { type = "color", tab = "npc", key = "neutralColor", label = "Neutral colour", desc = "The ones that haven't decided." },
  { type = "checkbox", tab = "npc", key = "npcTitles", label = "Their job under the plate",
    desc = "<Hunter Trainer>, <Innkeeper>: the title the game shows for an NPC." },
  { type = "checkbox", tab = "npc", key = "questProgress", label = "Quest kills left beside the plate",
    desc = "3/10 next to a mob your quests still need (kills, or the item it drops). Needs QuestForever switched on; in a group the game can hide mob names, and then no count shows." },
  { type = "stepper", tab = "npc", key = "npcScale", label = "Size", min = 0.6, max = 1.6, step = 0.05, format = Scale },
  { type = "checkbox", tab = "npc", key = "showMinor", label = "Show minor units",
    desc = "Mobs the game counts as minor - many starting-zone ones. Off, they get only a name. Critters have their own switch.",
    apply = function() module.ApplyCVars() end },
  { type = "checkbox", tab = "npc", key = "showTotems", label = "Show totems",
    apply = function() module.ApplyCVars() end },
  { type = "checkbox", tab = "npc", key = "hideCritters", label = "Hide critters", desc = "Even if the game offers them." },
  { type = "checkbox", tab = "npc", key = "showTapped", label = "Grey out tapped mobs", desc = "Someone else hit it: no experience, no loot." },
  { type = "color", tab = "npc", key = "tappedColor", label = "Tapped colour", desc = "What a mob that isn't yours looks like." },

  ---------------------------------------------------------------- personal
  { type = "heading", tab = "personal", tabLabel = "Personal", label = "Your Own Plate", icon = "profiles" },
  { type = "checkbox", tab = "personal", key = "showPersonal", label = "Show my own nameplate", desc = "The health and power bar under your feet.",
    apply = function() module.ApplyCVars() end },
  { type = "note", tab = "personal", label = "The personal plate is the game's own: it carries your health, your power and your own buffs, and ForeverUI only asks for it. Your unit frame on the Unit Frames page is the fuller picture." },

  ---------------------------------------------------------------- advanced
  { type = "heading", tab = "advanced", tabLabel = "Advanced", label = "Filters", columns = 2, icon = "search" },
  { type = "checkbox", tab = "advanced", key = "hidePets", label = "Hide pets", desc = "Anything another player is driving." },
  { type = "checkbox", tab = "advanced", key = "hideDead", label = "Hide the dead" },
  { type = "checkbox", tab = "advanced", key = "hideUnattackable", label = "Hide what you can't attack" },
  { type = "checkbox", tab = "advanced", key = "onlyTarget", label = "Only show my target", desc = "One plate at a time." },
  { type = "input", tab = "advanced", key = "blacklist", label = "Never show these", desc = "Names, separated by commas.", hint = "e.g. Totem, Training Dummy" },
  { type = "input", tab = "advanced", key = "whitelist", label = "Always show these", desc = "Beats every rule and filter above.", hint = "e.g. Boss, Elite" },

  { type = "heading", tab = "advanced", label = "Singled Out", columns = 3, icon = "target" },
  { type = "stepper", tab = "advanced", key = "targetScale", label = "Your target", min = 1, max = 1.8, step = 0.05, format = Scale },
  { type = "stepper", tab = "advanced", key = "focusScale", label = "Your focus", min = 1, max = 1.8, step = 0.05, format = Scale },
  { type = "stepper", tab = "advanced", key = "bossScale", label = "Bosses", min = 1, max = 1.8, step = 0.05, format = Scale },
  { type = "stepper", tab = "advanced", key = "eliteScale", label = "Elites", min = 1, max = 1.8, step = 0.05, format = Scale },
  { type = "checkbox", tab = "advanced", key = "targetBorder", label = "White edge on your target" },

  { type = "heading", tab = "advanced", label = "Trying it out", columns = 2, icon = "installer" },
  { type = "action", tab = "advanced", label = "Test nameplates", width = 240, desc = "Fill the preview with a fight.",
    icon = "target", onClick = function() module.TestPlates() end },
  { type = "action", tab = "advanced", label = "Re-apply game settings", width = 240, desc = "Push every rule back to the game.",
    icon = "reset", onClick = function()
      module.ApplyCVars()
      ns.Print("nameplate settings pushed back to the game.")
    end },
  { type = "note", tab = "advanced", label = "Turn the whole module off on the Modules page to give Blizzard's plates back -- that one needs a reload." },
}

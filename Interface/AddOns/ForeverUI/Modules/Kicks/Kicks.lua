local _, ns = ...

-- Kick alerts: enemy casts worth interrupting, by priority, in the middle of
-- the screen. An option now (off by default): the nameplate cast bar shows
-- the same priority on the enemy itself.
--
--   HEALS - KICK        [Healing Wave         ] Kolkar Stormer      (big, green)
--   IMPORTANT           [Lightning Bolt       ] Windfury Sorceress  (red)
--   other casts         [Frostbolt            ] Windfury Sorceress  (small, amber)
--
-- The owner's ask, 24 Sept 2026: "special warnings for things that I need to
-- kick by priority... like heals".
--
-- Forever makes every enemy's cast SECRET to addons ("secret values if the
-- unit being queried for cast information is not the player or their pet").
-- We may show the spell's name and time, never read them - so we can't look
-- a heal up in a list. What the game gives instead: C_Spell.IsSpellHelpful
-- (a spell cast on friends: a heal or a buff) and C_Spell.IsSpellImportant
-- (Blizzard's "lethal if not interrupted"), both taking the secret spell ID
-- and answering with a secret yes/no - and C_CurveUtil turns a secret yes/no
-- into an alpha or a colour without us ever seeing it.
--
-- So every cast gets a row in all three lanes, and each row sits inside
-- frames whose alpha the game sets from those answers: the heal lane's row
-- shows only if helpful; the important lane's only if not helpful AND
-- important (an outer frame for one, an inner for the other - alphas
-- multiply); the rest only if neither. A cast that can't be interrupted is
-- dimmed the same way. The bar fills from the cast's (secret) start and end
-- times, which a StatusBar is allowed to take as its range.
--
-- What it can't do: a different SOUND for heals - a sound needs a real yes.

local module = ns.RegisterModule({
  name = "Kicks",
  title = "Kick Alerts",
})

-- Off unless asked for: the cast bar ON the enemy's nameplate now carries
-- the priority (green heals, red important, a KICK tag - Nameplates.lua),
-- which the owner preferred to a list in the middle of the screen.
module.defaults = {
  enabled = false,
  heals = true,            -- the heal lane
  important = true,        -- the important lane
  others = true,           -- every other enemy cast
  dimUnkickable = true,    -- fade casts that can't be interrupted
  width = 300,
  scale = 1,
}

local LANES = {
  { key = "heals",     tag = "HEAL", height = 30, font = 16, color = { 0.25, 0.95, 0.40 } },
  { key = "important", tag = "!!",   height = 24, font = 14, color = { 1.00, 0.25, 0.20 } },
  { key = "others",    tag = "",     height = 18, font = 12, color = { 1.00, 0.70, 0.20 } },
}
module.LANES = LANES
local SLOTS = 4             -- casts shown at once
local MAX_CAST = 12         -- seconds before a row gives up on a cast that never said it ended

local anchor
local casts = {}            -- slot -> { unit, started }
module.casts = casts

local function Settings()
  return ns.db.modules.Kicks
end

local function Secret(v)
  return issecretvalue ~= nil and issecretvalue(v)
end

-- Is there a value here? A secret one counts, and is never tested (testing
-- a secret - `x == nil`, `x or y` - is an error on Forever).
local function Present(v)
  if Secret(v) then return true end
  return v ~= nil
end

-- The game's secret yes/no as a number we can hand to SetAlpha, or 1 when
-- the game didn't answer (never branching on the answer itself).
local function AlphaFrom(bool, yes, no)
  if not Present(bool) then return 1 end
  local util = C_CurveUtil
  if util and util.EvaluateColorValueFromBoolean then
    local ok, v = pcall(util.EvaluateColorValueFromBoolean, bool, yes, no)
    if ok then return v end
  end
  if Secret(bool) then return 1 end
  return bool and yes or no
end
module.AlphaFrom = AlphaFrom

local function Ask(fn, spellID)
  if type(fn) ~= "function" or not Present(spellID) then return nil end
  local ok, v = pcall(fn, spellID)
  if ok then return v end   -- not `ok and v or nil`: that tests v, which may be secret
  return nil
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------

local function Row(parent, lane)
  -- outer: shows this lane's kind of cast; inner: the second condition;
  -- bar: dimmed when it can't be kicked.
  local outer = CreateFrame("Frame", nil, parent)
  outer:SetSize(Settings().width, lane.height)
  local inner = CreateFrame("Frame", nil, outer)
  inner:SetAllPoints()
  local bar = CreateFrame("StatusBar", nil, inner)
  bar:SetAllPoints()
  bar:SetStatusBarTexture(ns.Media.StatusBarTexture())
  bar:SetStatusBarColor(lane.color[1], lane.color[2], lane.color[3], 0.85)
  local back = bar:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.7)
  ns.Skin.Border(bar, { lane.color[1], lane.color[2], lane.color[3], 1 })
  local path = ns.Media.Role("general")
  -- The lane's tag, drawn in each row: a header over the lane would show
  -- whenever anything is cast, and whether this cast is a heal is the game's
  -- secret - the row itself only shows when it is.
  local tag = bar:CreateFontString(nil, "OVERLAY")
  tag:SetFont(path, math.max(10, lane.font - 2), "OUTLINE")
  tag:SetPoint("LEFT", 6, 0)
  tag:SetTextColor(1, 1, 1)
  tag:SetText(lane.tag)
  local spell = bar:CreateFontString(nil, "OVERLAY")
  spell:SetFont(path, lane.font, "OUTLINE")
  spell:SetPoint("LEFT", tag, "RIGHT", lane.tag ~= "" and 6 or 0, 0)
  spell:SetJustifyH("LEFT")
  local who = bar:CreateFontString(nil, "OVERLAY")
  who:SetFont(path, math.max(10, lane.font - 3), "OUTLINE")
  who:SetPoint("RIGHT", -6, 0)
  who:SetJustifyH("RIGHT")
  who:SetTextColor(0.9, 0.9, 0.9)
  spell:SetPoint("RIGHT", who, "LEFT", -6, 0)
  outer.inner, outer.bar, outer.spell, outer.who = inner, bar, spell, who
  outer:Hide()
  return outer
end

local function Build()
  anchor = CreateFrame("Frame", "ForeverUIKicks", UIParent)
  anchor:SetSize(Settings().width, 140)
  anchor:SetFrameStrata("HIGH")
  module.anchor = anchor
  local y = 0
  for _, lane in ipairs(LANES) do
    lane.frame = CreateFrame("Frame", nil, anchor)
    lane.frame:SetPoint("TOPLEFT", 0, y)
    lane.frame:SetSize(Settings().width, lane.height * SLOTS)
    lane.rows = {}
    for slot = 1, SLOTS do
      local row = Row(lane.frame, lane)
      row:SetPoint("TOPLEFT", 0, -(slot - 1) * (lane.height + 2))
      lane.rows[slot] = row
    end
    y = y - SLOTS * (lane.height + 2) - 6
  end
  anchor:SetHeight(-y)
  anchor:SetScale(Settings().scale or 1)
  anchor.fuiOwnScale = true   -- its own size slider; the mover leaves it be
  ns.RegisterMover("kicks", "Kick alerts", anchor, { "CENTER", "CENTER", 0, 160 })
  -- Keep each bar filling: its value is the clock, its range the cast.
  anchor:SetScript("OnUpdate", function()
    local now = GetTime() * 1000
    for slot, cast in pairs(casts) do
      if cast then
        for _, lane in ipairs(LANES) do lane.rows[slot].bar:SetValue(now) end
        if GetTime() - cast.started > MAX_CAST then module.EndCast(cast.unit) end
      end
    end
  end)
end

---------------------------------------------------------------------------
-- Casts
---------------------------------------------------------------------------

local function Hostile(unit)
  if not (UnitExists and UnitCanAttack) then return false end
  local okE, exists = pcall(UnitExists, unit)
  if not okE or Secret(exists) or not exists then return false end
  local okA, attackable = pcall(UnitCanAttack, "player", unit)
  return okA and not Secret(attackable) and attackable == true
end

local function SlotFor(unit)
  for slot = 1, SLOTS do
    if casts[slot] and casts[slot].unit == unit then return slot end
  end
  for slot = 1, SLOTS do
    if not casts[slot] then return slot end
  end
  return nil
end

-- Read the cast (all of it secret) and paint the three lanes' rows for it.
function module.StartCast(unit, channel)
  if not ns.IsModuleEnabled("Kicks") or not Hostile(unit) then return false end
  if not anchor then Build() end
  local info = channel and UnitChannelInfo or UnitCastingInfo
  if not info then return false end
  local ok, name, _, _, startMs, endMs, _, a7, a8, a9 = pcall(info, unit)
  if not ok or not Present(name) then return false end
  -- Casts: ..., castID, notInterruptible, spellID. Channels: ..., notInterruptible, spellID.
  local notInterruptible, spellID
  if channel then notInterruptible, spellID = a7, a8 else notInterruptible, spellID = a8, a9 end
  local slot = SlotFor(unit)
  if not slot then return false end
  casts[slot] = { unit = unit, started = GetTime(), channel = channel and true or false }

  local s = Settings()
  local helpful = Ask(C_Spell and C_Spell.IsSpellHelpful, spellID)
  local important = Ask(C_Spell and C_Spell.IsSpellImportant, spellID)
  local caster = nil
  pcall(function() caster = UnitName(unit) end)
  local kickAlpha = 1
  if s.dimUnkickable then kickAlpha = AlphaFrom(notInterruptible, 0.3, 1) end
  for index, lane in ipairs(LANES) do
    local row = lane.rows[slot]
    local on = s[lane.key] ~= false
    -- Never `on and AlphaFrom(...) or 0`: the `or` would test a secret.
    if not on then
      row:SetAlpha(0)
    elseif index == 1 then
      row:SetAlpha(AlphaFrom(helpful, 1, 0))
    else
      row:SetAlpha(AlphaFrom(helpful, 0, 1))
    end
    if index == 1 then
      row.inner:SetAlpha(1)
    elseif index == 2 then
      row.inner:SetAlpha(AlphaFrom(important, 1, 0))
    else
      row.inner:SetAlpha(AlphaFrom(important, 0, 1))
    end
    row.bar:SetAlpha(kickAlpha)
    if Present(startMs) and Present(endMs) then
      pcall(row.bar.SetMinMaxValues, row.bar, startMs, endMs)
    else
      row.bar:SetMinMaxValues(0, 1)
    end
    pcall(row.bar.SetValue, row.bar, GetTime() * 1000)
    row.spell:SetText(name)
    if type(caster) == "string" then row.who:SetText(caster) else row.who:SetText("") end   -- no `or` on a secret
    row:Show()
  end
  anchor:Show()
  return true
end

function module.EndCast(unit)
  for slot = 1, SLOTS do
    local cast = casts[slot]
    if cast and cast.unit == unit then
      casts[slot] = nil
      if anchor then
        for _, lane in ipairs(LANES) do lane.rows[slot]:Hide() end
      end
    end
  end
end

-- Could it be kicked after all (or not)? Repaint that cast.
local function Recheck(unit)
  for slot = 1, SLOTS do
    if casts[slot] and casts[slot].unit == unit then
      module.StartCast(unit, casts[slot].channel)
    end
  end
end

local function Watched(unit)
  return type(unit) == "string" and not Secret(unit) and unit:find("^nameplate%d") ~= nil
end

local events = CreateFrame("Frame")
module.events = events
local STARTS = { UNIT_SPELLCAST_START = false, UNIT_SPELLCAST_CHANNEL_START = true }
local STOPS = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
  UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_STOP = true, NAME_PLATE_UNIT_REMOVED = true }
events:SetScript("OnEvent", function(_, event, unit)
  if not Watched(unit) then return end
  if STARTS[event] ~= nil then
    module.StartCast(unit, STARTS[event])
  elseif STOPS[event] then
    module.EndCast(unit)
  elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
    Recheck(unit)
  end
end)

function module:OnEnable()
  -- These came on by default for a day (24 Sept 2026); now they're opt-in.
  -- Anyone who had them on only because of that gets them switched off once.
  if ns.db and not ns.db.kicksOptIn then
    ns.db.kicksOptIn = true
    if ns.SetModuleEnabled and C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        ns.SetModuleEnabled("Kicks", false)
        ns.Print("kick priority now shows on the enemy's own cast bar (green heals, red important). "
          .. "The alerts in the middle of the screen are off - /fui kicks to turn them back on.")
      end)
      return
    end
  end
  for event in pairs(STARTS) do pcall(events.RegisterEvent, events, event) end
  for event in pairs(STOPS) do pcall(events.RegisterEvent, events, event) end
  pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_INTERRUPTIBLE")
  pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
  if not anchor then Build() end
end

function module:OnDisable()
  events:UnregisterAllEvents()
  for slot in pairs(casts) do casts[slot] = nil end
  if anchor then
    for _, lane in ipairs(LANES) do
      for _, row in ipairs(lane.rows) do row:Hide() end
    end
  end
end

function module:Refresh()
  if anchor then anchor:SetScale(Settings().scale or 1) end
end

-- A made-up cast in one lane (the live combat test, /fui test combat):
-- plain values, so it goes straight into the lane it names. Returns the slot.
function module.SimCast(laneIndex, spell, caster, seconds, kickable)
  if not anchor then Build() end
  local slot
  for i = 1, SLOTS do if not casts[i] then slot = i break end end
  if not slot then return nil end
  local unit = "sim" .. slot
  casts[slot] = { unit = unit, started = GetTime(), channel = false }
  local now = GetTime() * 1000
  for index, lane in ipairs(LANES) do
    local row = lane.rows[slot]
    row:SetAlpha((index == laneIndex and Settings()[lane.key] ~= false) and 1 or 0)
    row.inner:SetAlpha(1)
    row.bar:SetAlpha((kickable == false and Settings().dimUnkickable) and 0.3 or 1)
    row.bar:SetMinMaxValues(now, now + seconds * 1000)
    row.bar:SetValue(now)
    row.spell:SetText(spell)
    row.who:SetText(caster)
    row:Show()
  end
  anchor:Show()
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, function() module.EndCast(unit) end)
  end
  return slot
end

-- A look at it without a fight: one of each, made up (plain values).
function module.Test()
  if not anchor then Build() end
  local samples = { { "Healing Wave", "Kolkar Stormer" }, { "Lightning Bolt", "Windfury Sorceress" },
    { "Frostbolt", "Windfury Sorceress" } }
  for index, lane in ipairs(LANES) do
    local row = lane.rows[1]
    row:SetAlpha(1); row.inner:SetAlpha(1); row.bar:SetAlpha(1)
    row.bar:SetMinMaxValues(0, 1); row.bar:SetValue(0.6)
    row.spell:SetText(samples[index][1]); row.who:SetText(samples[index][2])
    row:Show()
  end
  anchor:Show()
  if C_Timer and C_Timer.After then
    C_Timer.After(6, function()
      if not next(casts) then
        for _, lane in ipairs(LANES) do lane.rows[1]:Hide() end
      end
    end)
  end
end

local function Percent(v)
  return ("%d%%"):format(math.floor((v or 1) * 100 + 0.5))
end

module.options = {
  { type = "heading", label = "Kick Alerts", subtitle = "Enemy casts to interrupt, heals first", icon = "target" },
  { type = "checkbox", switch = true, key = "enabled", label = "Kick alerts in the middle of the screen",
    desc = "The nameplate cast bars show the same priority on the enemy itself (Cast Bar tab).",
    get = function() return ns.IsModuleEnabled("Kicks") end,
    set = function(on) ns.db.kicksOptIn = true; ns.SetModuleEnabled("Kicks", on) end },
  { type = "note", label = "Watches enemies with a nameplate. Heals (spells cast on friends) go in the top "
    .. "lane, spells the game marks as important under them, everything else small at the bottom. Forever "
    .. "keeps enemy casts secret from addons, so the game itself decides which lane a cast belongs in." },
  { type = "checkbox", key = "heals", label = "Heal lane (green)" },
  { type = "checkbox", key = "important", label = "Important lane (red)" },
  { type = "checkbox", key = "others", label = "Every other cast (small, amber)" },
  { type = "checkbox", key = "dimUnkickable", label = "Fade casts that can't be interrupted" },
  { type = "stepper", slider = true, key = "scale", label = "Size", min = 0.6, max = 1.8, step = 0.05,
    format = Percent },
  { type = "action", label = "Show a test", width = 200, icon = "target",
    desc = "One made-up cast in each lane for six seconds. Move it with /fui move.",
    onClick = function() module.Test() end },
}

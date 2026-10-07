local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- HoTs you can't see.
--
-- In a fight Forever won't let an addon read auras, so the HoT row and the
-- watch corners go dark at exactly the moment they matter. But nothing stops
-- us knowing what WE just did: you clicked Renew on the tank's frame, the game
-- said the cast succeeded, Renew lasts fifteen seconds. That is enough to draw
-- the icon and count it down without ever reading an aura.
--
-- What this can't know: another healer's HoTs, a shield that broke early, a
-- dispel. It only ever fills in while auras are unreadable; the moment they
-- can be read again the real thing takes over.

local PENDING_FOR = 4      -- seconds a click waits for its "cast succeeded"
local MAX_DURATION = 3600

-- Classic durations, used until the real one has been seen. Out of combat the
-- true duration of every HoT of yours is written down as it goes by, so
-- talents and whatever Forever changed correct these by themselves.
ns.SEED_DURATIONS = {
  ["Renew"] = 15, ["Power Word: Shield"] = 30, ["Weakened Soul"] = 15,
  ["Rejuvenation"] = 12, ["Regrowth"] = 21, ["Abolish Poison"] = 8,
  ["Abolish Disease"] = 20, ["Fear Ward"] = 600,
}

-- Casting one puts the other on the target as well.
local LINKED = { ["Power Word: Shield"] = { "Weakened Soul" } }
ns.LINKED_AURAS = LINKED   -- translated with the rest (SpellData.lua)

local inferred = {}   -- [player name] = { [spell] = { icon, expires, duration } }
local pending         -- the last click: { name, spell, at }
local sentTo = {}     -- [castGUID] = target name, from UNIT_SPELLCAST_SENT
local lastSent        -- the last cast sent: { target, spell, at } - when the GUID is hidden
local barCast         -- the last action-bar press: { spell, at } (ForeverUI's own bars)
ns.inferStats = { clicks = 0, applied = 0, unreadable = 0 }

local function Readable(value)
  return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- A secret name must never reach :match - it throws, and the pcall around
-- the cast handlers swallowed that silently, which is why nothing was ever
-- remembered in a group.
local function Short(name)
  return type(name) == "string" and Readable(name) and name:match("^[^-]+") or nil
end

-- Who a frame is, for remembering what you put on them. The name when the
-- game shows it (solo); in a group Forever hides every name, so the frame's
-- unit ("party2", "raid7") stands in - the click and the frame drawing it
-- agree on that as well as they would on a name.
function ns.InferKey(state)
  if not state then return nil end
  return Short(state.name) or (Readable(state.unit) and state.unit) or nil
end

function ns.SpellDuration(spell)
  local learned = ns.db.learnedDurations and ns.db.learnedDurations[spell]
  return learned or ns.SEED_DURATIONS[spell]
end

-- Called with every aura of yours that could be read, so the table above is
-- only ever a starting point.
function ns.LearnDuration(spell, duration)
  if type(spell) ~= "string" or type(duration) ~= "number" or duration <= 0 or duration > MAX_DURATION then
    return
  end
  ns.db.learnedDurations = ns.db.learnedDurations or {}
  duration = math.floor(duration + 0.5)
  if ns.db.learnedDurations[spell] ~= duration then
    ns.db.learnedDurations[spell] = duration
  end
end

local function Icon(spell)
  local _, byName = ns.ScanSpellbook(true)
  return byName[spell] and byName[spell].icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function ns.InferAura(name, spell, now)
  name = Short(name)
  local duration = name and ns.SpellDuration(spell)
  if not duration then
    return false
  end
  now = now or GetTime()
  inferred[name] = inferred[name] or {}
  inferred[name][spell] = { icon = Icon(spell), expires = now + duration, duration = duration }
  for _, other in ipairs(LINKED[spell] or {}) do
    ns.InferAura(name, other, now)
  end
  ns.inferStats.applied = ns.inferStats.applied + 1
  return true
end

-- What we believe is on this player right now: spell -> { icon, expires, duration }.
function ns.InferredAuras(name, now)
  local auras = inferred[Short(name) or ""]
  if not auras then
    return nil
  end
  now = now or GetTime()
  for spell, aura in pairs(auras) do
    if aura.expires <= now then
      auras[spell] = nil
    end
  end
  return next(auras) and auras or nil
end

function ns.ForgetInferred(name)
  if name then
    inferred[Short(name) or ""] = nil
  else
    inferred = {}
  end
end

---------------------------------------------------------------------------
-- Knowing what you cast, and on whom
---------------------------------------------------------------------------

-- A click on one of our frames: the frame says who, the binding says what.
function ns.NoteClick(button, mouseButton)
  local unitButton = button
  if button.isWheelButton then
    unitButton = ns.hoverButton -- the wheel casts on whoever the mouse is over
  end
  local state = unitButton and unitButton.state
  local name = ns.InferKey(state)
      or (unitButton and Readable(unitButton.unit) and unitButton.unit) or nil
  local key
  if type(mouseButton) == "string" and mouseButton:find("^hfwheel") then
    key = ns.ModifierPrefix() .. mouseButton:sub(3)
  else
    key = ns.KeyFromClick(mouseButton)
  end
  local binding = key and ns.db.bindings[key]
  if not name or not binding or binding.kind ~= "spell" then
    return
  end
  ns.inferStats.clicks = ns.inferStats.clicks + 1
  pending = { name = name, spell = binding.spell, at = GetTime() }
end

function ns.HookCasts(button)
  if button.hfCastHooked or not button.HookScript then
    return
  end
  button.hfCastHooked = true
  button:HookScript("PostClick", function(self, mouseButton) ns.NoteClick(self, mouseButton) end)
end

local function SpellName(spellID)
  if not Readable(spellID) then
    return nil
  end
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(spellID)
  elseif GetSpellInfo then
    return (GetSpellInfo(spellID))
  end
end

-- A spell pressed on one of ForeverUI's own action bars (ActionBars.lua calls
-- this before the click goes through). In a fight the game hides which spell
-- a cast was; the button you pressed doesn't.
function ns.NoteBarCast(spell)
  if type(spell) == "string" and spell ~= "" then
    barCast = { spell = spell, at = GetTime() }
  end
end

local function Fresh(note, now)
  return note and now - note.at <= PENDING_FOR and note or nil
end

-- Who a helpful spell lands on when the game won't say: the game's own rule.
-- A friendly target gets it; with no target, or an enemy targeted, it goes on
-- you. Every question here can come back secret in a group - then we don't
-- guess at all.
local function AutoTarget()
  local ok, name = pcall(function()
    if UnitExists and UnitExists("target") then
      local friendly = UnitCanAssist and UnitCanAssist("player", "target")
      if not Readable(friendly) then
        return nil
      end
      if friendly then
        local targetName = UnitName("target")
        return Readable(targetName) and targetName or nil
      end
    end
    local me = UnitName("player")
    -- Hidden in a group: your own frame there is "player" too.
    return Readable(me) and me or "player"
  end)
  return ok and name or nil
end
ns.AutoTarget = AutoTarget

local function OnSent(target, castGUID, spellID)
  local named = Readable(target) and target ~= "" and target or nil
  if named and Readable(castGUID) then
    sentTo[castGUID] = named
  else
    ns.inferStats.unreadable = ns.inferStats.unreadable + 1
  end
  lastSent = { target = named, spell = SpellName(spellID), at = GetTime() }
end

-- Every source of "what" and "who", best first. What: the game's spell ID,
-- then the spell of the send, the bar press or the frame click. Who: the
-- send's own target by GUID, the frame you clicked, the send's target, and
-- last the game's self-cast rule. Only a spell with a known duration becomes
-- an aura, so a Wrath or a Maul never lights anything.
local function OnSucceeded(castGUID, spellID)
  local now = GetTime()
  local click, sent, bar = Fresh(pending, now), Fresh(lastSent, now), Fresh(barCast, now)
  local spell = SpellName(spellID) or (sent and sent.spell) or (bar and bar.spell)
    or (click and click.spell)
  local target = Readable(castGUID) and sentTo[castGUID] or nil
  if Readable(castGUID) then
    sentTo[castGUID] = nil
  end
  if not target and click and (not spell or spell == click.spell) then
    target, spell = click.name, spell or click.spell
  end
  target = target or (sent and sent.target)
  if spell and not target and ns.SpellDuration(spell) then
    target = AutoTarget()
  end
  pending, lastSent, barCast = nil, nil, nil
  if not (spell and target) or not ns.InferAura(target, spell, now) then
    return
  end
  ns.RefreshAll()
end

-- Always listening, whichever role is current: the casts are yours whatever
-- window is open, and each grid decides for itself whether to show them.
local function OnEvent(_, event, unit, a, b, c)
  if unit ~= "player" or not ns.db then
    return
  end
  if event == "UNIT_SPELLCAST_SENT" then
    pcall(OnSent, a, b, c)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    pcall(OnSucceeded, a, b)
  else
    pending = nil -- failed or interrupted: nothing landed
  end
end
ns.InferenceEvent = OnEvent

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", OnEvent)
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
  if ns.RegisterEvent then
    ns.RegisterEvent(watcher, event)
  else
    pcall(watcher.RegisterEvent, watcher, event)
  end
end

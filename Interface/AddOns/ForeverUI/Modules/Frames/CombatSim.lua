local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- A pretend fight, for building and checking the frames solo.
--
-- /fui test group shows a pretend party or raid standing still. This makes
-- it fight: the tanks take steady hits, a raid-wide blast lands every few
-- seconds, random players spike, dispellable debuffs go out, people die and
-- are brought back, "other healers" top people up, HoTs tick down and are
-- put back on, and threat moves - someone pulls now and then. Enemy casts go
-- into the kick alerts (heals, important, the rest). Click a pretend player
-- and your spell really goes off on you, as before - and the one you clicked
-- is healed, so click-casting can be tried in the middle of it.
--
-- A small panel in the corner says what is going on and what it costs: how
-- long each redraw of every frame took, so 40 frames can be judged.
--
--   /fui test combat 5 | 10 | 20 | 40     start (or change size)
--   /fui test combat off                  stop, back to the real group
--
-- A developer's tool: it never touches a real unit, and nothing it does is
-- saved. The fight is driven by a seeded random, so a size plays the same
-- way each time it starts.

local TICK = 0.25           -- seconds between steps of the fight
local AOE_EVERY = 8         -- seconds between raid-wide blasts
local CAST_EVERY = 3.5      -- seconds between enemy casts for the kick alerts

local sim                   -- the running fight, or nil
ns.combatSim = nil

local HOTS = {
  "Interface\\Icons\\Spell_Nature_Rejuvenation",
  "Interface\\Icons\\Spell_Nature_ResistNature",
  "Interface\\Icons\\Spell_Holy_Renew",
  "Interface\\Icons\\Spell_Holy_PowerWordShield",
}
local DISPELS = {
  { "Magic", "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
  { "Poison", "Interface\\Icons\\Spell_Nature_CorrosiveBreath" },
  { "Curse", "Interface\\Icons\\Spell_Shadow_CurseOfTounges" },
  { "Disease", "Interface\\Icons\\Spell_Shadow_CallofBone" },
}
-- Enemy casts: which kick lane (1 heals, 2 important, 3 the rest), how long.
local CASTS = {
  { "Healing Wave", "Kolkar Stormer", 1, 2.5 },
  { "Renew", "Scarlet Chaplain", 1, 2.0 },
  { "Chain Lightning", "Windfury Matriarch", 2, 2.5 },
  { "Fear", "Defias Evoker", 2, 1.5 },
  { "Frostbolt", "Windfury Sorceress", 3, 3.0 },
  { "Shadow Bolt", "Defias Evoker", 3, 2.5 },
  { "Shield Wall", "Razorfen Defender", 3, 1.5, false },
}

-- A small seeded random (the same fight every time for a size).
local function Random(state)
  state.seed = (state.seed * 1103515245 + 12345) % 2147483648
  return state.seed / 2147483648
end

local function Pick(state, n)
  return math.floor(Random(state) * n) + 1
end

---------------------------------------------------------------------------
-- The fight
---------------------------------------------------------------------------

local function Alive(m) return not m.dead and not m.offline end

local function Damage(m, amount)
  if not Alive(m) then return end
  m.health = m.health - math.floor(amount)
  if m.health <= 0 then
    m.health, m.dead, m.diedAt = 0, true, sim.clock
    m.hots, m.dispelType, m.dispelIcon, m.incomingMine, m.incomingOthers = nil, nil, nil, nil, nil
    sim.deaths = sim.deaths + 1
  end
end

local function Heal(m, amount)
  if not Alive(m) then return end
  m.health = math.min(m.healthMax, m.health + math.floor(amount))
end

local function Step(dt)
  local s = sim
  s.clock = s.clock + dt
  local members = s.members
  local n = #members

  -- The tanks take a steady beating; one DPS or healer gets clipped.
  for i = 1, math.min(2, n) do Damage(members[i], members[i].healthMax * 0.035 * (0.6 + Random(s))) end
  if Random(s) < 0.35 then
    local m = members[Pick(s, n)]
    Damage(m, m.healthMax * (0.08 + Random(s) * 0.22))
  end

  -- The raid-wide blast.
  s.nextAoe = s.nextAoe - dt
  if s.nextAoe <= 0 then
    s.nextAoe = AOE_EVERY
    for _, m in ipairs(members) do Damage(m, m.healthMax * (0.18 + Random(s) * 0.12)) end
    s.aoes = s.aoes + 1
  end

  -- Debuffs go out, and get cleansed by someone else after a while.
  if Random(s) < 0.06 then
    local m = members[Pick(s, n)]
    if Alive(m) and not m.dispelType then
      local d = DISPELS[Pick(s, #DISPELS)]
      m.dispelType, m.dispelIcon, m.dispelUntil = d[1], d[2], s.clock + 4 + Random(s) * 6
    end
  end

  -- Other healers, HoTs, incoming heals.
  for _, m in ipairs(members) do
    if Alive(m) then
      if m.dispelType and s.clock >= (m.dispelUntil or 0) then m.dispelType, m.dispelIcon = nil, nil end
      if m.dispelType then Damage(m, m.healthMax * 0.01) end
      if m.hots then
        local left = {}
        for _, hot in ipairs(m.hots) do
          hot.remaining = hot.remaining - dt
          if hot.remaining > 0 then
            left[#left + 1] = hot
            Heal(m, m.healthMax * 0.006)
          end
        end
        m.hots = #left > 0 and left or nil
      end
      if Random(s) < 0.05 and (not m.hots or #m.hots < 3) then
        m.hots = m.hots or {}
        m.hots[#m.hots + 1] = { icon = HOTS[Pick(s, #HOTS)], remaining = 9 + Random(s) * 9 }
      end
      if m.health < m.healthMax * 0.55 and Random(s) < 0.10 then
        Heal(m, m.healthMax * (0.15 + Random(s) * 0.2))
      end
      m.incomingOthers = (Random(s) < 0.15) and math.floor(m.healthMax * 0.12) or nil
      m.incomingMine = nil
    elseif m.dead and s.clock - (m.diedAt or 0) > 10 then
      m.dead, m.health = false, math.floor(m.healthMax * 0.4)   -- battle rez / release and run back
    end
  end

  -- Threat: tanks hold it; now and then someone pulls, then the tank taunts back.
  for i, m in ipairs(members) do
    if i <= 2 then m.threat, m.loose = 3, nil
    elseif m.loose and s.clock >= (m.looseUntil or 0) then m.threat, m.loose = nil, nil
    end
  end
  if Random(s) < 0.03 and n > 2 then
    local m = members[2 + Pick(s, n - 2)]
    if Alive(m) then m.threat, m.loose, m.looseUntil = 3, true, s.clock + 3 end
  end

  -- Out of range now and then (someone ran off).
  if Random(s) < 0.04 then
    local m = members[Pick(s, n)]
    m.inRange = not m.inRange
  end

  -- An enemy cast for the kick alerts.
  s.nextCast = s.nextCast - dt
  if s.nextCast <= 0 then
    s.nextCast = CAST_EVERY
    local kicks = FUI.GetModule and FUI.GetModule("Kicks")
    if kicks and kicks.SimCast and FUI.IsModuleEnabled and FUI.IsModuleEnabled("Kicks") then
      local c = CASTS[Pick(s, #CASTS)]
      kicks.SimCast(c[3], c[1], c[2], c[4], c[5])
      s.casts = s.casts + 1
    end
  end
end

-- Redraw every pretend frame on every grid, timing it.
local function Draw()
  local started = debugprofilestop and debugprofilestop()
  local drawn = 0
  for _, role in ipairs(ns.ShownGrids and ns.ShownGrids() or {}) do
    for i, button in ipairs(ns.SimButtons(role)) do
      local m = sim.members[i]
      if m and button:IsShown() then
        ns.RenderSimButton(button, m)
        drawn = drawn + 1
      end
    end
  end
  if started then
    local ms = debugprofilestop() - started
    sim.lastMs = ms
    sim.worstMs = math.max(sim.worstMs, ms)
    sim.totalMs, sim.draws = sim.totalMs + ms, sim.draws + 1
  end
  sim.drawn = drawn
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local panel
local function Panel()
  if panel then return panel end
  panel = CreateFrame("Frame", "ForeverUICombatSim", UIParent)
  panel:SetSize(230, 96)
  panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -120)
  panel:SetFrameStrata("HIGH")
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.75)
  panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.text:SetPoint("TOPLEFT", 8, -8)
  panel.text:SetJustifyH("LEFT")
  panel:Hide()
  return panel
end

local function PanelText()
  local dead = 0
  for _, m in ipairs(sim.members) do if m.dead then dead = dead + 1 end end
  return ("|cffffd100Combat test|r  %d-man   %ds\n"
    .. "dead now %d  (deaths %d)\n"
    .. "next AoE %.0fs   enemy casts %d\n"
    .. "redraw %d frames: %.2f ms (avg %.2f, worst %.2f)\n"
    .. "|cff999999/fui test combat off|r"):format(
    #sim.members, math.floor(sim.clock), dead, sim.deaths, sim.nextAoe, sim.casts,
    sim.drawn or 0, sim.lastMs or 0, (sim.draws > 0 and sim.totalMs / sim.draws or 0), sim.worstMs)
end
ns.CombatSimText = function() return sim and PanelText() or nil end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
  if not sim then return end
  since = since + elapsed
  if since < TICK then return end
  local dt = since
  since = 0
  Step(dt)
  Draw()
  if panel then panel.text:SetText(PanelText()) end
end)
ticker:Hide()

-- Clicking a pretend player heals them (on top of your spell going off on you).
local hooked = {}
local function HookClicks()
  for _, role in ipairs(ns.ShownGrids and ns.ShownGrids() or {}) do
    for i, button in ipairs(ns.SimButtons(role)) do
      if not hooked[button] and button.HookScript then
        hooked[button] = true
        button:HookScript("PostClick", function()
          local m = sim and sim.members[i]
          if m then Heal(m, m.healthMax * 0.3) end
        end)
      end
    end
  end
end

function ns.StartCombatSim(size)
  size = math.floor(tonumber(size) or 5)
  size = math.max(2, math.min(40, size))
  if not ns.SimulateGroup(size) then return false end
  sim = { members = {}, clock = 0, seed = 1000 + size, nextAoe = AOE_EVERY, nextCast = 1,
    deaths = 0, aoes = 0, casts = 0, worstMs = 0, totalMs = 0, draws = 0 }
  ns.combatSim = sim
  for i = 1, size do
    local m = ns.SimMember(i)
    m.dead, m.offline, m.isTarget = false, false, (i == 3)
    m.health = m.healthMax
    m.hots, m.dispelType, m.dispelIcon, m.threat, m.loose = nil, nil, nil, nil, nil
    sim.members[i] = m
  end
  HookClicks()
  Panel():Show()
  panel.text:SetText(PanelText())
  since = 0
  ticker:Show()
  ns.Print(("combat test: %d-man fight running. Click a pretend player to heal them. |cffffd100/fui test combat off|r to stop.")
    :format(size))
  return true
end

function ns.StopCombatSim()
  if not sim then return false end
  sim, ns.combatSim = nil, nil
  ticker:Hide()
  if panel then panel:Hide() end
  ns.StopSimulating()
  return true
end

function ns.CombatSimRunning()
  return sim ~= nil
end

-- For the tests: step the fight by hand.
function ns.CombatSimStep(dt)
  if not sim then return false end
  Step(dt or TICK)
  Draw()
  return true
end

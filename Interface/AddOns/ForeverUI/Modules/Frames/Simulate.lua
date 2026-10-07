local _, FUI = ...
FUI.Frames = FUI.Frames or {}
local ns = FUI.Frames

-- A pretend group, for testing the grids solo.
--
-- Alone, a party grid shows one frame: you. That is no way to see how five
-- or forty look, what a dispel or a HoT row or a loose mob looks like on the
-- tank grid, or whether a click actually casts. So this fills every grid on
-- screen with a made-up group, drawn exactly where the real frames would be,
-- in each grid's own look.
--
-- The made-up members are real click-casting buttons pointed at YOU. Click
-- one with any binding and the spell really goes off -- on yourself -- so the
-- test is of your actual Heal, Tank or DPS clicks, not a picture of them.
--
-- What they are careful NOT to be is part of the engine. A unit button hands
-- itself to the engine the moment it gets a unit, and the engine would then
-- redraw it from your real health and name. So these drop that script before
-- they are given one, and the engine never hears of them.
--
--   /fui test group            a party of five, on every grid on screen
--   /fui test group 10|25|40   a raid of that size
--   /fui test group off        back to the real group

local BUTTON_SPACING = 2
local GROUP_GAP = 6
local sims = {}          -- role -> { buttons = {}, size = n }
local active = nil       -- size, while simulating

-- Forty names and classes. The first two are the tanks, the next few heal.
local CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "DRUID", "SHAMAN", "ROGUE", "MAGE", "WARLOCK", "HUNTER" }
local NAMES = {
  "Tankadin", "Shieldwall", "Holyfire", "Leafsong", "Tidecall", "Stabsworth", "Pyroblast", "Felgrip",
  "Afkhunter", "Skuri", "Kupho", "Shado", "Panz", "Cons", "Felo", "Elro", "Phal", "Vera", "Isht",
  "Miss", "Adel", "Veno", "Ereg", "Shur", "Emer", "Badw", "Zala", "Fura", "Vini", "Elec", "Gale",
  "Arax", "Dorl", "Brem", "Tolk", "Wyra", "Oska", "Quen", "Yarl", "Nimb",
}
local HOT_ICONS = {
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

-- One member's state, the same shape ReadUnit makes for a real unit. Fixed
-- by index, so the same person looks the same every time you test.
function ns.SimMember(i)
  local healthMax = 1100 + (i * 173) % 1400
  local fraction = 0.25 + ((i * 37) % 76) / 100
  local s = {
    name = NAMES[(i - 1) % #NAMES + 1],
    class = i <= 2 and (i == 1 and "PALADIN" or "WARRIOR") or CLASSES[(i * 5) % #CLASSES + 1],
    healthMax = healthMax,
    health = math.floor(healthMax * math.min(1, fraction)),
    inRange = i % 9 ~= 0,
    role = i <= 2 and "TANK" or (i <= 5 and "HEALER" or "DAMAGER"),
    isTank = i <= 2,
  }
  if i == 7 then s.dead, s.health = true, 0 end
  if i == 11 then s.offline = true end
  if i == 3 then s.isTarget = true end
  if i % 4 == 1 then s.incomingMine = math.floor(healthMax * 0.18) end
  if i % 6 == 2 then s.incomingOthers = math.floor(healthMax * 0.12) end
  if i % 3 == 0 then
    local dispel = DISPELS[math.floor(i / 3) % #DISPELS + 1]
    s.dispelType, s.dispelIcon = dispel[1], dispel[2]
  end
  if i % 2 == 1 and not s.dead then
    s.hots = {}
    for h = 1, 1 + (i % 3) do
      s.hots[h] = { icon = HOT_ICONS[(i + h) % #HOT_ICONS + 1], remaining = 4 + (i * h * 3) % 18 }
    end
  end
  -- Threat: the tanks hold it, one DPS has pulled, one healer is being hit.
  if i <= 2 then s.threat = 3 end
  if i == 6 then s.threat, s.loose = 3, true end
  if i == 4 then s.threat, s.loose = 2, true end
  return s
end

local function RenderSim(button, s)
  s.hotCount = s.hots and #s.hots or 0
  local now = GetTime and GetTime() or 0
  for _, hot in ipairs(s.hots or {}) do
    hot.expires = now + hot.remaining
  end
  local ok, err = pcall(ns.Render, button, s)
  if not ok and ns.RecordError then
    ns.RecordError("simulated group: " .. tostring(err), "")
  end
end

ns.RenderSimButton = RenderSim   -- the live combat test (CombatSim.lua) redraws with it

-- A button that clicks like a real frame and is invisible to the engine.
local function SimButton(set, role, index)
  local name = ("ForeverUIFramesSim%s%d"):format(role, index)
  local button = _G[name] or CreateFrame("Button", name, set.anchor, "ForeverUIFramesUnitButtonTemplate")
  button:SetScript("OnAttributeChanged", nil)   -- before the unit: never join the engine
  button.gridRole = role
  button.simulated = true
  button:SetAttribute("unit", "player")         -- every click lands on you
  return button
end

-- Where button `i` of `size` goes, relative to the grid's anchor: the party
-- list for five, the raid groups beyond that, exactly as the real ones.
local function Place(button, i, size)
  local w, h = ns.db.frameWidth, ns.db.frameHeight
  button:SetSize(w, h)
  button:ClearAllPoints()
  local anchor = button:GetParent()
  local horizontal = ns.db.horizontal
  if size <= 5 then
    local step = i - 1
    if horizontal then
      button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", step * (w + BUTTON_SPACING), -BUTTON_SPACING)
    else
      button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -BUTTON_SPACING - step * (h + BUTTON_SPACING))
    end
    return
  end
  local group = math.floor((i - 1) / 5) + 1
  local slot = (i - 1) % 5
  local x, y
  if ns.GroupOffset then
    x, y = ns.GroupOffset(group, ns.db.groupsPerRow or 8)
  else
    x, y = (group - 1) * (w + GROUP_GAP), -BUTTON_SPACING
  end
  if horizontal then
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x + slot * (w + BUTTON_SPACING), y)
  else
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y - slot * (h + BUTTON_SPACING))
  end
end

-- The real headers step aside while the pretend group is up, and come back
-- through the engine's own visibility rules when it goes.
local function HideRealFrames(set)
  for _, header in ipairs({ set.header, set.petHeader }) do
    if header then RegisterAttributeDriver(header, "state-visibility", "hide") end
  end
  for _, header in ipairs(set.raidHeaders or {}) do
    RegisterAttributeDriver(header, "state-visibility", "hide")
  end
end

local function Build(role, size)
  local set = ns.GridSet(role)
  if not set.anchor then
    return 0
  end
  local sim = sims[role] or { buttons = {} }
  sims[role] = sim
  local built = 0
  ns.WithGrid(role, function()
    HideRealFrames(set)
    for i = 1, size do
      local button = sim.buttons[i] or SimButton(set, role, i)
      sim.buttons[i] = button
      Place(button, i, size)
      if ns.BindButton then ns.BindButton(button) end
      button:Show()
      RenderSim(button, ns.SimMember(i))
      built = built + 1
    end
    for i = size + 1, #sim.buttons do
      sim.buttons[i]:Hide()
    end
  end)
  sim.size = size
  return built
end

function ns.SimulatingGroup()
  return active
end

-- The pretend buttons for one grid, for the tests and for anyone poking.
function ns.SimButtons(role)
  return sims[role] and sims[role].buttons or {}
end

function ns.SimulateGroup(size)
  size = math.floor(tonumber(size) or 5)
  size = math.max(2, math.min(40, size))
  if InCombatLockdown() then
    ns.Print("not in combat -- these are real click-casting buttons, and the game only builds those out of combat.")
    return false
  end
  local roles = ns.ShownGrids and ns.ShownGrids() or { ns.GetMode() }
  if #roles == 0 then
    ns.Print("no grid is on screen to fill -- switch one on first (/fui grids).")
    return false
  end
  local total = 0
  for _, role in ipairs(roles) do
    total = total + Build(role, size)
  end
  active = size
  ns.Print(("pretend %s of %d on %d grid%s. Clicks cast on you. |cffffd100/fui test group off|r to stop.")
    :format(size <= 5 and "party" or "raid", size, #roles, #roles == 1 and "" or "s"))
  return total
end

function ns.StopSimulating()
  if not active then
    return false
  end
  if InCombatLockdown() then
    ns.Print("it will go when the fight ends.")
    ns.WhenOutOfCombat(ns.StopSimulating)
    return false
  end
  for role, sim in pairs(sims) do
    for _, button in ipairs(sim.buttons) do
      button:Hide()
    end
    ns.WithGrid(role, function()
      if ns.ApplyVisibility then ns.ApplyVisibility() end
    end)
  end
  active = nil
  ns.Print("back to your real group.")
  return true
end

local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Incoming heals, dispellable debuffs and your HoTs. None uses a class list:
--   * incoming heals come from the game (UnitGetIncomingHeals), split into
--     yours and everyone else's so healers don't double up;
--   * "dispellable" is whatever the game returns for the HARMFUL|RAID filter,
--     which is "debuffs this player can remove" - the same filter Blizzard's
--     own raid frames use. Forever's class reworks change that list, not us.
--
-- Classic Era's heal prediction covers cast-time heals. HoTs aren't predicted
-- by the game; that needs LibHealComm and every healer in the group running it.

-- The health bar is the frame width minus the 1px edge on each side.
local function BarWidth() return ns.db.frameWidth - 2 end

local DISPEL_FILTER = "HARMFUL|RAID"

-- Standard debuff colours; the order decides which one shows when several are on a unit.
local DISPEL_ORDER = { "Magic", "Curse", "Disease", "Poison" }
ns.DISPEL_COLORS = {
  Magic   = { 0.20, 0.60, 1.00 },
  Curse   = { 0.60, 0.00, 1.00 },
  Disease = { 0.60, 0.40, 0.00 },
  Poison  = { 0.00, 0.60, 0.00 },
}
local DISPEL_RANK = {}
for i, kind in ipairs(DISPEL_ORDER) do
  DISPEL_RANK[kind] = i
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- Mana, rage, energy: whatever this unit uses.
ns.POWER_COLORS = {
  MANA = { 0.25, 0.45, 0.95 },
  RAGE = { 0.78, 0.20, 0.20 },
  ENERGY = { 0.95, 0.85, 0.25 },
  FOCUS = { 0.90, 0.55, 0.25 },
  RUNIC_POWER = { 0.35, 0.70, 0.90 },
}

-- Classic has no specs, so a "role" is what the raid assigned, with the
-- modern role API used when a client offers it.
ns.ROLE_MARKS = {
  MAINTANK  = { "T", 0.55, 0.75, 1.00 },
  MAINASSIST = { "A", 0.75, 0.75, 1.00 },
  TANK      = { "T", 0.55, 0.75, 1.00 },
  HEALER    = { "H", 0.45, 0.95, 0.55 },
  DAMAGER   = { "D", 1.00, 0.65, 0.55 },
  -- Set by hand only: the game has no idea who stands next to the boss.
  MELEE     = { "M", 1.00, 0.65, 0.55 },
  RANGED    = { "R", 0.80, 0.65, 1.00 },
}

-- Roles come from group APIs, which can answer with secret values once you're
-- actually in a group. The whole lookup runs protected: no role is a marker
-- that doesn't show, an error here was every frame failing to draw.
local function LookUpRole(unit)
  if GetPartyAssignment then
    if GetPartyAssignment("MAINTANK", unit) then
      return "MAINTANK"
    elseif GetPartyAssignment("MAINASSIST", unit) then
      return "MAINASSIST"
    end
  end
  if UnitGroupRolesAssigned then
    local assigned = UnitGroupRolesAssigned(unit)
    if assigned and assigned ~= "NONE" then
      return assigned
    end
  end
  return nil
end

-- Classic rarely knows anyone's role: there are no specs to read and nobody
-- sets Main Tank in a five-man. So a role you set by hand always wins, and
-- the game's own answer fills in when you haven't.
function ns.ReadRole(unit, s)
  -- A secret name (anyone else, in a group) can't be a table key: no hand-set
  -- role for them then, the game's answer instead.
  local name = s.name
  if issecretvalue and issecretvalue(name) then name = nil end
  local manual = name and ns.db.manualRoles and ns.db.manualRoles[name]
  if manual and ns.ROLE_MARKS[manual] then
    s.role, s.roleManual = manual, true
    return
  end
  local ok, role = pcall(LookUpRole, unit)
  s.role = ok and ns.ROLE_MARKS[role] and role or nil
  s.roleManual = nil
end

local ROLE_CYCLE = { "TANK", "MELEE", "HEALER", "RANGED" } -- then back to automatic

-- role: "TANK" | "HEALER" | "DAMAGER", or nil to hand the decision back.
function ns.SetManualRole(name, role)
  if not name or name == "" then
    return false
  end
  ns.db.manualRoles = ns.db.manualRoles or {}
  ns.db.manualRoles[name] = ns.ROLE_MARKS[role] and role or nil
  ns.SetSetting("manualRoles", ns.db.manualRoles)
  return true
end

-- You picked a role in the game (right-click your frame > Set Role, or a
-- role check). That is the latest word on what you're playing, so it replaces
-- the role you set by hand on the Roles page - which otherwise wins, and kept
-- a healer badge on a player who had just said "Tank" (owner, 26 Sept 2026).
local GAME_ROLE_FITS = { TANK = { TANK = true }, HEALER = { HEALER = true },
  DAMAGER = { MELEE = true, RANGED = true, DAMAGER = true } }
function ns.AdoptGameRole()
  local ok, assigned = pcall(UnitGroupRolesAssigned or function() return nil end, "player")
  if not ok or type(assigned) ~= "string" or (issecretvalue and issecretvalue(assigned))
    or not GAME_ROLE_FITS[assigned] then
    return false
  end
  local me = UnitName and UnitName("player")
  if type(me) ~= "string" or (issecretvalue and issecretvalue(me)) then
    return false
  end
  local manual = ns.db.manualRoles and ns.db.manualRoles[me]
  if not manual or GAME_ROLE_FITS[assigned][manual] then
    return false
  end
  ns.SetManualRole(me, nil)
  ns.Print(("you're playing %s now (the game's Set Role), so that replaces the role you set on the Roles page.")
    :format(({ TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" })[assigned]))
  return true
end

function ns.CycleManualRole(name)
  local current = ns.db.manualRoles and ns.db.manualRoles[name]
  local nextRole = ROLE_CYCLE[1]
  for i, role in ipairs(ROLE_CYCLE) do
    if role == current then
      nextRole = ROLE_CYCLE[i + 1] -- nil after the last: back to automatic
    end
  end
  ns.SetManualRole(name, nextRole)
  return nextRole
end

---------------------------------------------------------------------------
-- Your own frame order: tank, melee, you, casters - or any other way round
---------------------------------------------------------------------------

local DEFAULT_ORDER = { "TANK", "MELEE", "HEALER", "RANGED" }
-- Where someone goes when nobody has said: a guess from their class, good
-- enough to put a warrior near the tank and a mage near the back.
local CLASS_BUCKET = { WARRIOR = "MELEE", ROGUE = "MELEE", PALADIN = "MELEE", SHAMAN = "MELEE",
  DRUID = "MELEE", HUNTER = "RANGED", MAGE = "RANGED", WARLOCK = "RANGED", PRIEST = "HEALER" }

-- Always all four, each once, whatever a saved profile holds.
function ns.RoleOrder()
  local order, seen = {}, {}
  for _, role in ipairs(ns.db.roleOrder or {}) do
    if not seen[role] and (role == "TANK" or role == "MELEE" or role == "HEALER" or role == "RANGED") then
      seen[role] = true
      order[#order + 1] = role
    end
  end
  for _, role in ipairs(DEFAULT_ORDER) do
    if not seen[role] then
      order[#order + 1] = role
    end
  end
  return order
end

-- The same order in the game's own role words, for a secure header's
-- ASSIGNEDROLE grouping: melee and ranged are both DAMAGER there, placed
-- where the first of them is. Used when names are hidden (in a group), since
-- "My role order" otherwise sorts by a list of names.
function ns.AssignedRoleOrder()
  local out, seen = {}, {}
  for _, role in ipairs(ns.RoleOrder()) do
    local assigned = (role == "MELEE" or role == "RANGED") and "DAMAGER" or role
    if not seen[assigned] then
      seen[assigned] = true
      out[#out + 1] = assigned
    end
  end
  out[#out + 1] = "NONE"
  return table.concat(out, ",")
end

function ns.MoveRoleOrder(index, delta)
  local order = ns.RoleOrder()
  local other = index + delta
  if not order[index] or not order[other] then
    return false
  end
  order[index], order[other] = order[other], order[index]
  ns.SetSetting("roleOrder", order)
  return true
end

-- Which of the four a unit belongs in: what you set, else what the game
-- says, else their class.
function ns.SortBucket(unit, name)
  local role = name and ns.db.manualRoles and
    (ns.db.manualRoles[name] or ns.db.manualRoles[name:match("^[^-]+")])
  if not role then
    local ok, found = pcall(LookUpRole, unit)
    role = ok and found or nil
  end
  if role == "MAINTANK" then
    role = "TANK"
  end
  if role == "TANK" or role == "HEALER" or role == "MELEE" or role == "RANGED" then
    return role
  end
  local class
  if UnitClass then
    local _
    _, class = UnitClass(unit)
  end
  return CLASS_BUCKET[class] or "RANGED"
end

-- The names the group headers are handed, in your order: one list for the
-- party, and one per raid group. Names are spelled the way the header spells
-- them (with the realm when there is one) or it won't find them.
function ns.SortedNameLists()
  local position = {}
  for i, role in ipairs(ns.RoleOrder()) do
    position[role] = i
  end
  local party, groups = {}, {}
  local function entry(unit, fullName)
    local name, realm = UnitName(unit)
    if not name or name == "" then
      return nil
    end
    fullName = fullName or ((realm and realm ~= "") and (name .. "-" .. realm) or name)
    return { name = fullName, rank = position[ns.SortBucket(unit, fullName)] or 9 }
  end
  local function sorted(list)
    table.sort(list, function(a, b)
      if a.rank ~= b.rank then
        return a.rank < b.rank
      end
      return a.name < b.name
    end)
    local names = {}
    for i, item in ipairs(list) do
      names[i] = item.name
    end
    return table.concat(names, ",")
  end

  local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  if IsInRaid and IsInRaid() and GetRaidRosterInfo then
    for i = 1, count do
      local fullName, _, subgroup = GetRaidRosterInfo(i)
      local item = fullName and entry("raid" .. i, fullName)
      if item and subgroup then
        groups[subgroup] = groups[subgroup] or {}
        table.insert(groups[subgroup], item)
      end
    end
  end
  party[1] = entry("player")
  for i = 1, math.min(4, math.max(0, count - 1)) do
    party[#party + 1] = entry("party" .. i)
  end
  local lists = { party = sorted(party), groups = {} }
  for group, list in pairs(groups) do
    lists.groups[group] = sorted(list)
  end
  return lists
end

-- Everyone in your group right now, for the Roles list in the options.
function ns.GroupNames()
  local names, seen = {}, {}
  local function add(unit)
    local name = UnitName and UnitName(unit)
    -- In a group other players' names are SECRET: no comparing, indexing or
    -- :lower() -- "/fui frames role <name>" threw. Those can't be listed.
    if issecretvalue and issecretvalue(name) then return end
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  add("player")
  local inRaid = IsInRaid and IsInRaid()
  local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  for i = 1, inRaid and count or math.max(0, count - 1) do
    add((inRaid and "raid" or "party") .. i)
  end
  return names
end

-- A name typed in chat, matched to someone in the group. Forever names carry
-- a surname ("Solindius Runez") and people type the first one, which would
-- set a role nobody's frame ever looks up. Exact first, ignoring case; then
-- the one member whose first name it is. Otherwise it is kept as typed, for
-- someone not in the group yet.
function ns.ResolveGroupName(typed)
  local wanted = (typed or ""):lower()
  local byFirst
  for _, name in ipairs(ns.GroupNames()) do
    local lower = name:lower()
    if lower == wanted then
      return name
    end
    if lower:match("^(%S+)") == wanted then
      if byFirst then
        return typed -- two people share it: don't guess
      end
      byFirst = name
    end
  end
  return byFirst or typed
end

---------------------------------------------------------------------------
-- Threat: who the mobs are hitting
---------------------------------------------------------------------------

-- UnitThreatSituation: 3 = tanking, 2 = tanking but losing it, 1 = about to
-- pull, 0/nil = nothing. Forever may hide it (there is a
-- C_Secrets.ShouldUnitThreatStateBeSecret), so the comparison runs protected
-- and an answer the client withholds is no border rather than an error.
local THREAT_COLORS = {
  [1] = { 1.00, 0.85, 0.20 },
  [2] = { 1.00, 0.50, 0.10 },
  [3] = { 1.00, 0.10, 0.10 },
}
local HOLDING = { 0.30, 0.76, 1.00 }   -- tank mode: a tank holding it is fine
local MAX_NAMEPLATES = 40

local function ThreatLevel(unit)
  local status = UnitThreatSituation(unit)
  if status and status >= 1 then
    return status
  end
  return 0
end

-- How many visible mobs are on this player (tank mode). Ally-against-nameplate
-- is one of the questions the game still answers in a fight.
local function MobsOn(unit)
  local count = 0
  for i = 1, MAX_NAMEPLATES do
    local plate = "nameplate" .. i
    if UnitExists(plate) then
      local status = UnitThreatSituation(unit, plate)
      if status and status >= 2 then
        count = count + 1
      end
    end
  end
  return count
end

-- You, and anyone marked Tank (by you on the Roles page, or by the game).
function ns.IsTankUnit(unit, s)
  if s.role == "TANK" or s.role == "MAINTANK" then
    return true
  end
  local ok, me = pcall(UnitIsUnit, unit, "player")
  return ok and ns.Secrets.Bool(me, false) or false
end

function ns.ReadThreat(unit, s)
  s.threat, s.loose, s.mobCount, s.threatHidden = 0, false, 0, nil
  s.isTank = ns.IsTankUnit(unit, s)
  if not UnitThreatSituation then
    return
  end
  local ok, level = pcall(ThreatLevel, unit)
  if not ok then
    -- Grouped, Forever hides threat levels from addons and the comparison
    -- is refused: RenderThreat falls back to "is your target attacking
    -- them", which the game can answer for us without it being read.
    s.threatHidden = true
    return
  end
  s.threat = level
  -- Tank-mode extras (harmless to compute in healer mode; only tank draws them):
  -- a mob is "loose" when it's on someone who ISN'T a tank.
  s.loose = level >= 2 and not s.isTank
  if s.loose then
    local okCount, count = pcall(MobsOn, unit)
    s.mobCount = okCount and count or 0
  end
end

-- A border just outside the frame, so it can show alongside the dispel colour
-- (which owns the frame's own edge) rather than fighting it for the same line.
local function ThreatBorder(button)
  if button.threatEdges then
    return button.threatEdges
  end
  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local tex = button:CreateTexture(nil, "OVERLAY")
    tex.side = side   -- thickness is set later (SetEdgeThickness), so tank mode can thicken it
    tex:Hide()
    edges[#edges + 1] = tex
  end
  button.threatEdges = edges

  -- Tank-mode overlays: a red wash and an "AGGRO" label on a loose frame. Built
  -- here (once, cheaply) and simply left hidden in healer mode.
  local bar = button.health or button
  button.threatTint = bar:CreateTexture(nil, "ARTWORK", nil, 3)
  button.threatTint:SetAllPoints()
  button.threatTint:SetColorTexture(1, 0.05, 0.05, 0.28)
  button.threatTint:Hide()
  button.threatLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.threatLabel:SetPoint("CENTER", 0, 0)
  button.threatLabel:SetTextColor(1, 1, 1)
  button.threatLabel:Hide()
  return edges
end

-- Edges start with no thickness; this sets it (2px normally, 4px for a loose
-- frame in tank mode). Skips work when the thickness hasn't changed.
local function SetEdgeThickness(button, edges, t)
  if button.threatThickness == t then
    return
  end
  button.threatThickness = t
  for _, tex in ipairs(edges) do
    tex:ClearAllPoints()
    if tex.side == "TOP" then
      tex:SetPoint("BOTTOMLEFT", button, "TOPLEFT", -t, 0); tex:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", t, 0); tex:SetHeight(t)
    elseif tex.side == "BOTTOM" then
      tex:SetPoint("TOPLEFT", button, "BOTTOMLEFT", -t, 0); tex:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", t, 0); tex:SetHeight(t)
    elseif tex.side == "LEFT" then
      tex:SetPoint("TOPRIGHT", button, "TOPLEFT", 0, 0); tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0); tex:SetWidth(t)
    else
      tex:SetPoint("TOPLEFT", button, "TOPRIGHT", 0, 0); tex:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0); tex:SetWidth(t)
    end
  end
end

-- Who has YOUR target, when threat itself is hidden (grouped on Forever).
-- "Is your target's target this player?" comes back as a secret yes/no; the
-- game turns it into an alpha (Secrets.Choose), so the frame lights up on
-- whoever took the mob off you - the paladin who taunted, the mage who pulled
-- - without ForeverUI ever knowing who it was (owner, 26 Sept 2026).
local function RenderTargetHolder(button, s, enabled)
  local unit = button.unit or s.unit
  local show = enabled and unit and not s.isTank and UnitExists
    and ns.Secrets.Bool(UnitExists("targettarget"), false)
  if not show then
    if button.holderTint then
      button.holderTint:Hide()
      button.holderLabel:Hide()
      for _, tex in ipairs(button.holderEdges) do tex:Hide() end
    end
    return
  end
  if not button.holderTint then
    local bar = button.health or button
    button.holderTint = bar:CreateTexture(nil, "ARTWORK", nil, 4)
    button.holderTint:SetAllPoints()
    button.holderTint:SetColorTexture(1, 0.05, 0.05, 0.35)
    button.holderLabel = bar:CreateFontString(nil, "OVERLAY")
    button.holderLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    button.holderLabel:SetPoint("CENTER", bar, "CENTER", 0, 0)
    button.holderLabel:SetTextColor(1, 0.85, 0.85)
    button.holderLabel:SetText("HAS YOUR TARGET")
    button.holderEdges = {}
    -- Four 3-pixel edges just inside the frame: side -> the two corners it joins.
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
      { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
      local tex = button:CreateTexture(nil, "OVERLAY")
      tex:SetColorTexture(1, 0.1, 0.1, 1)
      tex:SetPoint(side[1], button, side[1], 0, 0)
      tex:SetPoint(side[2], button, side[2], 0, 0)
      if side[3] == "h" then tex:SetHeight(3) else tex:SetWidth(3) end
      button.holderEdges[#button.holderEdges + 1] = tex
    end
  end
  -- No `x and y or z` here: what Choose hands back can itself be secret,
  -- and `or` would test it.
  local alpha = 0
  local okSame, same = pcall(UnitIsUnit, unit, "targettarget")
  if okSame then
    alpha = ns.Secrets.Choose(same, 1, 0, 0)
  end
  button.holderTint:SetAlpha(alpha)
  button.holderLabel:SetAlpha(alpha)
  button.holderTint:Show()
  button.holderLabel:Show()
  for _, tex in ipairs(button.holderEdges) do
    tex:SetAlpha(alpha)
    tex:Show()
  end
end
ns.RenderTargetHolder = RenderTargetHolder

function ns.RenderThreat(button, s, enabled)
  RenderTargetHolder(button, s, enabled and s.threatHidden and ns.db.mode == "tank")
  local level = enabled and (s.threat or 0) or 0
  local tankMode = ns.db.mode == "tank"
  local color = THREAT_COLORS[level]
  if tankMode and level >= 2 and s.isTank then
    color = HOLDING -- a tank with a mob on them is how it should be
  end
  if not color and not button.threatEdges then
    return -- never had threat: don't build textures for it
  end
  local edges = ThreatBorder(button)
  local loose = tankMode and level >= 2 and s.loose
  SetEdgeThickness(button, edges, loose and 4 or 2)
  for _, tex in ipairs(edges) do
    if color then
      tex:SetColorTexture(color[1], color[2], color[3], 1)
      tex:SetAlpha(1)
      tex:Show()
    else
      tex:Hide()
    end
  end
  -- The wash and label are tank mode only; healer mode just gets the border.
  if tankMode then
    button.threatTint:SetShown(loose and true or false)
    if loose then
      button.threatLabel:SetText((s.mobCount or 0) > 1 and ("AGGRO x" .. s.mobCount) or "AGGRO")
      button.threatLabel:Show()
    elseif level == 1 and not s.isTank then
      button.threatLabel:SetText("|cffffd933pulling|r")
      button.threatLabel:Show()
    else
      button.threatLabel:Hide()
    end
  elseif button.threatTint then
    button.threatTint:Hide()
    button.threatLabel:Hide()
  end
end

-- THE METER (tank mode): how close each player is to pulling YOUR target.
--
-- A thin bar along the top of every frame: their threat on whatever you have
-- targeted, as a share of what it would take to pull it (100% = it turns on
-- them). The percentage can be a secret number, so it is handed straight to the
-- status bar and the font string, which may draw what we may not read.
local METER_HEIGHT = 4

local function ThreatMeter(button)
  if button.threatMeter then
    return button.threatMeter
  end
  local bar = button.health or button
  local meter = CreateFrame("StatusBar", nil, bar)
  meter:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  meter:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  meter:SetHeight(METER_HEIGHT)
  meter:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  meter:SetMinMaxValues(0, 100)
  meter.bg = meter:CreateTexture(nil, "BACKGROUND")
  meter.bg:SetAllPoints()
  meter.bg:SetColorTexture(0, 0, 0, 0.75)
  meter.text = bar:CreateFontString(nil, "OVERLAY", "ForeverUIFramesTinyFont")
  meter.text:SetPoint("RIGHT", bar, "RIGHT", -3, 1)
  meter:Hide()
  meter.text:Hide()
  button.threatMeter = meter
  return meter
end

local function MeterColor(percent)
  if percent >= 90 then
    return 1.00, 0.15, 0.15
  elseif percent >= 60 then
    return 1.00, 0.75, 0.15
  end
  return 0.35, 0.85, 0.40
end

local function Percent(unit)
  local _, _, scaled = UnitDetailedThreatSituation(unit, "target")
  return scaled
end

-- Called a few times a second while you have something to fight.
function ns.UpdateThreatMeter(button, fighting)
  local unit = button.unit
  local show = fighting and unit and ns.db.showThreatMeter and UnitDetailedThreatSituation
    and not (button.state and (button.state.dead or button.state.ghost or button.state.offline))
  if not show then
    if button.threatMeter then
      button.threatMeter:Hide()
      button.threatMeter.text:Hide()
    end
    return
  end
  local ok, percent = pcall(Percent, unit)
  if not ok or type(percent) == "nil" then
    if button.threatMeter then
      button.threatMeter:Hide()
      button.threatMeter.text:Hide()
    end
    return
  end
  local meter = ThreatMeter(button)
  meter:SetValue(percent) -- a secret number is fine here
  local okColor, r, g, b = pcall(MeterColor, percent)
  if okColor then
    meter:SetStatusBarColor(r, g, b)
  else
    meter:SetStatusBarColor(1.00, 0.65, 0.15)
  end
  meter:Show()
  if ns.db.showThreatPercent then
    meter.text:SetFormattedText("%.0f%%", percent)
    meter.text:Show()
  else
    meter.text:Hide()
  end
end

-- Is there anything to measure threat against? Your target, hostile and alive.
function ns.HaveThreatTarget()
  local B = ns.Secrets.Bool
  local ok, result = pcall(function()
    return B(UnitExists("target"), false) and B(UnitCanAttack("player", "target"), false)
      and not B(UnitIsDead("target"), false)
  end)
  return ok and result or false
end

-- Loose frames throb, so the one that matters is the one that moves.
function ns.PulseThreat(button, now)
  if not button.threatEdges or not button.state or not button.state.loose or not ns.db.showThreat then
    return
  end
  local alpha = 0.55 + 0.45 * math.abs(math.sin(now * 5))
  for _, tex in ipairs(button.threatEdges) do
    tex:SetAlpha(alpha)
  end
end

-- Their target (tank mode): what each player is fighting.
--
-- The name is only ever DRAWN (a FontString takes a secret string), and "is it
-- hostile" goes through the secret-safe boolean, so nothing here throws in a
-- dungeon where the game hides who is who.
function ns.ReadTheirTarget(unit, s)
  s.theirTarget, s.theirTargetHostile = nil, false
  local token = unit .. "target"
  local ok, exists = pcall(UnitExists, token)
  if not ok or not ns.Secrets.Bool(exists, false) then
    return
  end
  local okName, name = pcall(UnitName, token)
  if okName then
    s.theirTarget = name
  end
  if UnitCanAttack then
    local okAttack, hostile = pcall(UnitCanAttack, "player", token)
    s.theirTargetHostile = okAttack and ns.Secrets.Bool(hostile, false) or false
  end
end

function ns.RenderTheirTarget(bar, s, enabled)
  if not bar.theirTarget then
    if not (enabled and s.theirTarget) then
      return
    end
    local text = bar:CreateFontString(nil, "OVERLAY", "ForeverUIFramesTinyFont")
    text:SetPoint("BOTTOMLEFT", 4, 3)
    text:SetPoint("BOTTOMRIGHT", -34, 3)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    bar.theirTarget = text
  end
  local text = bar.theirTarget
  if enabled and s.theirTarget and s.theirTargetHostile then
    text:SetText(s.theirTarget) -- may be a secret string: drawn, never read
    text:SetTextColor(1, 0.45, 0.40)
    text:Show()
  else
    text:Hide()
  end
end

-- Who plays what, drawn on each frame: a badge (tank, healer, damage -
-- ChatGPT-painted, Media/role-*.tga) or the old letter. Melee, ranged and
-- the main assist all wear the damage badge; the letter still tells them apart.
ns.ROLE_BADGES = {
  TANK = "tank", MAINTANK = "tank", HEALER = "healer",
  DAMAGER = "dps", MELEE = "dps", RANGED = "dps", MAINASSIST = "dps",
}

function ns.RoleBadgeTexture(badge)
  return ns.MEDIA .. "role-" .. badge
end

-- Where the marker sits (owner, 23 Sept 2026: "a number of options ...
-- to include outside on the left and right"). Inside: any corner, edge or the
-- centre. Outside: beside the frame, top, middle or bottom, clear of it by a
-- few pixels - it hangs into the space between frames, not over the bar.
-- { the marker's point, the bar's point, x, y }
local ROLE_GAP = 3
ns.ROLE_PLACES = {
  TOPLEFT      = { "TOPLEFT", "TOPLEFT", 3, -2 },
  TOP          = { "TOP", "TOP", 0, -2 },
  TOPRIGHT     = { "TOPRIGHT", "TOPRIGHT", -3, -2 },
  LEFT         = { "LEFT", "LEFT", 3, 0 },
  CENTER       = { "CENTER", "CENTER", 0, 0 },
  RIGHT        = { "RIGHT", "RIGHT", -3, 0 },
  BOTTOMLEFT   = { "BOTTOMLEFT", "BOTTOMLEFT", 3, 2 },
  BOTTOM       = { "BOTTOM", "BOTTOM", 0, 2 },
  BOTTOMRIGHT  = { "BOTTOMRIGHT", "BOTTOMRIGHT", -3, 2 },
  OUTTOPLEFT     = { "TOPRIGHT", "TOPLEFT", -ROLE_GAP, 0 },
  OUTLEFT        = { "RIGHT", "LEFT", -ROLE_GAP, 0 },
  OUTBOTTOMLEFT  = { "BOTTOMRIGHT", "BOTTOMLEFT", -ROLE_GAP, 0 },
  OUTTOPRIGHT    = { "TOPLEFT", "TOPRIGHT", ROLE_GAP, 0 },
  OUTRIGHT       = { "LEFT", "RIGHT", ROLE_GAP, 0 },
  OUTBOTTOMRIGHT = { "BOTTOMLEFT", "BOTTOMRIGHT", ROLE_GAP, 0 },
}
ns.ROLE_PLACE_LABELS = {
  TOPLEFT = "Top left", TOP = "Top middle", TOPRIGHT = "Top right",
  LEFT = "Left middle", CENTER = "Centre", RIGHT = "Right middle",
  BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom middle", BOTTOMRIGHT = "Bottom right",
  OUTTOPLEFT = "Outside left, top", OUTLEFT = "Outside left", OUTBOTTOMLEFT = "Outside left, bottom",
  OUTTOPRIGHT = "Outside right, top", OUTRIGHT = "Outside right", OUTBOTTOMRIGHT = "Outside right, bottom",
}

local function Place(region, bar, where)
  local place = ns.ROLE_PLACES[where] or ns.ROLE_PLACES.TOPLEFT
  region:ClearAllPoints()
  region:SetPoint(place[1], bar, place[2], place[3], place[4])
end

-- The marker can't live on the health bar itself: a healer's bar clips
-- everything past its edge (so an incoming heal can't run across the next
-- frame - ClipTo below), which cut the badge off whenever it was put outside.
-- It gets a layer of its own on the unit button, drawn above the bar and
-- never clipped. The letter moves onto it too.
local function RoleLayer(bar)
  local layer = bar.roleLayer
  if layer then
    return layer
  end
  local host = bar.GetParent and bar:GetParent() or nil
  if not host or not host.CreateTexture then
    host = bar
  end
  layer = CreateFrame("Frame", nil, host)
  layer:SetAllPoints(bar)
  local level = bar.GetFrameLevel and bar:GetFrameLevel()
  if level then
    layer:SetFrameLevel(level + 10)
  end
  bar.roleLayer = layer
  bar.role:SetParent(layer)
  return layer
end

ns.PlaceOnBar = Place
ns.RoleLayer = RoleLayer

function ns.RenderRole(bar, s, enabled)
  local mark = enabled and s.role and ns.ROLE_MARKS[s.role]
  local badge = mark and ns.db.roleStyle ~= "letter" and ns.ROLE_BADGES[s.role]
  local where = ns.db.rolePosition or "TOPLEFT"
  local size = ns.db.roleSize or 12
  local icon = bar.roleIcon
  if mark then
    RoleLayer(bar)
  end
  if badge and not icon then
    icon = bar.roleLayer:CreateTexture(nil, "OVERLAY")
    bar.roleIcon = icon
  end
  if badge then
    bar.role:Hide()
    icon:SetTexture(ns.RoleBadgeTexture(badge))
    icon:SetSize(size, size)
    Place(icon, bar, where)
    icon:Show()
    return
  end
  if icon then
    icon:Hide()
  end
  if not mark then
    bar.role:Hide()
    return
  end
  bar.role:SetText(mark[1])
  bar.role:SetTextColor(mark[2], mark[3], mark[4])
  -- The letter follows the same place, and the size setting.
  bar.role:SetSize(size, size)
  local file, _, flags = bar.role:GetFont()
  bar.role:SetFont(file or "Fonts\\FRIZQT__.TTF", math.max(7, size - 3), flags or "OUTLINE")
  Place(bar.role, bar, where)
  bar.role:Show()
end

function ns.ReadPower(unit, s)
  if not UnitPower then
    s.power, s.powerMax = 0, 0
    return
  end
  -- Never compare or divide these: they may be secret values.
  -- The token can be secret in a group; then it's unknown (nil), never a key.
  local _, token = UnitPowerType(unit)
  s.powerToken = not (issecretvalue and issecretvalue(token)) and token or nil
  s.power, s.powerMax = UnitPower(unit), UnitPowerMax(unit)
end

function ns.RenderPower(button, s, height)
  local bar = button.power
  if not height or height <= 0 then
    bar:Hide()
    return
  end
  bar:SetHeight(height)
  ns.Secrets.SetBar(bar, s.power or 0, s.powerMax or 1)
  local color = ns.POWER_COLORS[s.powerToken or "MANA"] or ns.POWER_COLORS.MANA
  bar:SetStatusBarColor(color[1], color[2], color[3])
  -- In a group the maximum can be a secret number, and comparing one throws
  -- (seen the moment the owner joined a party). Read it if the client lets
  -- us; a unit whose maximum is hidden certainly has one, so show the bar.
  local max = ns.Secrets.Number(s.powerMax)
  bar:SetShown(max == nil or max > 0)
end

-- Split the total into "mine" and "everyone else's". Separate so it can run
-- protected: on Forever these numbers can come back as secret values, and
-- subtracting one of those throws rather than returning nonsense.
local function SplitIncoming(unit)
  -- Through Secrets.Number first. Forever can hand these back as secret
  -- values, and "all - mine" on one of those THROWS -- which put the frame
  -- into measureFailed and stopped it ever drawing an incoming heal again.
  -- A secret reads as nil here, which is honestly "unknown" rather than an
  -- error, and the caller shows what it can.
  local all = ns.Secrets.Number(UnitGetIncomingHeals(unit)) or 0
  local mine = ns.Secrets.Number(UnitGetIncomingHeals(unit, "player")) or 0
  return mine, math.max(0, all - mine)
end

function ns.ReadIncoming(unit, s)
  s.incomingMine, s.incomingOthers = 0, 0
  s.incomingAllRaw, s.incomingMineRaw, s.incomingSecret = nil, nil, nil
  if not UnitGetIncomingHeals then
    return
  end
  -- The raw answers are kept exactly as the game gave them. On Forever they
  -- are usually SECRET values: useless for arithmetic, but a status bar fills
  -- from one perfectly well, which is how the prediction gets drawn at all.
  local okAll, all = pcall(UnitGetIncomingHeals, unit)
  local okMine, mine = pcall(UnitGetIncomingHeals, unit, "player")
  s.incomingAllRaw = okAll and all or nil
  s.incomingMineRaw = okMine and mine or nil
  -- And the plain numbers too, when this client allows reading them: the
  -- overheal strip is arithmetic and can only exist when they are readable.
  local ok, mineNumber, others = pcall(SplitIncoming, unit)
  if ok then
    s.incomingMine, s.incomingOthers = mineNumber, others
  else
    s.incomingSecret = true
  end
  if ns.Secrets.Number(s.incomingAllRaw) == nil and type(s.incomingAllRaw) ~= "nil" then
    s.incomingSecret = true
  end
end

-- One aura by index through whichever API this client has.
-- Returns found, icon, dispelName, duration, expirationTime, name, stacks, isMine.
-- Durations and stack counts leave here as plain numbers or as nil: the timers
-- and the "is this short enough to be a HoT" test are arithmetic, and on
-- Forever an aura's numbers can arrive secret even when the client says auras
-- are readable. nil means "no countdown", which is a row that looks empty
-- rather than an error on every tick.
local Number = function(value) return ns.Secrets.Number(value) end

local function RawAura(unit, i, filter)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
    if aura then
      return true, aura.icon, aura.dispelName, Number(aura.duration), Number(aura.expirationTime),
        aura.name, Number(aura.applications), aura.sourceUnit == "player"
    end
    return false
  elseif UnitAura then
    local name, icon, count, dispelName, duration, expirationTime, caster = UnitAura(unit, i, filter)
    return name ~= nil, icon, dispelName, Number(duration), Number(expirationTime),
      name, Number(count), caster == "player"
  end
  return false
end

-- Every aura read in the addon goes through here, and it never throws: a
-- client that refuses gets asked again in a few seconds, and until then the
-- unit simply has no auras to draw. Health has to keep updating through that,
-- which is the whole point - an error here used to take the frame down with it.
local function AuraAt(unit, i, filter)
  if ns.Secrets.AurasSecret() or ns.Secrets.AurasRestricted() or ns.Secrets.AurasBlocked() then
    return false
  end
  local ok, found, icon, dispelName, duration, expires, name, stacks, mine =
    pcall(RawAura, unit, i, filter)
  if not ok then
    ns.Secrets.BlockAuras()
    return false
  end
  return found, icon, dispelName, duration, expires, name, stacks, mine
end
ns.AuraAt = AuraAt -- Target.lua reads the target's debuffs through the same guard

function ns.ReadDispellable(unit, s)
  s.dispelType, s.dispelIcon, s.dispelSpell = nil, nil, nil
  local best
  for i = 1, 40 do
    local found, icon, dispelName, _, _, name = AuraAt(unit, i, DISPEL_FILTER)
    if not found then
      break
    end
    local rank = DISPEL_RANK[dispelName]
    if rank and (not best or rank < best) then
      best, s.dispelType, s.dispelIcon, s.dispelSpell = rank, dispelName, icon, name
    end
  end
end

-- Your HoTs and shields: helpful auras YOU cast on the unit, no longer than
-- the "Show HoTs up to" setting (60s by default). No spell list, so Renew,
-- Rejuvenation, Riptide, Power Word: Shield - and whatever Forever adds - all
-- qualify, while long buffs (Fortitude, Forever's 1-hour Blessings) don't.
-- Auras the game reports without a duration are skipped: nothing to count down.
local HOT_FILTER = "HELPFUL|PLAYER"
local MAX_HOTS = 3 -- icon slots in Frames.xml
ns.MAX_HOTS = MAX_HOTS
local HOT_WARNING = 3 -- seconds left when the countdown turns red

-- spell name -> list of entries, highest priority first; one index per watch
-- list, because each grid has its own list and reads it while drawing.
local indexes = setmetatable({}, { __mode = "k" })

local function BuildIndex(list)
  local index = {}
  for order, entry in ipairs(list) do
    local spells = index[entry.spell]
    if not spells then
      spells = {}
      index[entry.spell] = spells
    end
    entry.order = order
    spells[#spells + 1] = entry
  end
  indexes[list] = index
  return index
end

local function WatchIndex()
  local list = ns.db and ns.db.auraWatch or {}
  return indexes[list] or BuildIndex(list)
end

-- Every watched spell name (this grid's list), for the game-drawn HoT row.
function ns.WatchedNames()
  return WatchIndex()
end

-- Watched at all, whoever cast it.
function ns.IsWatched(name)
  return name ~= nil and WatchIndex()[name] ~= nil
end

-- Is this spell already being watched somewhere that would show YOUR cast of
-- it? A watch set to other players' casts only doesn't count - hiding it from
-- the HoT row as well would mean seeing it nowhere.
function ns.WatchCoversMine(name)
  local list = name and WatchIndex()[name]
  if not list then
    return false
  end
  for _, entry in ipairs(list) do
    if entry.mine ~= "others" then
      return true
    end
  end
  return false
end

local function AurasUnreadable()
  return ns.Secrets.AurasSecret() or ns.Secrets.AurasRestricted() or ns.Secrets.AurasBlocked()
end

-- The HoT row from what you were seen to cast (Inference.lua), soonest to
-- expire first. Spells you watch in a corner go to their corner instead.
local function InferredHots(s)
  local hots = s.hots or {}
  s.hots = hots
  local auras = ns.db.inferHots and ns.InferredAuras and ns.InferredAuras(ns.InferKey(s))
  local list = {}
  s.inferredUntil = nil
  for spell, aura in pairs(auras or {}) do
    -- The soonest anything of yours runs out, corner or row: redraw then.
    if not s.inferredUntil or aura.expires < s.inferredUntil then
      s.inferredUntil = aura.expires
    end
    if aura.duration <= ns.db.hotMaxDuration and not ns.WatchCoversMine(spell) then
      list[#list + 1] = aura
    end
  end
  table.sort(list, function(a, b) return a.expires < b.expires end)
  local n = math.min(#list, MAX_HOTS)
  for i = 1, n do
    local hot = hots[i] or {}
    hots[i] = hot
    hot.icon, hot.expires, hot.duration = list[i].icon, list[i].expires, list[i].duration
  end
  s.hotCount = n
end

function ns.ReadHots(unit, s)
  -- In a fight the auras can't be read at all; what's drawn then is what you
  -- were seen to cast.
  if AurasUnreadable() then
    InferredHots(s)
    return
  end
  local hots = s.hots
  if not hots then
    hots = {}
    s.hots = hots
  end
  local maxDuration = ns.db.hotMaxDuration
  local n = 0
  for i = 1, 40 do
    local found, icon, _, duration, expirationTime, name = AuraAt(unit, i, HOT_FILTER)
    if not found or n == MAX_HOTS then
      break
    end
    -- A spell you asked to watch in a corner doesn't also belong in the HoT
    -- row: Power Word: Shield in the starter watch list was appearing twice on
    -- every frame, once in each. What you chose deliberately wins.
    if duration and duration > 0 and ns.LearnDuration and type(name) == "string" then
      ns.LearnDuration(name, duration) -- so the in-combat guess uses YOUR Renew, talents and all
    end
    if duration and duration > 0 and duration <= maxDuration and not ns.WatchCoversMine(name) then
      n = n + 1
      local hot = hots[n] or {}
      hots[n] = hot
      hot.icon, hot.expires, hot.duration = icon, expirationTime, duration
    end
  end
  s.hotCount = n
  -- In a fight a read that finds nothing is far more likely the game hiding
  -- the auras (a lock we didn't hear about) than no HoTs at all: fall back
  -- to what you were seen to cast, so a Regrowth still ticking doesn't
  -- vanish at the pull.
  if n == 0 and InCombatLockdown and InCombatLockdown() then
    InferredHots(s)
  end
end

---------------------------------------------------------------------------
-- Missing buffs
---------------------------------------------------------------------------

-- The buffs worth nagging about: your class's, that you have learned, that you
-- haven't switched off. Rebuilt when the spellbook or the setting changes, not
-- on every refresh.
local MAX_MISSING = 2
local buffList

function ns.ForgetBuffList()
  buffList = nil
end

-- Every buff your class could track, known or not, for the options page.
function ns.GroupBuffChoices()
  local class
  if UnitClass then
    local _
    _, class = UnitClass("player")
  end
  local _, byName = ns.ScanSpellbook(false)
  local choices = {}
  for _, entry in ipairs(ns.GROUP_BUFFS[class] or {}) do
    local known = byName[entry.spell]
    local chosen = ns.db.missingBuffs and ns.db.missingBuffs[entry.spell]
    if chosen == nil then
      chosen = not entry.off
    end
    choices[#choices + 1] = { entry = entry, known = known ~= nil, on = chosen,
      icon = known and known.icon, label = entry.label or entry.spell }
  end
  return choices
end

local function BuffList()
  if not buffList then
    buffList = {}
    for _, choice in ipairs(ns.GroupBuffChoices()) do
      if choice.known and choice.on then
        local names = { [choice.entry.spell] = true }
        for _, name in ipairs(choice.entry.also or {}) do
          names[name] = true
        end
        local covers
        for _, name in ipairs(choice.entry.covers or {}) do
          covers = covers or {}
          covers[name] = true
        end
        buffList[#buffList + 1] = { names = names, covers = covers, prefix = choice.entry.prefix,
          mine = choice.entry.mine, manaOnly = choice.entry.manaOnly, icon = choice.icon, spell = choice.entry.spell }
      end
    end
  end
  return buffList
end

function ns.SetGroupBuff(spell, on)
  local chosen = {}
  for k, v in pairs(ns.db.missingBuffs or {}) do chosen[k] = v end
  chosen[spell] = on and true or false
  ns.SetSetting("missingBuffs", chosen)
end

local function Covers(buff, name, mine)
  if buff.mine and not mine then
    return false
  end
  if buff.names[name] or (buff.covers and buff.covers[name]) then
    return true
  end
  for _, prefix in ipairs(buff.prefix or {}) do
    if name:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

-- Buff Watch (BuffWatch.lua) reads the same list, the same way.
ns.GroupBuffList = function() return BuffList() end
ns.BuffCovers = Covers

-- Only ever says "missing" when the buffs could actually be read. In a fight
-- Forever hides auras, and a frame that lit up for everybody the moment combat
-- started would be worse than one that says nothing.
function ns.ReadMissingBuffs(unit, s)
  s.missingCount = 0
  local list = BuffList()
  if #list == 0 or s.dead or s.ghost or s.offline then
    return
  end
  if ns.Secrets.AurasSecret() or ns.Secrets.AurasRestricted() or ns.Secrets.AurasBlocked() then
    return
  end
  -- Too far away to see is not the same as unbuffed.
  if UnitIsVisible and not ns.Secrets.Bool(UnitIsVisible(unit), true) then
    return
  end
  local has = {}
  for i = 1, 40 do
    local found, _, _, _, _, name, _, mine = AuraAt(unit, i, "HELPFUL")
    if not found then
      break
    end
    if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
      for index, buff in ipairs(list) do
        if not has[index] and Covers(buff, name, mine) then
          has[index] = true
        end
      end
    end
  end
  if ns.Secrets.AurasBlocked() then
    return -- the read was refused part-way: what we have isn't the whole list
  end
  local missing = s.missing or {}
  s.missing = missing
  local n = 0
  for index, buff in ipairs(list) do
    if not has[index] and n < MAX_MISSING and not (buff.manaOnly and s.powerToken ~= "MANA") then
      n = n + 1
      missing[n] = buff
    end
  end
  s.missingCount = n
end

-- Right-hand side, half way up: the corners belong to the watch list and the
-- bottom-left to the HoTs. A red edge says "this is something absent".
local function MissingIcons(bar)
  if bar.missingIcons then
    return bar.missingIcons
  end
  local icons = {}
  for i = 1, MAX_MISSING do
    local edge = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    edge:SetSize(15, 15)
    edge:SetPoint("RIGHT", bar, "RIGHT", -3 - (i - 1) * 17, 0)
    edge:SetColorTexture(0.9, 0.15, 0.15, 1)
    local icon = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(13, 13)
    icon:SetPoint("CENTER", edge, "CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetDesaturated(true)
    icon.edge = edge
    icons[i] = icon
  end
  bar.missingIcons = icons
  return icons
end

function ns.RenderMissingBuffs(bar, s, enabled)
  local count = enabled and s.missingCount or 0
  if count == 0 and not bar.missingIcons then
    return
  end
  local icons = MissingIcons(bar)
  for i = 1, MAX_MISSING do
    local icon = icons[i]
    if i <= count then
      icon:SetTexture(s.missing[i].icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      icon:Show()
      icon.edge:Show()
    else
      icon:Hide()
      icon.edge:Hide()
    end
  end
end

-- Watched auras: any spell you name, anywhere on the frame.
-- Unlike the HoT row this doesn't guess - it shows exactly what you asked for,
-- whoever cast it, which is how you watch another healer's shield or a boss debuff.
--
-- Nine places an indicator can sit. The first four are the original corners
-- in their original order, so a watch list saved before there were nine still
-- means exactly what it did. Several indicators in one place sit side by side
-- (owner, 23 Sept 2026: "if I want these to be together in the top left"),
-- in priority order, working inward from the corner or out from the middle.
--
-- Then six more between them (owner: "can we have more locations than
-- this?"): halfway between each side and the middle, on the top, the middle
-- and the bottom. Those are the middle points shifted a quarter of the frame's
-- width left or right (WATCH_SHIFT), so the map is five across, three down.
-- Past that, any spell can be nudged a pixel at a time from wherever it sits.
ns.WATCH_CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
  "TOP", "BOTTOM", "LEFT", "RIGHT", "CENTER",
  "TOP", "TOP", "CENTER", "CENTER", "BOTTOM", "BOTTOM" }
ns.WATCH_SHIFT = { [10] = -0.25, [11] = 0.25, [12] = -0.25, [13] = 0.25, [14] = -0.25, [15] = 0.25 }
ns.WATCH_CORNER_LABELS = { "Top left", "Top right", "Bottom left", "Bottom right",
  "Top middle", "Bottom middle", "Left middle", "Right middle", "Centre",
  "Top, left of middle", "Top, right of middle", "Left of centre", "Right of centre",
  "Bottom, left of middle", "Bottom, right of middle" }
ns.WATCH_NUDGE_MAX = 60

-- What an indicator looks like: the spell's own icon, a plain square in a
-- colour, or a general symbol in a colour. The symbols are white art
-- (ChatGPT-painted, cut by tools/convert_art.py) tinted at draw time, so any
-- colour works. "color" is the plain square and keeps its old name for the
-- same reason as the corners.
ns.WATCH_STYLES = { "icon", "color", "dot", "ring", "diamond", "triangle", "star",
  "heart", "spade", "club", "cross", "plus", "moon" }
ns.WATCH_STYLE_LABELS = {
  icon = "Spell icon", color = "Square", dot = "Dot", ring = "Ring", diamond = "Diamond",
  triangle = "Triangle", star = "Star", heart = "Heart", spade = "Spade", club = "Club",
  cross = "Cross", plus = "Plus", moon = "Moon",
}

function ns.ShapeTexture(style)
  return ns.MEDIA .. "shape-" .. style
end

-- The number on an indicator: time left, time it has been up, or none.
ns.WATCH_TIMERS = { "down", "up", "off" }
ns.WATCH_TIMER_LABELS = { down = "Counts down", up = "Counts up", off = "No timer" }
ns.WATCH_WHO = { "mine", "others", "any" }
ns.WATCH_WHO_LABELS = { mine = "Mine", others = "Other players'", any = "Anyone's" }

function ns.RebuildWatchIndex()
  BuildIndex(ns.db.auraWatch or {})
end

local function Trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Adding, removing and cycling the watch list. Order is priority: when two
-- entries want the same corner, the one higher in the list wins.
function ns.AddWatch(spell)
  spell = Trim(spell)
  if spell == "" then
    return false
  end
  for _, entry in ipairs(ns.db.auraWatch) do
    if entry.spell == spell then
      return false
    end
  end
  table.insert(ns.db.auraWatch, {
    spell = spell,
    corner = #ns.db.auraWatch % 4 + 1, -- spread new ones around the frame
    mine = "any",
    style = "icon",
    color = { 0.3, 0.8, 1 },
  })
  ns.SetSetting("auraWatch", ns.db.auraWatch)
  return true
end

function ns.RemoveWatch(index)
  if ns.db.auraWatch[index] then
    table.remove(ns.db.auraWatch, index)
    ns.SetSetting("auraWatch", ns.db.auraWatch)
    return true
  end
  return false
end

function ns.CycleWatch(index, field)
  local entry = ns.db.auraWatch[index]
  if not entry then
    return
  end
  if field == "corner" then
    entry.corner = (entry.corner or 1) % #ns.WATCH_CORNERS + 1
  elseif field == "style" then
    local at = 1
    for i, style in ipairs(ns.WATCH_STYLES) do
      if style == entry.style then at = i end
    end
    entry.style = ns.WATCH_STYLES[at % #ns.WATCH_STYLES + 1]
  elseif field == "timer" then
    -- nil is "whatever this grid's default is", then each choice in turn.
    local order = { down = "up", up = "off", off = nil }
    if entry.timer == nil then
      entry.timer = "down"
    else
      entry.timer = order[entry.timer]
    end
  elseif field == "mine" then
    local order = { mine = "others", others = "any", any = "mine" }
    entry.mine = order[entry.mine] or "any"
  end
  ns.SetSetting("auraWatch", ns.db.auraWatch)
end

-- Set one field outright: the position grid, the symbol swatches and the
-- colour picker choose a value rather than stepping through them.
local WATCH_FIELDS = { corner = true, style = true, color = true, timer = true, size = true, dx = true, dy = true }
function ns.SetWatchField(index, field, value)
  local entry = ns.db.auraWatch[index]
  if not entry or not WATCH_FIELDS[field] then
    return
  end
  if field == "size" and value ~= nil then
    value = math.max(ns.AURA_SIZE_MIN, math.min(ns.AURA_SIZE_MAX, math.floor(value + 0.5)))
  end
  entry[field] = value
  ns.SetSetting("auraWatch", ns.db.auraWatch)
end

-- Move one spell a few pixels from its place, any direction. Back to zero
-- clears it.
function ns.NudgeWatch(index, dx, dy)
  local entry = ns.db.auraWatch[index]
  if not entry then
    return
  end
  local limit = ns.WATCH_NUDGE_MAX
  local x = math.max(-limit, math.min(limit, (entry.dx or 0) + (dx or 0)))
  local y = math.max(-limit, math.min(limit, (entry.dy or 0) + (dy or 0)))
  entry.dx = x ~= 0 and x or nil
  entry.dy = y ~= 0 and y or nil
  ns.SetSetting("auraWatch", ns.db.auraWatch)
end

-- Bigger or smaller than the grid's default, one step at a time. Stepping
-- back onto the default clears the override, so a later change to the
-- default carries this entry with it.
ns.AURA_SIZE_MIN, ns.AURA_SIZE_MAX = 8, 32
function ns.StepWatchSize(index, delta)
  local entry = ns.db.auraWatch[index]
  if not entry then
    return
  end
  local default = ns.db.auraSize or 13
  local size = math.max(ns.AURA_SIZE_MIN, math.min(ns.AURA_SIZE_MAX, (entry.size or default) + delta))
  ns.SetWatchField(index, "size", size ~= default and size or nil)
end

-- Move an entry up or down the priority order.
function ns.MoveWatch(index, delta)
  local list = ns.db.auraWatch
  local target = index + delta
  if list[index] and list[target] then
    list[index], list[target] = list[target], list[index]
    ns.SetSetting("auraWatch", list)
    return target
  end
  return index
end

local function Wants(entry, isMine)
  return entry.mine == "any" or (entry.mine == "mine") == (isMine and true or false)
end

-- Every watched spell that is up gets its own indicator now; two in one place
-- sit side by side rather than the lower one vanishing. Each is given a SLOT
-- (the widget that draws it): the first in each of the four corners keeps
-- that corner's own slot, 1-4, exactly as before there were more, and the
-- rest take slots from 5 up. Where a slot is DRAWN is worked out afterwards
-- (ns.PlaceAuras), from how many share its place.
local MAX_WATCHED = 12

local function Watched(entry, icon, duration, expires, stacks)
  return {
    spell = entry.spell, mine = entry.mine,
    order = entry.order, corner = entry.corner or 1, style = entry.style, color = entry.color,
    size = entry.size, timer = entry.timer, dx = entry.dx, dy = entry.dy,
    icon = icon, duration = duration, expires = expires, stacks = stacks,
  }
end

local function AssignSlots(found, slots)
  table.sort(found, function(a, b)
    if a.corner ~= b.corner then return a.corner < b.corner end
    return a.order < b.order
  end)
  local nextSlot, lead = 5, {}
  local used = 0
  for _, item in ipairs(found) do
    local slot
    if item.corner <= 4 and not lead[item.corner] then
      slot = item.corner
      lead[item.corner] = true
    else
      slot = nextSlot
      nextSlot = nextSlot + 1
    end
    item.slot = slot
    slots[slot] = item
    if slot > used then used = slot end
  end
  return used
end

function ns.ReadWatched(unit, s)
  local slots = s.watch
  if not slots then
    slots = {}
    s.watch = slots
  end
  ns.Wipe(slots)
  s.watchSlots = 0
  local watchIndex = WatchIndex()
  if not next(watchIndex) then
    return
  end
  local found, seen = {}, {}
  -- The game draws some of them itself on this frame (GameHots.lua).
  local drawn = s.gameWatched
  local function take(entry, ...)
    if drawn and drawn[(entry.spell or "") .. "|" .. (entry.mine or "any")] then
      return
    end
    if not seen[entry] and #found < MAX_WATCHED then
      seen[entry] = true
      found[#found + 1] = Watched(entry, ...)
    end
  end

  if AurasUnreadable() then
    local auras = ns.db.inferHots and ns.InferredAuras and ns.InferredAuras(ns.InferKey(s))
    for spell, aura in pairs(auras or {}) do
      for _, entry in ipairs(watchIndex[spell] or {}) do
        if Wants(entry, true) then
          take(entry, aura.icon, aura.duration, aura.expires, nil)
        end
      end
    end
  else
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
      for i = 1, 40 do
        local found_, icon, _, duration, expires, name, stacks, isMine = AuraAt(unit, i, filter)
        if not found_ then
          break
        end
        for _, entry in ipairs(name and watchIndex[name] or {}) do
          if Wants(entry, isMine) then
            take(entry, icon, duration, expires, stacks)
          end
        end
      end
    end
  end
  s.watchSlots = AssignSlots(found, slots)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function ns.FormatRemaining(seconds)
  if seconds <= 0 then
    return ""
  end
  return ("%d"):format(math.ceil(seconds))
end

-- The number on an indicator. "down" is the time left, "up" the time since
-- it went on (needs its full duration, so an aura without one shows none),
-- "off" nothing at all.
function ns.AuraTimerText(mode, expires, duration, now)
  if mode == "off" or not expires or expires <= 0 then
    return ""
  end
  local remaining = expires - now
  if remaining <= 0 then
    return ""
  end
  if mode == "up" then
    if not duration or duration <= 0 then
      return ""
    end
    return ("%d"):format(math.max(0, math.floor(duration - remaining)))
  end
  return ns.FormatRemaining(remaining)
end

-- Red for the last few seconds whichever way it counts: that is when you
-- want to be told to refresh it.
local function PaintTimer(timer, mode, expires, duration, now)
  timer:SetText(ns.AuraTimerText(mode, expires, duration, now))
  if expires and expires - now <= HOT_WARNING then
    timer:SetTextColor(1, 0.3, 0.3)
  else
    timer:SetTextColor(1, 1, 1)
  end
end

-- Just the numbers; runs on the frame ticker, so no icon work here. The
-- ticker doesn't borrow each grid's settings the way a full redraw does, so
-- the timer style is read off what that redraw left on the bar.
function ns.UpdateHotTimers(bar, s, now)
  local timers = bar.hots.timers
  local mode = bar.hots.timerMode or "down"
  for i = 1, s.hotCount or 0 do
    local hot = s.hots[i]
    PaintTimer(timers[i], mode, hot.expires, hot.duration, now)
  end
end

function ns.RenderHots(bar, s, alive, now)
  local count = alive and s.hotCount or 0
  local icons, timers = bar.hots.icons, bar.hots.timers
  bar.hots.timerMode = ns.db.auraTimer or "down"
  bar.hots.shownCount = count
  for i = 1, MAX_HOTS do
    if i <= count then
      icons[i]:SetTexture(s.hots[i].icon)
      icons[i]:Show()
      timers[i]:SetShown(bar.hots.timerMode ~= "off")
    else
      icons[i]:Hide()
      timers[i]:Hide()
    end
  end
  if count > 0 then
    ns.UpdateHotTimers(bar, s, now)
  end
end

function ns.UpdateWatchTimers(bar, s, now)
  local watch = bar.watch
  local default = watch.timerMode or "down"
  for slot = 1, #watch.timers do
    local item = s.watch and s.watch[slot]
    local timer = watch.timers[slot]
    local mode = item and (item.timer or default)
    if item and watch.icons[slot]:IsShown() and mode ~= "off"
      and item.expires and item.expires > 0 and (item.duration or 0) > 0 then
      PaintTimer(timer, mode, item.expires, item.duration, now)
      timer:Show()
    else
      timer:Hide()
    end
  end
end

-- Watch slots past the four the template builds are made here, as they are
-- needed. Plain textures and text on a plain frame: safe to create in combat.
local function EnsureWatchSlots(watch, count)
  for slot = #watch.icons + 1, count do
    local icon = watch:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:Hide()
    watch.icons[slot] = icon
    local timer = watch:CreateFontString(nil, "OVERLAY", "ForeverUIFramesTinyFont")
    timer:SetJustifyH("CENTER")
    timer:Hide()
    watch.timers[slot] = timer
    local stacks = watch:CreateFontString(nil, "OVERLAY", "ForeverUIFramesTinyFont")
    stacks:SetJustifyH("RIGHT")
    stacks:Hide()
    watch.stacks[slot] = stacks
  end
end

-- An icon keeps a sliver cropped off its baked-in border; the symbols and the
-- plain square are drawn whole, in the entry's colour.
local function PaintIndicator(texture, style, icon, color)
  local c = color or { 1, 1, 1 }
  if style == "color" then
    texture:SetColorTexture(c[1], c[2], c[3], 1)
    texture:SetVertexColor(1, 1, 1, 1)
  elseif style and style ~= "icon" and ns.WATCH_STYLE_LABELS[style] then
    texture:SetTexture(ns.ShapeTexture(style))
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(c[1], c[2], c[3], 1)
  else
    texture:SetTexture(icon)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    texture:SetVertexColor(1, 1, 1, 1)
  end
end

function ns.RenderWatched(bar, s, alive, now)
  local watch = bar.watch
  watch.timerMode = ns.db.auraTimer or "down"
  EnsureWatchSlots(watch, alive and s.watchSlots or 0)
  for slot = 1, #watch.icons do
    local item = alive and s.watch and s.watch[slot]
    local icon, stacks = watch.icons[slot], watch.stacks[slot]
    if item then
      PaintIndicator(icon, item.style, item.icon, item.color)
      icon:Show()
      if (item.stacks or 0) > 1 then
        stacks:SetText(item.stacks)
        stacks:Show()
      else
        stacks:Hide()
      end
    else
      icon:Hide()
      stacks:Hide()
      watch.timers[slot]:Hide()
    end
  end
  ns.UpdateWatchTimers(bar, s, now)
end

---------------------------------------------------------------------------
-- Placing them
---------------------------------------------------------------------------

-- Everything that sits on the bar - the watched auras and the HoT row - goes
-- in groups by place. A group in a corner or on a side runs inward from the
-- edge; one in the middle of an edge, or the centre, is centred on it.
local EDGE, GAP = 2, 1

local function Direction(point)
  if point:find("LEFT") then return 1 end
  if point:find("RIGHT") then return -1 end
  return 0
end

local function Lift(point)
  if point:find("TOP") then return -EDGE end
  if point:find("BOTTOM") then return EDGE end
  return 0
end

local function SetTextSize(fontString, size)
  if fontString.fuiTextSize == size then
    return
  end
  local file, _, flags = fontString:GetFont()
  fontString:SetFont(file or "Fonts\\FRIZQT__.TTF", size, flags or "OUTLINE")
  fontString.fuiTextSize = size
end

local function PlaceGroup(point, members, textSize, shift)
  local direction = Direction(point)
  local total = 0
  for i, member in ipairs(members) do
    total = total + member.size + (i > 1 and GAP or 0)
  end
  local along = direction == 0 and -total / 2 or EDGE
  for _, member in ipairs(members) do
    local x
    if direction == 0 then
      x = along + member.size / 2
    else
      x = direction * along
    end
    local icon = member.icon
    icon:SetSize(member.size, member.size)
    icon:ClearAllPoints()
    icon:SetPoint(point, member.frame, point, x + shift + (member.dx or 0), Lift(point) + (member.dy or 0))
    local timer = member.timer
    timer:ClearAllPoints()
    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    timer:SetSize(math.max(member.size + 8, 20), math.max(member.size, textSize + 2))
    SetTextSize(timer, textSize)
    if member.stacks then
      member.stacks:ClearAllPoints()
      member.stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
      member.stacks:SetSize(member.size, textSize + 2)
      SetTextSize(member.stacks, textSize)
    end
    along = along + member.size + GAP
  end
end

function ns.PlaceAuras(bar, s)
  local size = ns.db.auraSize or 13
  local textSize = ns.db.auraTimerSize or 9
  -- Groups are by PLACE (the index), not by anchor point: "top, left of
  -- middle" and "top middle" share the TOP point but not a row.
  local groups, order = {}, {}
  local function add(corner, member)
    if not ns.WATCH_CORNERS[corner] then
      corner = 1
    end
    local group = groups[corner]
    if not group then
      group = {}
      groups[corner] = group
      order[#order + 1] = corner
    end
    group[#group + 1] = member
  end

  -- Watched ones first, in the order they were read: by place, then priority.
  local watch = bar.watch
  local items = {}
  for slot = 1, #watch.icons do
    local item = s.watch and s.watch[slot]
    if item and watch.icons[slot]:IsShown() then
      items[#items + 1] = item
    end
  end
  table.sort(items, function(a, b)
    if a.corner ~= b.corner then return a.corner < b.corner end
    return a.order < b.order
  end)
  for _, item in ipairs(items) do
    local slot = item.slot
    add(item.corner, { frame = watch, icon = watch.icons[slot], timer = watch.timers[slot],
      stacks = watch.stacks[slot], size = item.size or size, dx = item.dx, dy = item.dy })
  end
  -- Then the HoT row, wherever it has been put, after any watched spell
  -- sharing its place.
  local hots = bar.hots
  for i = 1, hots.shownCount or 0 do
    add(ns.db.hotRowCorner or 3, { frame = hots, icon = hots.icons[i], timer = hots.timers[i], size = size })
  end

  local width = bar:GetWidth()
  if type(width) ~= "number" or width <= 0 then
    width = ns.db.frameWidth or 120
  end
  for _, corner in ipairs(order) do
    PlaceGroup(ns.WATCH_CORNERS[corner], groups[corner], textSize, (ns.WATCH_SHIFT[corner] or 0) * width)
  end

  -- The game-drawn corners and HoT row (GameHots.lua) go where ours would
  -- have: after the frame's own icons sharing their place.
  if bar.fuiGameHots then
    local function Own(corner)
      local px = 0
      for _, member in ipairs(groups[corner] or {}) do
        px = px + member.size + GAP
      end
      return px
    end
    local slotPx = {}
    if ns.PlaceGameWatch then
      for corner, point in ipairs(ns.WATCH_CORNERS) do
        slotPx[corner] = ns.PlaceGameWatch(bar, corner, point,
          Direction(point) * EDGE + (ns.WATCH_SHIFT[corner] or 0) * width, Lift(point), Own(corner), GAP)
      end
    end
    if ns.PlaceGameHots then
      local corner = ns.db.hotRowCorner or 3
      local point = ns.WATCH_CORNERS[corner] or "BOTTOMLEFT"
      ns.PlaceGameHots(bar, point, Direction(point) * EDGE + (ns.WATCH_SHIFT[corner] or 0) * width,
        Lift(point), Own(corner) + (slotPx[corner] or 0))
    end
  end
end

-- Pixels for `amount` of health on a bar of `healthMax`.
-- Three widths: your heal, everyone else's, and the part that lands on a
-- full health bar.
--
-- The overheal used to be thrown away here -- incoming was clamped to what
-- was missing and the remainder simply vanished. That is the one number a
-- healer most wants back: it is the difference between "they are covered"
-- and "you are both wasting a cast on the same person".
function ns.IncomingWidths(s)
  local max = math.max(s.healthMax or 0, 1)
  local missing = math.max(0, max - (s.health or 0))
  local width = BarWidth()

  local incomingMine = s.incomingMine or 0
  local incomingOthers = s.incomingOthers or 0

  local mine = math.min(incomingMine, missing)
  local others = math.min(incomingOthers, math.max(0, missing - mine))
  -- Whatever is still coming once the bar is full.
  local over = math.max(0, (incomingMine + incomingOthers) - (mine + others))
  -- Capped so a huge overheal cannot run off the end of the frame.
  over = math.min(over, max)

  return mine / max * width, others / max * width, over / max * width
end

-- Incoming heals when the numbers are SECRET.
--
-- Forever hands UnitGetIncomingHeals() back as a secret value in a group, so
-- the old code -- which turned it into pixels -- could never draw anything,
-- and "incoming heals" silently did nothing for every healer on the beta.
--
-- A status bar takes a secret value without complaint, so the prediction is
-- drawn as two bars instead of two textures. Each is as wide as the whole
-- health bar and scaled 0..healthMax, so one point of health is the same
-- number of pixels as on the bar underneath; each is anchored to the health
-- fill's right edge, so it starts exactly where health ends and follows it as
-- it moves. Nothing here is added, subtracted or compared.
--
-- "All" sits underneath in the other-healers colour and "mine" over it in
-- yours, both from the same origin: the bright part is what you are landing,
-- the rest is everyone else's. (Subtracting one from the other to lay them
-- end to end is exactly the arithmetic the client forbids.)
-- A heal that has not landed yet must not look like health that has. Drawn
-- in the same solid green as the bar, a 50% player mid-cast read as though
-- they were already at 80%. The prediction is a GHOST instead: washed out,
-- half transparent, with a bright tick at the far end marking where the heal
-- will reach. Health is what is solid; everything paler than it is a promise.
local PREDICT_MINE   = { 0.72, 0.92, 0.78, 0.45 }
local PREDICT_OTHERS = { 0.55, 0.68, 0.58, 0.32 }
local PREDICT_EDGE   = { 0.85, 1.00, 0.88, 0.85 }
ns.PREDICT_MINE, ns.PREDICT_OTHERS = PREDICT_MINE, PREDICT_OTHERS

local function PredictBar(bar, key, colour, level)
  local existing = bar[key]
  if existing then
    return existing
  end
  local predict = CreateFrame("StatusBar", nil, bar)
  local fill = bar:GetStatusBarTexture()
  local path = fill and fill.GetTexture and fill:GetTexture()
  predict:SetStatusBarTexture(path or "Interface\\Buttons\\WHITE8X8")
  predict:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4] or 0.4)
  -- A hairline where the heal ends, so the eye can see how far it will get
  -- without mistaking the pale part for health.
  local tick = predict:CreateTexture(nil, "OVERLAY")
  tick:SetColorTexture(PREDICT_EDGE[1], PREDICT_EDGE[2], PREDICT_EDGE[3], PREDICT_EDGE[4])
  tick:SetWidth(1)
  tick:SetPoint("TOPRIGHT", predict:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
  tick:SetPoint("BOTTOMRIGHT", predict:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
  predict.tick = tick
  local base = bar.GetFrameLevel and bar:GetFrameLevel()
  if base then predict:SetFrameLevel(base + level) end
  predict:Hide()
  bar[key] = predict
  return predict
end

-- Past the right-hand edge of the frame there is nothing to draw on, so the
-- overflow is clipped rather than allowed to run across the next frame.
local function ClipTo(bar)
  if bar.SetClipsChildren and not bar.fuiClipped then
    pcall(bar.SetClipsChildren, bar, true)
    bar.fuiClipped = true
  end
end

local function PlacePredict(predict, bar, fill, current, maximum)
  -- type(), not "== nil": comparing a secret value is itself refused.
  if type(current) == "nil" or type(maximum) == "nil" then
    predict:Hide()
    return
  end
  predict:ClearAllPoints()
  if ns.db.fillDirection == "up" then
    -- A standing bar: the heal stacks on top of the fill.
    if predict.SetOrientation then predict:SetOrientation("VERTICAL") end
    predict:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, 0)
    predict:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, 0)
    predict:SetHeight(bar:GetHeight() or 30)
    if predict.tick then
      predict.tick:ClearAllPoints()
      predict.tick:SetHeight(1)
      predict.tick:SetPoint("TOPLEFT", predict:GetStatusBarTexture(), "TOPLEFT", 0, 0)
      predict.tick:SetPoint("TOPRIGHT", predict:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    end
  else
    if predict.SetOrientation then predict:SetOrientation("HORIZONTAL") end
    predict:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    predict:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    predict:SetWidth(bar:GetWidth() or BarWidth())
    if predict.tick then
      predict.tick:ClearAllPoints()
      predict.tick:SetWidth(1)
      predict.tick:SetPoint("TOPRIGHT", predict:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
      predict.tick:SetPoint("BOTTOMRIGHT", predict:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
  end
  ns.Secrets.SetBar(predict, current, maximum)
  predict:Show()
end

-- The overheal strip, made on demand so the XML template does not have to
-- change for it. Drawn over the END of the bar rather than past it: there is
-- nothing past a full bar to draw on.
local function OverhealTexture(bar)
  if not bar.incomingOver then
    local tex = bar:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(1.00, 0.85, 0.35, 0.55)
    tex:Hide()
    bar.incomingOver = tex
  end
  return bar.incomingOver
end

-- THE OVERHEAL LANE.
--
-- The waste cannot be worked out on Forever: incoming and missing health are
-- both secret, the bar's geometry does not carry the value (a 100px bar at
-- 90% still reports 100), and its texture coordinates come back secret too.
-- All three were probed in the client.
--
-- So it is shown instead of counted. The health bar is made a little shorter
-- than the frame, which puts "full" at a point INSIDE it, and the strip left
-- over becomes a lane. A bar of the same scale, anchored where the health
-- fill ends and carrying the incoming heal, is laid across both; the lane
-- clips it, so the only part that ever shows in the lane is the part of the
-- heal that reaches past full. That is the overhealing, drawn by the game,
-- with no number read by us.
local function OverhealLane(button, bar)
  if bar.overLane then
    return bar.overLane, bar.overSpill
  end
  local lane = CreateFrame("Frame", nil, button)
  lane:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 3)
  if lane.SetClipsChildren then
    pcall(lane.SetClipsChildren, lane, true)
  end
  -- The empty lane is the BAR's own background, not a box of its own: an
  -- empty black rectangle on the end of a full bar reads as damage, or as a
  -- bug. This way it looks like the far end of the bar, and only the amber
  -- that lands in it says anything.
  local back = lane:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  lane.back = back
  -- One hairline at the near edge: the "full health" mark. Everything to the
  -- right of it is overhealing.
  local mark = lane:CreateTexture(nil, "ARTWORK", nil, 2)
  mark:SetWidth(1)
  mark:SetPoint("TOPLEFT")
  mark:SetPoint("BOTTOMLEFT")
  lane.mark = mark

  local spill = CreateFrame("StatusBar", nil, lane)
  spill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  spill:SetStatusBarColor(1.00, 0.72, 0.20, 0.55)   -- ghosted, like the rest of the prediction
  spill:Hide()
  bar.overLane, bar.overSpill = lane, spill
  return lane, spill
end

function ns.RenderOverhealLane(button, bar, s, alive)
  local width = ns.OverhealLaneWidth and ns.OverhealLaneWidth() or 0
  if width <= 0 then
    if bar.overLane then bar.overLane:Hide() end
    return 0
  end
  local lane, spill = OverhealLane(button, bar)
  -- Exactly beside the health bar and exactly as tall as it: anchored to the
  -- bar on the left and to the frame on the right, so it never covers the
  -- mana bar underneath.
  lane:ClearAllPoints()
  lane:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
  lane:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, 0)
  lane:SetPoint("RIGHT", button, "RIGHT", -(ns.db.borderSize or 1), 0)
  -- Painted every pass, so it follows the bar background and border colours.
  -- The bar's own background with a breath of amber in it: plain background
  -- made an empty lane look like health the unit had lost, and the tint says
  -- "this is the waste zone" before any waste arrives.
  local back = ns.db.barBackgroundColor or { 0.12, 0.12, 0.12 }
  lane.back:SetColorTexture(back[1] * 0.85 + 0.07, back[2] * 0.85 + 0.045,
    back[3] * 0.85 + 0.01, back[4] or 1)
  local r, g, b = ns.EdgeColor(button, s)
  lane.mark:SetColorTexture(r, g, b, 0.6)
  -- The empty track stays put whatever the unit is doing; only the amber
  -- inside it comes and goes. A lane that vanished left a gap showing the
  -- frame's background, which read as a stripe of its own.
  lane:Show()
  if not alive then
    spill:Hide()
    return width
  end
  -- The value is whatever the game says is coming; the lane shows only what
  -- lands past the end of the health bar.
  local incoming = s.incomingAllRaw
  if type(incoming) == "nil" and not s.incomingSecret then
    local total = (s.incomingMine or 0) + (s.incomingOthers or 0)
    incoming = total > 0 and total or nil
  end
  if type(incoming) == "nil" or type(s.healthMax) == "nil" or not ns.db.showIncoming then
    spill:Hide()
    return width
  end
  local fill = bar:GetStatusBarTexture()
  spill:ClearAllPoints()
  spill:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
  spill:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
  spill:SetWidth(bar:GetWidth() or BarWidth())
  ns.Secrets.SetBar(spill, incoming, s.healthMax)
  spill:Show()
  return width
end

function ns.RenderIncoming(bar, s, alive)
  local over = OverhealTexture(bar)
  local all = PredictBar(bar, "predictAll", PREDICT_OTHERS, 1)
  local mineBar = PredictBar(bar, "predictMine", PREDICT_MINE, 2)
  if not alive then
    bar.incomingMine:Hide()
    bar.incomingOthers:Hide()
    all:Hide()
    mineBar:Hide()
    over:Hide()
    return
  end
  local fill = bar:GetStatusBarTexture()
  ClipTo(bar)

  -- The secret path: hand the raw values to the bars and let the widget do
  -- the measuring. The old textures stay out of the way.
  bar.incomingMine:Hide()
  bar.incomingOthers:Hide()
  -- Raw from the game when there is one (secret or not); otherwise the plain
  -- numbers, which is what the unlocked preview and the self-test hand over.
  local allValue, mineValue = s.incomingAllRaw, s.incomingMineRaw
  if type(allValue) == "nil" and not s.incomingSecret then
    local total = (s.incomingMine or 0) + (s.incomingOthers or 0)
    allValue = total > 0 and total or nil
  end
  if type(mineValue) == "nil" and not s.incomingSecret and (s.incomingMine or 0) > 0 then
    mineValue = s.incomingMine
  end
  if ns.IncomingColors then
    local mine, others = ns.IncomingColors()
    all:SetStatusBarColor(others[1], others[2], others[3], others[4] or 0.4)
    mineBar:SetStatusBarColor(mine[1], mine[2], mine[3], mine[4] or 0.4)
  end
  PlacePredict(all, bar, fill, allValue, s.healthMax)
  PlacePredict(mineBar, bar, fill, mineValue, s.healthMax)

  -- The overheal strip is arithmetic; when the numbers refuse, it just stays off.
  if not pcall(ns.RenderOverheal, bar, s, all) then over:Hide() end
end

-- Overhealing: how much of what is coming lands on someone already full.
--
-- This is arithmetic -- incoming, minus what is missing -- so it can only be
-- drawn on a client that lets an addon read those numbers. On Forever they
-- are secret, and there is no way round it: the widgets do not give it away
-- either. A status bar filled from a secret value draws correctly, but its
-- fill texture reports the bar's FULL width whatever the value is (checked
-- in the client: a bar of 100 showing 90% answered 100), because the fill is
-- drawn with texture coordinates rather than by resizing. So there is nothing
-- to measure, and the strip stays hidden until Blizzard stops hiding the
-- numbers -- at which point this works again with no further change.
function ns.RenderOverheal(bar, s, _)
  local over = OverhealTexture(bar)
  if ns.db.showOverheal == false or s.incomingSecret then
    over:Hide()
    return 0
  end
  local _, _, overWidth = ns.IncomingWidths(s)
  if overWidth < 1 then
    over:Hide()
    return 0
  end
  over:ClearAllPoints()
  over:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  over:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  over:SetWidth(math.min(overWidth, BarWidth()))
  over:Show()
  return overWidth
end

function ns.RenderDispel(button, s, enabled)
  local bar = button.health
  local color = enabled and s.dispelType and ns.DISPEL_COLORS[s.dispelType]
  if color then
    button.edge:SetColorTexture(color[1], color[2], color[3], 1)
    bar.dispelTint:SetColorTexture(color[1], color[2], color[3], 0.3)
    bar.dispelTint:Show()
    -- If it's already drawn in a corner, the coloured edge is enough: the same
    -- icon twice on one frame is the thing this avoids.
    if ns.IsWatched(s.dispelSpell) then
      bar.dispelIcon:Hide()
    else
      bar.dispelIcon:SetTexture(s.dispelIcon)
      bar.dispelIcon:Show()
    end
  else
    local r, g, b = ns.EdgeColor(button, s)
    button.edge:SetColorTexture(r, g, b, 1)
    bar.dispelTint:Hide()
    bar.dispelIcon:Hide()
  end
end

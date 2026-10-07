local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- The HoT row, drawn by the game.
--
-- In a fight Forever hides auras from addons, so the row we read ourselves
-- went blank at the pull. Guessing from your own casts (Inference.lua) filled
-- in solo, but in a group the game hides everyone's name as well, and every
-- guess was lost: Rejuvenation and Regrowth vanished the moment a dungeon
-- pull started (owner, 25 Sept 2026).
--
-- So the row isn't read at all any more. Each frame carries one of the game's
-- own aura containers (CustomAuraContainerTemplate, the same one the unit
-- frames' buffs use) asked for "my buffs that last a minute or less" - your
-- HoTs and shields - soonest to run out first. The game fills it in, in or
-- out of combat, grouped or solo, with the real time left. We only say how
-- big, how many and where: the HoT row's own settings.
--
-- The icons inside are locked to addons while auras are secret, so a
-- container is only ever made out of combat (a frame that first appears
-- mid-fight falls back to the guesses until it ends). Moving and resizing it
-- is fine at any time: the container itself is ours.

ns.gameHotStats = { made = 0, refused = 0, lastError = nil }

local GAP = 1

local function Available()
  -- Not while the controller's navigation is live (Core/Controller.lua).
  if FUI.AuraContainersAllowed then return FUI.AuraContainersAllowed() end
  return _G.CustomAuraContainerGroupDefaultOptions ~= nil
end
ns.GameHotsAvailable = Available

local function StyleButton(button, holder)
  pcall(function()
    local size = holder.fuiSize or 13
    button:SetSize(size, size)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(false) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetCountdownFont then pcall(cooldown.SetCountdownFont, cooldown, "NumberFontNormalSmall") end
    button:SetDurationCooldown(cooldown)
    holder.fuiCooldowns[#holder.fuiCooldowns + 1] = cooldown

    -- Stacks, for a buff that builds (the game writes "2", "3"...; nothing
    -- for a single application). Above the timer so both stay readable.
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(cooldown:GetFrameLevel() + 2)
    local count = over:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", math.max(7, math.floor(size * 0.6)), "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", 2, -1)
    button:SetApplicationCount(count)
  end)
end

-- A spell you watch in a corner shows there, not also in the row (the rule
-- our own row always had: what you placed deliberately wins). The game's
-- container is told by spell ID, so every rank you know of each one.
-- Rebuilt only when the watched names or the spellbook change.
local exclude, excludeKey = {}, nil
local spellbookGeneration = 0

local function Excluded()
  local names = {}
  for name in pairs(ns.WatchedNames and ns.WatchedNames() or {}) do
    if ns.WatchCoversMine(name) then names[#names + 1] = name end
  end
  table.sort(names)
  local key = spellbookGeneration .. "|" .. table.concat(names, "|")
  if key ~= excludeKey then
    excludeKey, exclude = key, {}
    local _, byName = ns.ScanSpellbook(true)
    for _, name in ipairs(names) do
      local entry = byName[name]
      if entry then
        if entry.spellID then exclude[entry.spellID] = true end
        for _, rank in ipairs(entry.ranks or {}) do
          if rank.spellID then exclude[rank.spellID] = true end
        end
      end
    end
  end
  return exclude, excludeKey
end
ns.GameHotsExcluded = Excluded

local books = CreateFrame("Frame")
pcall(books.RegisterEvent, books, "SPELLS_CHANGED")
books:SetScript("OnEvent", function() spellbookGeneration = spellbookGeneration + 1 end)

-- Watched spells in the corners, drawn by the game too (owner, 25 Sept 2026:
-- "still not loading hots in combat when in group"). Rejuvenation and
-- Regrowth watched in a corner were ForeverUI's own reads, and in combat its
-- guesses - which grouped only work for casts you click onto a frame. So
-- each spell the game can match gets one of its "aura slots": a single icon
-- for exactly that spell (every rank you know), placed in the spell's
-- corner. Only helpful spells, drawn as icons, yours or anyone's: matching by
-- spell ID is allowed for buffs on you and your group, not for debuffs.
local MAX_SLOTS = 6
local specs, specsKey = {}, nil

function ns.GameWatchKey(entry)
  return (entry.spell or "") .. "|" .. (entry.mine or "any")
end

local function WatchSpecs()
  local list = ns.db.auraWatch or {}
  local parts = { spellbookGeneration, ns.db.auraSize or 13 }
  for _, entry in ipairs(list) do
    parts[#parts + 1] = table.concat({ entry.spell or "", entry.mine or "any", entry.style or "icon",
      entry.corner or 1, entry.size or 0, entry.dx or 0, entry.dy or 0 }, ":")
  end
  local key = table.concat(parts, "|")
  if key == specsKey then
    return specs, specsKey
  end
  specsKey, specs = key, {}
  local _, byName = ns.ScanSpellbook(true)
  for _, entry in ipairs(list) do
    local known = byName[entry.spell or ""]
    if #specs < MAX_SLOTS and known and known.helpful ~= false and (entry.style or "icon") == "icon"
      and entry.mine ~= "others" then
      local ids = {}
      if known.spellID then ids[known.spellID] = true end
      for _, rank in ipairs(known.ranks or {}) do
        if rank.spellID then ids[rank.spellID] = true end
      end
      if next(ids) then
        specs[#specs + 1] = {
          key = ns.GameWatchKey(entry), ids = ids,
          filter = entry.mine == "mine" and "HELPFUL|PLAYER" or "HELPFUL",
          corner = entry.corner or 1, size = entry.size or ns.db.auraSize or 13,
          dx = entry.dx or 0, dy = entry.dy or 0,
        }
      end
    end
  end
  return specs, specsKey
end
ns.GameWatchSpecs = WatchSpecs

local function Filters()
  local ids = Excluded()
  return {
    maxDuration = math.max(1, tonumber(ns.db.hotMaxDuration) or 60),
    excludeSpellIDs = next(ids) and ids or nil,
  }
end

-- Made once per frame, out of combat, for a frame that has a real unit.
local function Container(button, bar)
  if button.gameHots or button.gameHotsFailed then
    return button.gameHots
  end
  if InCombatLockdown and InCombatLockdown() then
    return nil
  end
  local ok, err = pcall(function()
    local c = CreateFrame("AuraContainer", nil, bar.hots or bar, "CustomAuraContainerTemplate")
    c.fuiCooldowns = {}
    c.fuiSize = ns.db.auraSize or 13
    c:SetUnit(button.unit)
    c:AddAuraGroup("mine", "HELPFUL|PLAYER", {
      maxFrameCount = ns.MAX_HOTS or 3,
      initializeFrame = function(b) StyleButton(b, c) end,
      candidateFilters = Filters(),
      sortMethod = _G.AuraContainerSortMethod and _G.AuraContainerSortMethod.Expiration or nil,
      layout = { elementSpacing = GAP, elementWidth = c.fuiSize, elementHeight = c.fuiSize },
    })
    for i = 1, MAX_SLOTS do
      c:AddAuraSlot("w" .. i, "HELPFUL", {
        initializeFrame = function(b) StyleButton(b, c) end,
        candidateFilters = { includeSpellIDs = {} },
      })
      c:SetAuraSlotEnabled("w" .. i, false)
    end
    c:SetEnabled(true)
    c.fuiUnit = button.unit
    button.gameHots = c
    bar.fuiGameHots = c
  end)
  if ok then
    ns.gameHotStats.made = ns.gameHotStats.made + 1
  else
    button.gameHotsFailed = true
    ns.gameHotStats.refused = ns.gameHotStats.refused + 1
    ns.gameHotStats.lastError = tostring(err)
  end
  return button.gameHots
end

-- Point the slots at this grid's watched spells. Out of combat only.
local function ConfigureSlots(c, list)
  for i = 1, MAX_SLOTS do
    local key, spec = "w" .. i, list[i]
    if spec then
      c:SetAuraSlotFilterString(key, spec.filter)
      c:SetAuraSlotCandidateFilters(key, { includeSpellIDs = spec.ids })
      c:SetAuraSlotEnabled(key, true)
      local frame = c:GetAuraSlotFrame(key)
      if frame then frame:SetSize(spec.size, spec.size) end
    else
      c:SetAuraSlotEnabled(key, false)
    end
  end
end

-- Which watched spells the game draws on this frame, so the frame's own
-- corner icons leave them out (s.gameWatched, read by ns.ReadWatched).
local function MarkDrawn(s, list)
  local drawn = {}
  for _, spec in ipairs(list) do drawn[spec.key] = true end
  s.gameWatched = next(drawn) and drawn or nil
  -- This redraw's corners were read before we knew: drop them now.
  for slot, item in pairs(s.watch or {}) do
    if item and s.gameWatched and s.gameWatched[(item.spell or "") .. "|" .. (item.mine or "any")] then
      s.watch[slot] = nil
    end
  end
end

-- Returns true when the game is drawing this frame's HoT row, so our own
-- row stays empty. Called from each redraw, with that grid's settings lent.
-- `watch`: the corners are on (and the frame alive).
function ns.RenderGameHots(button, bar, s, show, watch)
  if not ns.db.gameHots or not Available() or not button.gameHotsEligible
    or not button.unit or not (bar and bar.hots) then
    if button.gameHots then button.gameHots:Hide() end
    if s then s.gameWatched = nil end
    return false
  end
  local c = Container(button, bar)
  if not c then
    return false
  end
  local ok = pcall(function()
    if c.fuiUnit ~= button.unit then
      c:SetUnit(button.unit)
      c.fuiUnit = button.unit
    end
    -- Settings that change the icons themselves wait for the fight to end.
    local size = ns.db.auraSize or 13
    local limit = ns.db.hotMaxDuration
    local timers = ns.db.auraTimer ~= "off"
    local calm = not (InCombatLockdown and InCombatLockdown())
    local watched
    if calm then
      local _, key = Excluded()
      watched = key
      local list, listKey = WatchSpecs()
      if c.fuiSlotsKey ~= listKey then
        ConfigureSlots(c, list)
        c.fuiSlotsKey, c.fuiSlots = listKey, list
      end
    end
    local slots = c.fuiSlots or {}
    MarkDrawn(s, (watch and slots) or {})
    if calm and (c.fuiSize ~= size or c.fuiLimit ~= limit or c.fuiTimers ~= timers
      or c.fuiWatched ~= watched) then
      c.fuiSize, c.fuiLimit, c.fuiTimers, c.fuiWatched = size, limit, timers, watched
      c:SetAuraGroupCandidateFilters("mine", Filters())
      c:SetAuraGroupLayout("mine", { elementSpacing = GAP, elementWidth = size, elementHeight = size })
      for i = 1, c:GetAuraGroupFrameCount("mine") do
        local b = c:GetAuraGroupFrame("mine", i)
        if b then b:SetSize(size, size) end
      end
      for _, cooldown in ipairs(c.fuiCooldowns) do
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(not timers) end
      end
    end
    c:SetAuraGroupEnabled("mine", show and true or false)
    c:SetShown((show or (watch and #slots > 0)) and true or false)
  end)
  return ok and show and true or false
end

-- The corner slots, each in its spell's corner after `before` pixels of the
-- frame's own icons there. Returns how many pixels they take in that corner.
-- Out of combat only: the game's icons are locked to addons in a fight, and
-- they keep the place they were given.
function ns.PlaceGameWatch(bar, corner, point, dx, dy, before, gap)
  local c = bar and bar.fuiGameHots
  if not c or not c:IsShown() or not c.fuiSlots or (InCombatLockdown and InCombatLockdown()) then
    return 0
  end
  local used = 0
  pcall(function()
    local sign = point:find("RIGHT") and -1 or 1
    for i, spec in ipairs(c.fuiSlots) do
      if spec.corner == corner then
        local frame = c:GetAuraSlotFrame("w" .. i)
        if frame then
          frame:ClearAllPoints()
          frame:SetPoint(point, bar.hots, point, dx + sign * (before + used) + spec.dx, dy + spec.dy)
        end
        used = used + spec.size + (gap or GAP)
      end
    end
  end)
  return used
end

-- Where the row goes: the HoT row's place, after any watched spells sharing
-- it (`before` is how many pixels of them there are). Called from PlaceAuras.
function ns.PlaceGameHots(bar, point, dx, dy, before)
  local c = bar and bar.fuiGameHots
  if not c or not c:IsShown() then return end
  pcall(function()
    local right = point:find("RIGHT") ~= nil
    local vertical = (point:find("TOP") and "TOP") or (point:find("BOTTOM") and "BOTTOM") or ""
    local flow = AnchorUtil and AnchorUtil.FlowDirection
    c:SetFlowLayoutAnchorPoint(vertical .. (right and "RIGHT" or "LEFT"))
    if flow then
      c:SetFlowLayoutGrowthDirection(right and flow.Left or flow.Right,
        vertical == "BOTTOM" and flow.Up or flow.Down)
    end
    c:ClearAllPoints()
    c:SetPoint(point, bar.hots, point, dx + (right and -before or before), dy)
  end)
end

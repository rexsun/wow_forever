local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Buff Watch (docs/vuhdo-parity.md, phase 3 - VuhDo's buff panel).
--
-- A small movable panel with one button per group buff your class brings
-- (the same list the frames' missing-buff icon uses - Auras page):
--
--   red     somebody is missing it - the number says how many
--   yellow  somebody's runs out soon
--   green   everyone has it
--
-- Click the button and it casts that buff on the next person who needs it,
-- or the group version (Prayer of Fortitude, Gift of the Wild) when enough of
-- them do. The button is an ordinary secure action button whose spell and
-- unit are set out of combat; auras can't be read in a fight on Forever, so
-- the panel freezes (dimmed) until the fight ends - which is when you rebuff
-- anyway.

for key, value in pairs({
  showBuffWatch = false,
  buffWatchSoon = 60,          -- seconds left that count as "runs out soon"
  buffWatchGroupAt = 3,        -- this many needing it: cast the group version
  buffWatchPosition = { "CENTER", "CENTER", 0, 240 },
}) do
  if ns.DEFAULTS[key] == nil then
    ns.DEFAULTS[key] = type(value) == "table" and ns.CopyTable(value) or value
  end
end

local ROW_SIZE = 30
local MAX_ROWS = 6
local anchor
local rows = {}
local results = {}
ns.buffWatchRows = rows

---------------------------------------------------------------------------
-- Reading the group
---------------------------------------------------------------------------

local function Roster()
  local list = {}
  if IsInRaid and IsInRaid() then
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
      list[#list + 1] = "raid" .. i
    end
  else
    list[1] = "player"
    for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
      list[#list + 1] = "party" .. i
    end
  end
  return list
end
ns.BuffWatchRoster = Roster

local function Plain(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

local function Name(unit)
  local ok, name = pcall(UnitName, unit)
  name = ok and Plain(name) or nil
  return type(name) == "string" and name or unit
end

-- Can this unit be read and buffed at all right now?
local function Reachable(unit)
  if UnitExists and not ns.Secrets.Bool(UnitExists(unit), false) then return false end
  if UnitIsConnected and not ns.Secrets.Bool(UnitIsConnected(unit), true) then return false end
  if UnitIsDeadOrGhost and ns.Secrets.Bool(UnitIsDeadOrGhost(unit), false) then return false end
  if UnitIsVisible and not ns.Secrets.Bool(UnitIsVisible(unit), true) then return false end
  return true
end

local function Unreadable()
  return ns.Secrets.AurasSecret() or ns.Secrets.AurasRestricted() or ns.Secrets.AurasBlocked()
end

local function PowerIsMana(unit)
  if not UnitPowerType then return true end
  local ok, _, token = pcall(UnitPowerType, unit)
  token = ok and Plain(token) or nil
  return token == nil or token == "MANA"
end

-- What each of your buffs needs. nil when the auras can't be read (a fight).
function ns.ScanBuffWatch(now)
  if Unreadable() then
    return nil
  end
  now = now or GetTime()
  local soonAt = ns.db.buffWatchSoon or 60
  local list = ns.GroupBuffList and ns.GroupBuffList() or {}
  local out = {}
  for index, buff in ipairs(list) do
    out[index] = { buff = buff, spell = buff.spell, icon = buff.icon, missing = {}, soon = {}, checked = 0 }
  end
  for _, unit in ipairs(Roster()) do
    if Reachable(unit) then
      local has = {}
      for i = 1, 40 do
        local found, _, _, duration, expires, name, _, mine = ns.AuraAt(unit, i, "HELPFUL")
        if not found then break end
        if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
          for index, buff in ipairs(list) do
            if not has[index] and ns.BuffCovers(buff, name, mine) then
              local left = (type(expires) == "number" and type(duration) == "number" and duration > 0)
                and (expires - now) or nil
              has[index] = { left = left }
            end
          end
        end
      end
      if ns.Secrets.AurasBlocked() then
        return nil -- refused part-way: what we have isn't the whole picture
      end
      for index, buff in ipairs(list) do
        if not (buff.manaOnly and not PowerIsMana(unit)) then
          local r = out[index]
          r.checked = r.checked + 1
          local got = has[index]
          if not got then
            r.missing[#r.missing + 1] = unit
          elseif got.left and got.left < soonAt then
            r.soon[#r.soon + 1] = unit
          end
        end
      end
    end
  end
  -- Who the button casts on, and with which spell.
  local _, known = ns.ScanSpellbook(false)
  for _, r in ipairs(out) do
    r.target = r.missing[1] or r.soon[1]
    r.cast = r.spell
    local need = #r.missing + #r.soon
    local group
    for name in pairs(r.buff.names or {}) do
      if name ~= r.spell and known[name] then group = name end
    end
    if group and need >= (ns.db.buffWatchGroupAt or 3) then
      r.cast = group
    end
    r.state = (#r.missing > 0 and "missing") or (#r.soon > 0 and "soon") or "ok"
  end
  return out
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local COLORS = {
  missing = { 0.90, 0.20, 0.20 },
  soon = { 1.00, 0.80, 0.15 },
  ok = { 0.25, 0.85, 0.35 },
}

local function Capture()
  if not anchor then return end
  local point, _, relative, x, y = anchor:GetPoint()
  if point and x and y then ns.db.buffWatchPosition = { point, relative, x, y } end
end
ns.CaptureBuffWatchPosition = Capture

local function Row(index)
  if rows[index] then return rows[index] end
  local button = CreateFrame("Button", "ForeverUIFramesBuffWatch" .. index, anchor, "SecureActionButtonTemplate")
  button:SetSize(ROW_SIZE, ROW_SIZE)
  button:RegisterForClicks("AnyUp")
  button:SetAttribute("type", "spell")
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetPoint("TOPLEFT", 2, -2)
  button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.edge = button:CreateTexture(nil, "BACKGROUND")
  button.edge:SetAllPoints()
  button.count = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.count:SetPoint("LEFT", button, "RIGHT", 6, 0)
  button:SetScript("OnEnter", function(self)
    local r = self.result
    if not r or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.spell)
    local function names(units, label)
      if #units == 0 then return end
      local list = {}
      for i, unit in ipairs(units) do
        if i > 10 then list[#list + 1] = "..."; break end
        list[#list + 1] = Name(unit)
      end
      GameTooltip:AddLine(label .. table.concat(list, ", "), 1, 1, 1, true)
    end
    names(r.missing, "Missing: ")
    names(r.soon, "Running out: ")
    if r.target then GameTooltip:AddLine("Click: " .. r.cast .. " on " .. Name(r.target), 0.3, 0.76, 1) end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  rows[index] = button
  return button
end

local function Build()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", "ForeverUIFramesBuffWatchAnchor", UIParent)
  anchor:SetSize(140, 16)
  anchor:SetFrameStrata("MEDIUM")
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  anchor:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); Capture() end)
  anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
  anchor.bg:SetAllPoints()
  anchor.bg:SetColorTexture(0.07, 0.07, 0.09, 0.85)
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  anchor.label:SetPoint("CENTER")
  anchor.label:SetText("Buff Watch - drag")
  anchor.label:SetTextColor(0.30, 0.76, 1.00)
  anchor.combat = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  anchor.combat:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
  anchor.combat:SetText("in combat - rebuff after")
  anchor.combat:Hide()
  ns.buffWatchAnchor = anchor
  return anchor
end

local function Place()
  local p = ns.db.buffWatchPosition or ns.DEFAULTS.buffWatchPosition
  anchor:ClearAllPoints()
  anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function ns.SetBuffWatchLocked(locked)
  if not anchor then return end
  anchor:EnableMouse(not locked)
  anchor.bg:SetShown(not locked)
  anchor.label:SetShown(not locked)
end

-- Draw what the scan found. Attributes (what a click casts on whom) are
-- secure, so they only change out of combat; in combat the panel is dimmed
-- and left as it was.
function ns.ApplyBuffWatch()
  local on = ns.db.showBuffWatch and true or false
  if not on and not anchor then return end
  if InCombatLockdown() then
    if anchor then
      anchor:SetAlpha(0.45)
      anchor.combat:SetShown(anchor:IsShown())
    end
    return
  end
  Build()
  Place()
  anchor:SetAlpha(1)
  anchor.combat:Hide()
  local scanned = on and ns.ScanBuffWatch() or nil
  if scanned then results = scanned end
  local list = on and results or {}
  anchor:SetShown(on and #list > 0)
  for index = 1, MAX_ROWS do
    local r = list[index]
    local button = (r or rows[index]) and Row(index)
    if button then
      if r then
        button.result = r
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2 - (index - 1) * (ROW_SIZE + 2))
        button.icon:SetTexture(r.icon)
        local c = COLORS[r.state] or COLORS.ok
        button.edge:SetColorTexture(c[1], c[2], c[3], 1)
        local need = #r.missing + #r.soon
        button.count:SetText(r.state == "ok" and "all" or (r.state == "missing"
          and ("%d missing"):format(#r.missing) or ("%d soon"):format(#r.soon)))
        button.count:SetTextColor(c[1], c[2], c[3])
        button:SetAttribute("spell", need > 0 and r.cast or nil)
        button:SetAttribute("unit", r.target)
        button:Show()
      else
        button.result = nil
        button:SetAttribute("spell", nil)
        button:Hide()
      end
    end
  end
  ns.SetBuffWatchLocked(ns.db.locked)
end

---------------------------------------------------------------------------
-- When to look again
---------------------------------------------------------------------------

local dirty = false
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED" }) do
  ns.RegisterEvent(watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
  if not ns.booted or not ns.db.showBuffWatch then return end
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    ns.ApplyBuffWatch()
  else
    dirty = true
  end
end)
local since = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  -- Half a second after a change, and every few seconds for the countdowns.
  if since < (dirty and 0.5 or 3) then return end
  since = 0
  if dirty or (ns.db and ns.db.showBuffWatch) then
    dirty = false
    if ns.booted and ns.db.showBuffWatch then ns.ApplyBuffWatch() end
  end
end)
ns.buffWatchWatcher = watcher

ns.SETTING_APPLY.showBuffWatch = function() ns.ApplyBuffWatch() end
ns.SETTING_APPLY.buffWatchSoon = function() ns.ApplyBuffWatch() end
ns.SETTING_APPLY.buffWatchGroupAt = function() ns.ApplyBuffWatch() end

local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Looks (docs/vuhdo-parity.md, phase 4):
--
--   HoT bars        a thin bar per HoT along the bottom of the frame, shrinking
--                   as it runs out - VuhDo's "HoT bars", next to the icons.
--   Debuff icons    how many the game draws (1-5), how big, which corner, and
--                   whether it shows only what you can dispel or every debuff.
--   State colours   dead players' bars, incoming heals (yours and others').
--   Class colours   your own palette; any class you don't change keeps the
--                   game's colour.

for key, value in pairs({
  hotBars = false,
  hotBarHeight = 3,
  hotBarCount = 3,
  hotBarColor = { 0.35, 0.95, 0.45 },
  debuffIconCount = 3,
  debuffIconSize = 12,
  debuffIconPosition = "BOTTOMLEFT",
  debuffShowAll = false,           -- every debuff, not only the ones you can dispel
  colorDead = false,
  deadColor = { 0.45, 0.08, 0.08 },
  incomingMineColor = false,       -- false: the built-in colours
  incomingOthersColor = false,
}) do
  if ns.DEFAULTS[key] == nil then
    ns.DEFAULTS[key] = type(value) == "table" and ns.CopyTable(value) or value
  end
end

---------------------------------------------------------------------------
-- Class colours
---------------------------------------------------------------------------

ns.CLASS_LIST = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- r, g, b for a class: yours if you set one, the game's otherwise. In a
-- group the game hands addons other players' class as a SECRET string:
-- indexing RAID_CLASS_COLORS with it threw, the frame's whole draw stopped,
-- and with class-coloured names nothing drew at all. Then there's no class
-- colour (nil), and the frame falls back to its ordinary one.
function ns.ClassColor(class)
  if not class or (issecretvalue and issecretvalue(class)) then return nil end
  local mine = ns.db and ns.db["classColor_" .. class]
  if type(mine) == "table" and mine[1] then
    return mine[1], mine[2], mine[3]
  end
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return nil
end

function ns.ResetClassColors()
  for _, class in ipairs(ns.CLASS_LIST) do
    ns.db["classColor_" .. class] = nil
  end
  ns.ApplyAppearance()
  ns.RefreshAll()
end

---------------------------------------------------------------------------
-- HoT bars
---------------------------------------------------------------------------

-- Everything on the frame with a known length: watched spells first (they
-- carry their own colour), then the HoT row.
local function Timed(s)
  local list = {}
  for i = 1, s.watchSlots or 0 do
    local w = s.watch and s.watch[i]
    if w and type(w.duration) == "number" and w.duration > 0 and type(w.expires) == "number" then
      list[#list + 1] = { duration = w.duration, expires = w.expires, color = w.color }
    end
  end
  for i = 1, s.hotCount or 0 do
    local h = s.hots and s.hots[i]
    if h and type(h.duration) == "number" and h.duration > 0 and type(h.expires) == "number" then
      list[#list + 1] = { duration = h.duration, expires = h.expires }
    end
  end
  return list
end

local function Bars(bar)
  if bar.fuiHotBars then return bar.fuiHotBars end
  local host = ns.RoleLayer and ns.RoleLayer(bar) or bar
  local list = {}
  for i = 1, 5 do
    local t = host:CreateTexture(nil, "OVERLAY", nil, 3)
    t:SetColorTexture(1, 1, 1, 1)
    t:Hide()
    list[i] = t
  end
  bar.fuiHotBars = list
  return list
end

function ns.UpdateHotBars(button, now)
  local bar = button.health
  if not ns.db.hotBars then
    if bar.fuiHotBars then for _, t in ipairs(bar.fuiHotBars) do t:Hide() end end
    return
  end
  local s = button.state
  local alive = not (s.dead or s.ghost or s.offline)
  local list = alive and Timed(s) or {}
  local bars = Bars(bar)
  local width = (bar.GetWidth and bar:GetWidth()) or 0
  if width <= 0 then width = (ns.db.frameWidth or 120) - 2 end
  local height = ns.db.hotBarHeight or 3
  local count = math.min(ns.db.hotBarCount or 3, #bars)
  local base = ns.db.hotBarColor or { 0.35, 0.95, 0.45 }
  now = now or GetTime()
  for i, t in ipairs(bars) do
    local entry = i <= count and list[i]
    local left = entry and (entry.expires - now) or 0
    if entry and left > 0 then
      local fraction = math.max(0, math.min(1, left / entry.duration))
      local c = entry.color or base
      t:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 0.9)
      t:ClearAllPoints()
      t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, (i - 1) * (height + 1))
      t:SetSize(math.max(1, width * fraction), height)
      t:Show()
    else
      t:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- State colours
---------------------------------------------------------------------------

-- A dead player's bar: full, in your dead colour, instead of empty.
function ns.PaintDead(bar, s)
  if not ns.db.colorDead then return false end
  local c = ns.db.deadColor or ns.DEFAULTS.deadColor
  ns.Secrets.SetBar(bar, s.healthMax, s.healthMax)
  bar:SetStatusBarColor(c[1], c[2], c[3])
  return true
end

-- The two incoming-heal bars, in your colours when you've set them.
function ns.IncomingColors()
  local mine, others = ns.db.incomingMineColor, ns.db.incomingOthersColor
  local m = type(mine) == "table" and { mine[1], mine[2], mine[3], ns.PREDICT_MINE[4] } or ns.PREDICT_MINE
  local o = type(others) == "table" and { others[1], others[2], others[3], ns.PREDICT_OTHERS[4] } or ns.PREDICT_OTHERS
  return m, o
end

---------------------------------------------------------------------------
-- Debuff icons (the game draws them; these are its settings)
---------------------------------------------------------------------------

ns.DEBUFF_PLACES = {
  BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right", TOPLEFT = "Top left",
  TOPRIGHT = "Top right", CENTER = "Centre",
}

function ns.DebuffIconSettings()
  local count = math.max(1, math.min(5, ns.db.debuffIconCount or 3))
  local size = math.max(8, math.min(24, ns.db.debuffIconSize or 12))
  local place = ns.DEBUFF_PLACES[ns.db.debuffIconPosition] and ns.db.debuffIconPosition or "BOTTOMLEFT"
  return count, size, place, ns.db.debuffShowAll and true or false
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

local function Redraw() ns.RefreshAll() end
local function Reattach() if ns.ApplyGameAuras then ns.ApplyGameAuras(true) end end
for _, key in ipairs({ "hotBars", "hotBarHeight", "hotBarCount", "hotBarColor", "colorDead", "deadColor",
  "incomingMineColor", "incomingOthersColor" }) do
  ns.SETTING_APPLY[key] = Redraw
end
for _, key in ipairs({ "debuffIconCount", "debuffIconSize", "debuffIconPosition", "debuffShowAll" }) do
  ns.SETTING_APPLY[key] = Reattach
end
for _, class in ipairs(ns.CLASS_LIST) do
  ns.SETTING_APPLY["classColor_" .. class] = function() ns.ApplyAppearance(); ns.RefreshAll() end
end

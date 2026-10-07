local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Status on the frames (docs/vuhdo-parity.md, phases 1 and 4):
--
--   The raid marker     skull, cross, star... on whoever carries one.
--   One status icon     the first that applies of: ready check, an incoming
--                       summon, an incoming resurrection, dead, offline - in
--                       an order you set, each on or off. VuhDo builds this
--                       sort of thing out of "bouquets"; one ordered list is
--                       the part people actually use.
--
-- Everything read here can come back secret on Forever (Blizzard's own raid
-- frames read the same functions from secure code). A secret or a refusal is
-- treated as "nothing to show", never branched on.

for key, value in pairs({
  showRaidMarker = true,
  raidMarkerPosition = "TOP",
  raidMarkerSize = 14,
  showStatusIcon = true,
  statusPosition = "CENTER",
  statusSize = 18,
  statusOrder = { "ready", "summon", "rez", "dead", "offline" },
  statusShow = { ready = true, summon = true, rez = true, dead = false, offline = false },
}) do
  if ns.DEFAULTS[key] == nil then ns.DEFAULTS[key] = value end
end

ns.STATUS_KINDS = {
  ready = "Ready check",
  summon = "Incoming summon",
  rez = "Incoming resurrection",
  dead = "Dead",
  offline = "Offline",
}

local READY_TEXTURES = {
  ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
  notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
  waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local SUMMON_ATLAS = {
  pending = "Raid-Icon-SummonPending",
  accepted = "Raid-Icon-SummonAccepted",
  declined = "Raid-Icon-SummonDeclined",
}
local REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
local DEAD_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local OFFLINE_TEXTURE = "Interface\\CharacterFrame\\Disconnect-Icon"
local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- A value we may branch on, or nil.
local function Plain(ok, value)
  if not ok then return nil end
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return Plain(pcall(fn, ...))
end

---------------------------------------------------------------------------
-- Ready check window: shown from the check until a few seconds after it ends
---------------------------------------------------------------------------

local READY_LINGER = 10
local readyActive, readyEndsAt = false, nil

function ns.ReadyCheckShowing(now)
  if readyActive then return true end
  return readyEndsAt ~= nil and (now or GetTime()) < readyEndsAt
end

function ns.OnReadyCheck(event)
  if event == "READY_CHECK" then
    readyActive, readyEndsAt = true, nil
  elseif event == "READY_CHECK_FINISHED" then
    readyActive = false
    readyEndsAt = GetTime() + READY_LINGER
    if C_Timer and C_Timer.After then
      C_Timer.After(READY_LINGER + 0.1, function() ns.RefreshAll() end)
    end
  end
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

local SUMMON_STATUS = {}
local function SummonName(status)
  if not next(SUMMON_STATUS) and Enum and Enum.SummonStatus then
    SUMMON_STATUS[Enum.SummonStatus.Pending or 1] = "pending"
    SUMMON_STATUS[Enum.SummonStatus.Accepted or 2] = "accepted"
    SUMMON_STATUS[Enum.SummonStatus.Declined or 3] = "declined"
  end
  return SUMMON_STATUS[status] or ({ [1] = "pending", [2] = "accepted", [3] = "declined" })[status]
end

function ns.ReadStatus(unit, s)
  -- Secret on Forever (even solo): never compared; it is painted as it is.
  -- Read raw, not through Call: Call's Plain() turns a secret into nil, so
  -- the secret was never seen and no grid ever drew a raid mark.
  local okMarker, marker = false, nil
  if type(GetRaidTargetIndex) == "function" then okMarker, marker = pcall(GetRaidTargetIndex, unit) end
  if not okMarker then marker = nil end
  s.raidMarkerSecret = issecretvalue and issecretvalue(marker) or nil
  s.raidMarker = (not s.raidMarkerSecret and type(marker) == "number" and marker >= 1 and marker <= 8)
    and marker or nil
  s.readyCheck = nil
  if ns.ReadyCheckShowing() then
    local status = Call(GetReadyCheckStatus, unit)
    if READY_TEXTURES[status] then
      -- After the check, anyone who never answered wasn't ready.
      s.readyCheck = (not readyActive and status == "waiting") and "notready" or status
    end
  end
  s.summon = nil
  local summons = C_IncomingSummon
  if summons and Call(summons.HasIncomingSummon, unit) == true then
    s.summon = SummonName(Call(summons.IncomingSummonStatus, unit))
  end
  s.rezIncoming = Call(UnitHasIncomingResurrection, unit) == true
  return s
end

-- Which status wins: the first in your order that applies and is switched on.
function ns.StatusFor(s)
  local order = ns.db.statusOrder or ns.DEFAULTS.statusOrder
  local show = ns.db.statusShow or ns.DEFAULTS.statusShow
  for _, kind in ipairs(order) do
    if show[kind] then
      if kind == "ready" and s.readyCheck then
        return "ready", READY_TEXTURES[s.readyCheck]
      elseif kind == "summon" and s.summon then
        return "summon", nil, SUMMON_ATLAS[s.summon]
      elseif kind == "rez" and s.rezIncoming and (s.dead or s.ghost) then
        return "rez", REZ_TEXTURE
      elseif kind == "dead" and (s.dead or s.ghost) then
        return "dead", DEAD_TEXTURE
      elseif kind == "offline" and s.offline then
        return "offline", OFFLINE_TEXTURE
      end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Icon(bar, key)
  local layer = ns.RoleLayer(bar)
  local icon = bar[key]
  if not icon then
    icon = layer:CreateTexture(nil, "OVERLAY", nil, 2)
    icon:Hide()
    bar[key] = icon
  end
  return icon
end

function ns.MarkerTexCoord(index)
  local i = (index or 1) - 1
  local col, row = i % 4, math.floor(i / 4)
  return col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25
end

function ns.RenderStatus(button, s)
  local bar = button.health
  local db = ns.db
  -- Raid marker.
  local marker = db.showRaidMarker ~= false and s.raidMarker
  local secretMarker = db.showRaidMarker ~= false and s.raidMarkerSecret
  if marker or secretMarker or bar.fuiMarker then
    local icon = Icon(bar, "fuiMarker")
    local size = db.raidMarkerSize or 14
    if marker then
      icon:SetTexture(MARKER_SHEET)
      icon:SetTexCoord(ns.MarkerTexCoord(marker))
      icon:SetSize(size, size)
      ns.PlaceOnBar(icon, bar, db.raidMarkerPosition or "TOP")
      icon:Show()
    elseif secretMarker and ns.Secrets.PaintRaidMark(icon, s.unit or button.unit) then
      icon:SetSize(size, size)
      ns.PlaceOnBar(icon, bar, db.raidMarkerPosition or "TOP")
    else
      icon:Hide()
    end
  end
  -- The one status icon.
  local kind, texture, atlas
  if db.showStatusIcon ~= false then
    kind, texture, atlas = ns.StatusFor(s)
  end
  if kind or bar.fuiStatus then
    local icon = Icon(bar, "fuiStatus")
    if kind then
      icon:SetTexCoord(0, 1, 0, 1)
      local drawn = atlas and icon.SetAtlas and pcall(icon.SetAtlas, icon, atlas)
      if not drawn then
        icon:SetTexture(texture or REZ_TEXTURE)
      end
      local size = db.statusSize or 18
      icon:SetSize(size, size)
      ns.PlaceOnBar(icon, bar, db.statusPosition or "CENTER")
      icon:Show()
    else
      icon:Hide()
    end
    button.state.statusKind = kind
  end
end

-- Move a status kind up (-1) or down (+1) the list.
function ns.MoveStatus(index, delta)
  local order = ns.db.statusOrder
  if type(order) ~= "table" then
    order = ns.CopyTable(ns.DEFAULTS.statusOrder)
    ns.db.statusOrder = order
  end
  local other = index + delta
  if not order[index] or not order[other] then return false end
  order[index], order[other] = order[other], order[index]
  ns.SetSetting("statusOrder", order)
  return true
end

function ns.ToggleStatus(kind)
  local show = ns.db.statusShow
  if type(show) ~= "table" then
    show = ns.CopyTable(ns.DEFAULTS.statusShow)
    ns.db.statusShow = show
  end
  show[kind] = not show[kind]
  ns.SetSetting("statusShow", show)
  return show[kind]
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
for _, event in ipairs({
  "RAID_TARGET_UPDATE", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
  "INCOMING_RESURRECT_CHANGED", "INCOMING_SUMMON_CHANGED",
}) do
  ns.RegisterEvent(watcher, event)
end
watcher:SetScript("OnEvent", function(_, event)
  if not ns.booted then return end
  if event == "READY_CHECK" or event == "READY_CHECK_FINISHED" then
    ns.OnReadyCheck(event)
  end
  ns.RefreshAll()
end)
ns.statusWatcher = watcher

local _, FUI = ...   -- ForeverUI's shared table
FUI.Frames = FUI.Frames or {}   -- the frame engine's own private namespace
local ns = FUI.Frames

-- Dispels in combat, drawn by the game.
--
-- An addon can't read auras during a fight on Forever, but Blizzard's own raid
-- frames still show what you can dispel. They don't read the auras either:
-- they register a "private aura anchor" - a frame plus a handful of settings -
-- and a secure, built-in addon (Blizzard_PrivateAurasUI) draws the icons and
-- the coloured overlay into it. That registration call is open to addons, so
-- each HealForever frame carries a small holder frame and asks for the same
-- service: dispellable debuffs only, no buffs, no other debuffs.
--
-- We never learn what is on anybody. The game just paints it for us.

ns.gameAuraStats = { asked = 0, granted = 0, refused = 0, lastError = nil }
ns.gameBuffStats = { asked = 0, granted = 0, refused = 0, lastError = nil }

local function Available()
  return C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor and C_UnitAuras.RemovePrivateAuraAnchor
end

local function EnumValue(group, key, fallback)
  local enum = Enum and Enum[group]
  return (enum and enum[key]) or fallback
end

-- The settings Blizzard_PrivateAurasUI reads off the holder. Scalars only, and
-- every one of them present: it does arithmetic on the sizes.
local function Settings(holder)
  local byMe = EnumValue("RaidDispelDisplayType", "DispellableByMe", 1)
  -- How many, how big, and dispellable-only or every debuff: Looks.lua.
  local count, size, _, all = 3, 12, nil, false
  if ns.DebuffIconSettings then count, size, _, all = ns.DebuffIconSettings() end
  holder:SetAttribute("max-buffs", 0)
  holder:SetAttribute("max-debuffs", all and count or 0)
  holder:SetAttribute("max-dispel-debuffs", count)
  holder:SetAttribute("aura-organization-type", EnumValue("RaidAuraOrganizationType", "Legacy", 0))
  holder:SetAttribute("display-only-dispellable-debuffs", not all)
  holder:SetAttribute("ignore-buffs", true)
  holder:SetAttribute("ignore-debuffs", not all)
  holder:SetAttribute("ignore-dispel-debuffs", false)
  holder:SetAttribute("dispel-indicator-option", byMe)
  holder:SetAttribute("display-larger-role-specific-debuffs", false)
  holder:SetAttribute("dispel-indicator-overlay-type", EnumValue("RaidDispelOverlayType", "UseDebuffColor", 1))
  holder:SetAttribute("dispel-indicator-overlay-animation", false)
  holder:SetAttribute("dispel-indicator-animated-border", false)
  holder:SetAttribute("show-big-defensive", false)
  holder:SetAttribute("big-defensive-size", 20)
  holder:SetAttribute("debuff-size", size)
  holder:SetAttribute("buff-size", 12)
  holder:SetAttribute("debuff-border-scale", 1)
  holder:SetAttribute("buff-border-scale", 1)
  holder:SetAttribute("always-hide-duration", true)
  holder:SetAttribute("set-aura-size-to-icon-size", true)
  holder:SetAttribute("power-bar-used-height", 0)
  holder:SetAttribute("group-type", EnumValue("EditModeUnitFrameSystemIndices", "Party", 0))
end

local function Holder(button)
  if not button.gameAuras then
    -- Its own frame: the secure side puts an OnAttributeChanged script on
    -- whatever it is handed, and the unit button already has one.
    local holder = CreateFrame("Frame", nil, button.health or button)
    holder:SetAllPoints()
    button.gameAuras = holder
  end
  return button.gameAuras
end

---------------------------------------------------------------------------
-- Buffs in combat, drawn by the game (24 Sept 2026, on trial)
--
-- The same service draws buffs: its settings have max-buffs, buff-size and
-- ignore-buffs, which the dispel holder above turns off. A second holder per
-- frame turns them on and everything else off, so everyone's HoTs and buffs
-- stay on the frames in a fight - drawn by the game, never read by us. The
-- dispel holder is untouched: if Forever won't draw buffs, nothing else
-- changes. Out of combat our own HoT row and watch corners say more, so by
-- default these fade in when a fight starts and out when it ends (alpha, not
-- Hide: the game's aura buttons inside are protected in combat).
---------------------------------------------------------------------------

local CORNER_OFFSET = { TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function BuffSettings(holder)
  local count = math.max(1, math.min(8, tonumber(ns.db.gameBuffsCount) or 4))
  local size = math.max(8, math.min(32, tonumber(ns.db.gameBuffsSize) or 14))
  holder:SetAttribute("max-buffs", count)
  holder:SetAttribute("max-debuffs", 0)
  holder:SetAttribute("max-dispel-debuffs", 0)
  holder:SetAttribute("aura-organization-type", EnumValue("RaidAuraOrganizationType", "Legacy", 0))
  holder:SetAttribute("display-only-dispellable-debuffs", false)
  holder:SetAttribute("ignore-buffs", false)
  holder:SetAttribute("ignore-debuffs", true)
  holder:SetAttribute("ignore-dispel-debuffs", true)
  holder:SetAttribute("dispel-indicator-option", EnumValue("RaidDispelDisplayType", "Disabled", 0))
  holder:SetAttribute("display-larger-role-specific-debuffs", false)
  holder:SetAttribute("dispel-indicator-overlay-type", EnumValue("RaidDispelOverlayType", "Disabled", 0))
  holder:SetAttribute("dispel-indicator-overlay-animation", false)
  holder:SetAttribute("dispel-indicator-animated-border", false)
  holder:SetAttribute("show-big-defensive", false)
  holder:SetAttribute("big-defensive-size", 20)
  holder:SetAttribute("debuff-size", size)
  holder:SetAttribute("buff-size", size)
  holder:SetAttribute("debuff-border-scale", 1)
  holder:SetAttribute("buff-border-scale", 1)
  holder:SetAttribute("always-hide-duration", true)
  holder:SetAttribute("set-aura-size-to-icon-size", true)
  holder:SetAttribute("power-bar-used-height", 0)
  holder:SetAttribute("group-type", EnumValue("EditModeUnitFrameSystemIndices", "Party", 0))
end
ns.GameBuffSettings = BuffSettings

local function BuffAlpha()
  if not ns.db.gameBuffsCombatOnly then return 1 end
  return (InCombatLockdown and InCombatLockdown()) and 1 or 0
end

local function BuffHolder(button)
  if not button.gameBuffs then
    local holder = CreateFrame("Frame", nil, button.health or button)
    holder:SetAllPoints()
    button.gameBuffs = holder
  end
  button.gameBuffs:SetAlpha(BuffAlpha())
  return button.gameBuffs
end

function ns.DetachGameBuffs(button)
  if button.gameBuffAnchor and Available() then
    pcall(C_UnitAuras.RemovePrivateAuraAnchor, button.gameBuffAnchor)
  end
  button.gameBuffAnchor, button.gameBuffUnit = nil, nil
end

-- Returns true when the game has agreed to draw this frame's buffs.
function ns.AttachGameBuffs(button, unit)
  if not unit or not ns.db.gameBuffs or not Available() then
    ns.DetachGameBuffs(button)
    return false
  end
  if button.gameBuffAnchor and button.gameBuffUnit == unit then
    return true
  end
  ns.DetachGameBuffs(button)
  local stats = ns.gameBuffStats
  stats.asked = stats.asked + 1
  local holder = BuffHolder(button)
  local place = ns.db.gameBuffsCorner or "TOPRIGHT"
  if not CORNER_OFFSET[place] then place = "TOPRIGHT" end
  local off = CORNER_OFFSET[place]
  local size = math.max(8, math.min(32, tonumber(ns.db.gameBuffsSize) or 14))
  local ok, anchorID = pcall(function()
    BuffSettings(holder)
    return C_UnitAuras.AddPrivateAuraAnchor({
      unitToken = unit,
      auraIndex = 1,
      parent = holder,
      showCooldownFrame = true,
      showCooldownEdge = false,
      showCountdownNumbers = false,
      showDispelIcon = false,
      isContainer = true,
      iconInfo = {
        iconAnchor = { point = place, relativeTo = holder, relativePoint = place, offsetX = off[1], offsetY = off[2] },
        iconWidth = size, iconHeight = size, borderScale = 1,
      },
    })
  end)
  if ok and anchorID then
    button.gameBuffAnchor, button.gameBuffUnit = anchorID, unit
    stats.granted = stats.granted + 1
    return true
  end
  stats.refused = stats.refused + 1
  stats.lastError = (not ok) and tostring(anchorID) or "no anchor returned"
  return false
end

-- Combat started or ended: fade the game-drawn buffs in or out.
function ns.GameBuffsCombat()
  local alpha = BuffAlpha()
  ns.ForEachButton(function(button)
    if button.gameBuffs then button.gameBuffs:SetAlpha(alpha) end
  end)
end

---------------------------------------------------------------------------
-- Dispels
---------------------------------------------------------------------------

local function DetachDispels(button)
  if button.gameAuraAnchor and Available() then
    pcall(C_UnitAuras.RemovePrivateAuraAnchor, button.gameAuraAnchor)
  end
  button.gameAuraAnchor, button.gameAuraUnit = nil, nil
end

function ns.DetachGameAuras(button)
  DetachDispels(button)
  ns.DetachGameBuffs(button)
end

-- Returns true when the game has agreed to draw this frame's dispels.
-- (Its buffs, when switched on, are asked for alongside.)
function ns.AttachGameAuras(button, unit)
  ns.AttachGameBuffs(button, unit)
  if not unit or not ns.db.gameDispels or not ns.db.showDispel or not Available() then
    DetachDispels(button)
    return false
  end
  if button.gameAuraAnchor and button.gameAuraUnit == unit then
    return true
  end
  DetachDispels(button)

  local stats = ns.gameAuraStats
  stats.asked = stats.asked + 1
  local holder = Holder(button)
  local _, size, place = 3, 12, "BOTTOMLEFT"
  if ns.DebuffIconSettings then _, size, place = ns.DebuffIconSettings() end
  local ok, anchorID = pcall(function()
    Settings(holder)
    return C_UnitAuras.AddPrivateAuraAnchor({
      unitToken = unit,
      auraIndex = 1,
      parent = holder,
      showCooldownFrame = false,
      showCooldownEdge = false,
      showCountdownNumbers = false,
      showDispelIcon = false,
      isContainer = true,
      iconInfo = {
        iconAnchor = { point = place, relativeTo = holder, relativePoint = place, offsetX = 0, offsetY = 0 },
        iconWidth = size, iconHeight = size, borderScale = 1,
      },
    })
  end)
  if ok and anchorID then
    button.gameAuraAnchor, button.gameAuraUnit = anchorID, unit
    stats.granted = stats.granted + 1
    return true
  end
  stats.refused = stats.refused + 1
  stats.lastError = (not ok) and tostring(anchorID) or "no anchor returned"
  return false
end

-- `force`: the settings changed, so every frame asks again rather than
-- keeping the anchor it already has.
function ns.ApplyGameAuras(force)
  ns.ForEachButton(function(button, unit)
    if force then ns.DetachGameAuras(button) end
    ns.AttachGameAuras(button, unit)
  end)
end

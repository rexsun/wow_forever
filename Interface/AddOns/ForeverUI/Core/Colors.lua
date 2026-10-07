local _, ns = ...

-- Every colour the UI uses, in one place. Modules ask for a name; nothing
-- hard-codes an r,g,b triple.

local colors = {}
ns.Colors = colors

colors.ui = {
  backdrop = { 0.08, 0.08, 0.10, 0.85 },
  border   = { 0.22, 0.22, 0.26, 1 },
  shadow   = { 0, 0, 0, 0.55 },
  accent   = { 0.30, 0.76, 1.00, 1 },
  neon     = { 0.10, 0.95, 1.00, 1 },   -- coordinates: meant to be seen
  text     = { 0.92, 0.92, 0.94, 1 },
  textDim  = { 0.62, 0.62, 0.66, 1 },
}

-- The accent -- the blue edge on every window, bar and tracker ForeverUI
-- draws -- is a setting. Modules take this TABLE by reference, so the change
-- is written into it rather than replacing it, and the borders already on
-- screen are repainted by Skin.RepaintAccent.
colors.defaultAccent = { 0.30, 0.76, 1.00, 1 }

function ns.ApplyAccentColor(rgb)
  rgb = rgb or (ns.db and ns.db.accentColor) or colors.defaultAccent
  local accent = colors.ui.accent
  accent[1], accent[2], accent[3] = rgb[1] or 0.30, rgb[2] or 0.76, rgb[3] or 1.00
  accent[4] = rgb[4] or 1
  if ns.Skin and ns.Skin.RepaintAccent then
    ns.Skin.RepaintAccent()
  end
  return accent
end

colors.status = {
  -- Experience is purple. Always.
  experience       = { 0.58, 0.26, 0.78, 1 },
  experienceRested = { 0.40, 0.22, 0.62, 0.70 },
  health      = { 0.20, 0.62, 0.28, 1 },
  healthDead  = { 0.35, 0.35, 0.35, 1 },
  healthLow   = { 0.75, 0.18, 0.18, 1 },
  incomingMine   = { 0.35, 1.00, 0.45, 0.75 },
  incomingOthers = { 0.10, 0.55, 0.25, 0.75 },
  absorb      = { 0.75, 0.80, 1.00, 0.60 },
  healAbsorb  = { 0.85, 0.25, 0.25, 0.60 },
  casting     = { 0.25, 0.55, 0.85, 1 },
  channeling  = { 0.30, 0.70, 0.60, 1 },
  uninterruptible = { 0.55, 0.55, 0.55, 1 },
}

-- The game grades how a unit feels about you on a scale of 1 to 8, and gives
-- each band a colour. These follow it: red attacks on sight, orange won't
-- start it but you can, yellow leaves you alone if you leave it alone, green
-- is on your side. Grey is separate -- see below.
colors.reaction = {
  hostile    = { 0.78, 0.25, 0.25, 1 },   -- 1-2, hated and hostile
  unfriendly = { 0.82, 0.45, 0.22, 1 },   -- 3, won't attack you first
  neutral    = { 0.85, 0.77, 0.36, 1 },   -- 4
  friendly   = { 0.31, 0.65, 0.35, 1 },   -- 5 and up
  -- Somebody else hit it first: no experience and no loot in it for you, and
  -- the game greys its health bar out to say so.
  tapped     = { 0.45, 0.45, 0.48, 1 },
}

colors.dispel = {
  Magic   = { 0.20, 0.60, 1.00, 1 },
  Curse   = { 0.60, 0.00, 1.00, 1 },
  Disease = { 0.60, 0.40, 0.00, 1 },
  Poison  = { 0.00, 0.60, 0.00, 1 },
}

-- Threat: no threat, gaining, losing it, holding it (tank).
colors.threat = {
  none    = { 0.65, 0.65, 0.65, 1 },
  gaining = { 0.90, 0.80, 0.30, 1 },
  losing  = { 0.95, 0.55, 0.20, 1 },
  holding = { 0.85, 0.25, 0.25, 1 },
}

-- Power types by their API name, so new ones can be added without code changes.
colors.power = {
  MANA        = { 0.25, 0.45, 0.85, 1 },
  RAGE        = { 0.78, 0.25, 0.25, 1 },
  FOCUS       = { 0.85, 0.55, 0.30, 1 },
  ENERGY      = { 0.90, 0.85, 0.35, 1 },
  RUNIC_POWER = { 0.35, 0.65, 0.85, 1 },
  UNKNOWN     = { 0.50, 0.50, 0.50, 1 },
}

-- In a group Forever hands out another player's class as a SECRET string,
-- and a secret can't be a table key (Colors.lua:92, 876 times in the owner's
-- first dungeon, 25 Sept 2026). The game's C_ClassColor.GetClassColor takes
-- one, and its colour can be painted but maybe not calculated with - so it is
-- only handed to callers that say they just paint (`paintOnly`); anyone
-- doing arithmetic on the colour gets the neutral grey instead.
local function IsSecret(value)
  if not issecretvalue then return false end
  local ok, secret = pcall(issecretvalue, value)
  return not ok or secret
end

function colors.Class(classFile, paintOnly)
  if classFile ~= nil and IsSecret(classFile) then
    if paintOnly and C_ClassColor and C_ClassColor.GetClassColor then
      local ok, r, g, b = pcall(function()
        return C_ClassColor.GetClassColor(classFile):GetRGB()
      end)
      if ok then return r, g, b, 1 end
    end
    return unpack(colors.ui.textDim)
  end
  local color = type(classFile) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if color then
    return color.r, color.g, color.b, 1
  end
  return unpack(colors.ui.textDim)
end

function colors.Power(powerToken)
  local color = colors.power[powerToken or "UNKNOWN"] or colors.power.UNKNOWN
  return unpack(color)
end

function colors.Get(group, key)
  local set = colors[group]
  local color = set and set[key]
  if not color then
    return unpack(colors.ui.text)
  end
  return unpack(color)
end
